{
  config,
  pkgs,
  lib,
  ...
}:

let
  host = "sagittarius.taildb4b48.ts.net";
  tailscaleIp = "100.119.78.108";

  # Externally reachable (Tailscale only — this is financial data, no LAN vhost).
  fireflyPort = 8451;
  importerPort = 8452;

  # Loopback-only vhost. The data importer talks to the Firefly III *API* through
  # this one, because the public vhost is gated behind `tailscale_auth` and a
  # request from 127.0.0.1 carries no tailnet identity. The web UI is useless
  # here: with `remote_user_guard` and no X-Remote-User header nobody is ever
  # logged in, so only token-authenticated API calls get through.
  fireflyInternalPort = 8461;

  fireflyPkg = config.services.firefly-iii.package;
  importerPkg = config.services.firefly-iii-data-importer.package;
  importerUser = config.services.firefly-iii-data-importer.user;
  # Same interpreter php-fpm serves the importer with, so the CLI reads the very
  # same cached config (and therefore the same API token).
  importerPhp = "${importerPkg.phpPackage}/bin/php";

  fireflySocket = config.services.phpfpm.pools.firefly-iii.socket;
  importerSocket = config.services.phpfpm.pools.firefly-iii-data-importer.socket;

  # Disk-based import. The web UI is upload-only — `importer:auto-import` is the
  # only way to import from disk — so the layout is built around that command:
  #
  #   importDir/          scanned by auto-import: converted CSVs + _fallback.json
  #   importDir/inbox/    drop raw UBS e-banking exports here
  #   importDir/archive/  processed files are moved here after a successful run
  #
  # Raw exports are deliberately kept in a subdirectory: auto-import would
  # happily feed them through _fallback.json and mis-map every column. It only
  # scans one level deep, so a subdirectory is invisible to it.
  importDir = "/data/lake/documents/firefly-import";
  importInbox = "${importDir}/inbox";
  importArchive = "${importDir}/archive";

  # `firefly-import` — convert UBS exports and run the importer in one step.
  fireflyImport = pkgs.writeShellApplication {
    name = "firefly-import";
    runtimeInputs = [
      pkgs.python3
      pkgs.coreutils
    ];
    text = ''
      convert_only=0
      dry_run=0
      for arg in "$@"; do
        case "$arg" in
          --convert-only) convert_only=1 ;;
          --dry-run) dry_run=1 ;;
          -h|--help)
            cat <<'USAGE'
      firefly-import [--convert-only] [--dry-run]

      Converts every UBS CSV export in ${importInbox} into an importable CSV in
      ${importDir}, then runs the Firefly III data importer over that directory
      and moves what it processed into ${importArchive}.

      One-time setup: run an import through the web UI, download the config JSON
      and save it as ${importDir}/_fallback.json — it is applied to every file
      that has no same-named .json companion.
      USAGE
            exit 0 ;;
          *) echo "unknown argument: $arg" >&2; exit 2 ;;
        esac
      done

      shopt -s nullglob
      raw=(${importInbox}/*.csv ${importInbox}/*.CSV)
      if [ ''${#raw[@]} -eq 0 ]; then
        echo "no UBS exports in ${importInbox}"
      else
        echo "==> converting ''${#raw[@]} export(s)"
        for f in "''${raw[@]}"; do
          base=$(basename "$f" .csv); base=''${base%.CSV}
          out="${importDir}/$base-firefly.csv"
          if [ "$dry_run" = 1 ]; then
            echo "    would convert $(basename "$f") -> $(basename "$out")"
          else
            python3 ${./../../../../scripts/ubs-csv-to-firefly.py} "$f" -o "$out"
            mv -- "$f" "${importArchive}/$(basename "$f")"
          fi
        done
      fi

      [ "$convert_only" = 1 ] && exit 0

      if [ ! -f ${importDir}/_fallback.json ]; then
        echo "error: ${importDir}/_fallback.json is missing." >&2
        echo "       auto-import ignores any CSV without a config. Run one import" >&2
        echo "       through the web UI, download the JSON and save it there." >&2
        exit 1
      fi

      pending=(${importDir}/*-firefly.csv)
      if [ ''${#pending[@]} -eq 0 ]; then
        echo "nothing to import"
        exit 0
      fi

      if [ "$dry_run" = 1 ]; then
        echo "==> would import ''${#pending[@]} file(s):"
        printf '    %s\n' "''${pending[@]##*/}"
        exit 0
      fi

      echo "==> importing ''${#pending[@]} file(s)"
      sudo -u ${importerUser} ${importerPhp} \
        ${importerPkg}/artisan importer:auto-import ${importDir}

      for f in "''${pending[@]}"; do
        mv -- "$f" "${importArchive}/$(basename "$f")"
      done
      echo "==> moved processed files to ${importArchive}"
    '';
  };

  # Raise PHP's tiny defaults so a full-year CAMT.053 export can be uploaded.
  uploadLimits = {
    "php_admin_value[upload_max_filesize]" = "64M";
    "php_admin_value[post_max_size]" = "64M";
    "php_admin_value[memory_limit]" = "512M";
  };
in
{
  services.firefly-iii = {
    enable = true;
    virtualHost = "${host}:${toString fireflyPort}";
    poolConfig = uploadLimits;

    settings = {
      APP_ENV = "production";
      APP_KEY_FILE = config.age.secrets.firefly-iii-app-key.path;
      APP_URL = "https://${host}:${toString fireflyPort}";
      SITE_OWNER = "admin@werlberger.org";

      # Shared PostgreSQL instance, over the unix socket (peer auth).
      DB_CONNECTION = "pgsql";
      DB_HOST = "/run/postgresql";
      DB_DATABASE = "firefly-iii";
      DB_USERNAME = "firefly-iii";

      # Tailscale is the identity provider: Caddy's tailscale_auth plugin
      # rejects anything that isn't from the tailnet and injects the tailnet
      # login, which PHP-FPM exposes as $_SERVER['HTTP_X_REMOTE_USER'].
      # The first user to log in is auto-created and gets the owner role.
      AUTHENTICATION_GUARD = "remote_user_guard";
      AUTHENTICATION_GUARD_HEADER = "HTTP_X_REMOTE_USER";
      AUTHENTICATION_GUARD_EMAIL = "HTTP_X_REMOTE_EMAIL";
      # Caddy is the only thing in front of PHP-FPM, and it listens on a unix
      # socket, so every request is by definition proxied.
      TRUSTED_PROXIES = "*";

      DEFAULT_LANGUAGE = "en_US";
      DEFAULT_LOCALE = "de_CH";
      TZ = "Europe/Zurich";
      LOG_CHANNEL = "syslog";
    };
  };

  # UBS Switzerland has no self-service open-banking API (Swiss banks sit behind
  # SIX bLink, which needs a business contract), so the supported path is file
  # import: UBS E-Banking → Accounts → Export → "ISO 20022 (camt.053)". The data
  # importer parses camt.053/camt.052 natively; CSV export works too but needs
  # column mapping. Save the mapping as a config JSON afterwards to make repeat
  # imports one click.
  services.firefly-iii-data-importer = {
    enable = true;
    virtualHost = "${host}:${toString importerPort}";
    poolConfig = uploadLimits;

    settings = {
      APP_ENV = "production";
      APP_URL = "https://${host}:${toString importerPort}";
      LOG_CHANNEL = "syslog";
      TZ = "Europe/Zurich";
      TRUSTED_PROXIES = "*";

      # API calls bypass Caddy's tailscale_auth via the loopback vhost; VANITY_URL
      # is what the importer puts in links shown to the user.
      FIREFLY_III_URL = "http://127.0.0.1:${toString fireflyInternalPort}";
      VANITY_URL = "https://${host}:${toString fireflyPort}";
      EXPECT_SECURE_URL = false;

      # Personal Access Token from Firefly III → Options → Profile → OAuth.
      # See the bootstrap note at the bottom of this file.
      FIREFLY_III_ACCESS_TOKEN_FILE = config.age.secrets.firefly-iii-importer-token.path;

      IMPORT_DIR_ALLOWLIST = importDir;
      # Without this, auto-import needs a same-named .json beside every CSV and
      # silently skips the ones that lack it. With it, a single _fallback.json in
      # the directory covers them all — which is what makes the monthly run a
      # one-liner instead of a config-file-shuffling exercise.
      FALLBACK_IN_DIR = true;
    };
  };

  # `firefly-import` on PATH: convert UBS exports, then run the importer.
  environment.systemPackages = [ fireflyImport ];

  services.postgresql = {
    ensureDatabases = [ "firefly-iii" ];
    ensureUsers = [
      {
        name = "firefly-iii";
        ensureDBOwnership = true;
      }
    ];
  };

  # Caddy needs to reach both PHP-FPM sockets (mode 0660, owned by each app's
  # own group). Joining the groups is tighter than running PHP-FPM as `caddy`.
  users.users.caddy.extraGroups = [
    "firefly-iii"
    "firefly-iii-data-importer"
  ];

  # The importer has to walk /data/lake/documents (0770 mw:nas) to reach its own
  # directory, so it needs the group — owning the leaf directory is not enough.
  users.users.${importerUser}.extraGroups = [ "nas" ];

  # setgid (2770) so files dropped by you or over the Samba share inherit `nas`
  # and stay readable by the importer, instead of landing as <you>:users.
  systemd.tmpfiles.rules = [
    "d ${importDir} 2770 ${importerUser} nas - -"
    "d ${importInbox} 2770 ${importerUser} nas - -"
    "d ${importArchive} 2770 ${importerUser} nas - -"
  ];

  # The upstream module only orders after `postgresql.target`, which says nothing
  # about `postgresql-setup.service` having run — and that is what creates the
  # database. Without this, `firefly-iii:upgrade-database` can race it on a fresh
  # boot and fail its migrations.
  systemd.services.firefly-iii-setup = {
    after = [ "postgresql-setup.service" ];
    requires = [ "postgresql-setup.service" ];
    # Both setup units bake the secret into the app's cached config at start, and
    # upstream only triggers on the package. Without this, re-encrypting a secret
    # and switching leaves the old value live — the importer would keep using the
    # placeholder token and look broken for no visible reason.
    restartTriggers = [ config.age.secrets.firefly-iii-app-key.file ];
  };

  systemd.services.firefly-iii-data-importer-setup.restartTriggers = [
    config.age.secrets.firefly-iii-importer-token.file
  ];

  # LOCALE_ARCHIVE comes from systemd's DefaultEnvironment, so a locale rebuild
  # does not change the pool's unit file and nixos-rebuild would leave the old
  # archive in the running process — the de_CH monetary warning would survive the
  # switch. Tie the pool's restart to the archive it actually reads.
  systemd.services.phpfpm-firefly-iii.restartTriggers = [ config.i18n.glibcLocales ];

  services.caddy.virtualHosts = {
    # Firefly III over Tailscale
    "${host}:${toString fireflyPort}" = {
      extraConfig = ''
        bind ${tailscaleIp}
        tls {
          get_certificate tailscale
        }
        tailscale_auth set_headers
        root * ${fireflyPkg}/public
        php_fastcgi unix/${fireflySocket} {
          header_up X-Remote-User {http.request.header.Tailscale-User-Login}
          header_up X-Remote-Email {http.request.header.Tailscale-User-Login}
        }
        file_server
      '';
    };

    # Firefly III on loopback, for the data importer's API calls only.
    "http://127.0.0.1:${toString fireflyInternalPort}" = {
      extraConfig = ''
        bind 127.0.0.1
        root * ${fireflyPkg}/public
        php_fastcgi unix/${fireflySocket} {
          # Nothing authenticates here, so strip the identity headers: otherwise
          # any local process could send its own X-Remote-User and be logged in
          # as anybody. Token auth on /api is unaffected.
          header_up -X-Remote-User
          header_up -X-Remote-Email
        }
        file_server
      '';
    };

    # Data importer over Tailscale. It has no login of its own — the tailnet
    # check is the only thing standing in front of it.
    "${host}:${toString importerPort}" = {
      extraConfig = ''
        bind ${tailscaleIp}
        tls {
          get_certificate tailscale
        }
        tailscale_auth
        root * ${importerPkg}/public
        php_fastcgi unix/${importerSocket}
        file_server
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [
    fireflyPort
    importerPort
  ];

  # Bootstrap, in order:
  #   1. Deploy. secrets/firefly-iii-app-key.age already holds a generated key;
  #      secrets/firefly-iii-importer-token.age is still a placeholder.
  #   2. Open https://${host}:${toString fireflyPort} — the Tailscale login
  #      auto-creates the first user and gives it the owner role.
  #   3. Options → Profile → OAuth → "Create new Personal Access Token", then
  #        agenix -e secrets/firefly-iii-importer-token.age   # paste the token
  #      and redeploy (or: systemctl restart firefly-iii-data-importer-setup
  #      phpfpm-firefly-iii-data-importer).
  #   4. Import a UBS camt.053 export at https://${host}:${toString importerPort}.
  #
  # Note: the data importer ships a hardcoded Laravel APP_KEY upstream (it keeps
  # no persistent data), so its session cookies are not secret. `tailscale_auth`
  # is what actually protects it — do not expose that vhost to the LAN.
}
