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
  #   importDir/          scanned by auto-import: converted CSV + its .json
  #   importDir/inbox/    drop raw UBS e-banking exports here
  #   importDir/archive/  processed files are moved here after a successful run
  #
  # Raw exports are deliberately kept in a subdirectory: auto-import would
  # happily feed them through and mis-map every column. It only scans one level
  # deep, so a subdirectory is invisible to it.
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

      Converts every UBS CSV export in ${importInbox} into one importable CSV in
      ${importDir}, then runs the Firefly III data importer over that directory
      and moves what it processed into ${importArchive}.

      All exports are converted in a SINGLE pass on purpose. Incoming transfers
      carry no counterparty IBAN, and the only thing tying the two sides of an
      internal transfer together is a shared Transaktions-Nr. — which the
      converter can only see when both statements are in the same batch. Convert
      the whole period for every account at once, or the credit sides import as
      deposits from revenue accounts named after their account holder.

      Always run --convert-only first and read the report: it reconciles each
      statement against its own Anfangssaldo/Schlusssaldo and lists the credits
      it could not explain.
      USAGE
            exit 0 ;;
          *) echo "unknown argument: $arg" >&2; exit 2 ;;
        esac
      done

      shopt -s nullglob
      raw=(${importInbox}/*.csv ${importInbox}/*.CSV)
      stamp=$(date +%Y%m%d-%H%M%S)
      # Deliberately not "ubs-*": raw exports are named by the bank or by you
      # (ubs-cc.csv), and a cleanup glob over the converter's own output must
      # not be able to match one of those. Ask how this comment came to exist.
      out="${importDir}/firefly-batch-$stamp.csv"

      if [ ''${#raw[@]} -eq 0 ]; then
        echo "no UBS exports in ${importInbox}"
      elif [ "$dry_run" = 1 ]; then
        echo "==> would convert ''${#raw[@]} export(s) into $(basename "$out")"
        printf '    %s\n' "''${raw[@]##*/}"
      else
        echo "==> converting ''${#raw[@]} export(s) into $(basename "$out")"
        # One invocation with every file: this is what makes transfer pairing
        # possible. A failure here (a statement that does not reconcile) leaves
        # the inbox untouched so it can be re-run after fixing the export.
        python3 ${./../../../../scripts/ubs-csv-to-firefly.py} "''${raw[@]}" -o "$out"
        for f in "''${raw[@]}"; do
          mv -- "$f" "${importArchive}/$(basename "$f")"
        done
      fi

      [ "$convert_only" = 1 ] && exit 0

      pending=(${importDir}/firefly-batch-*.csv)
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
      # auto-import exits non-zero if it skipped ANY row, and a row already in
      # Firefly ([a115]) counts as skipped. Re-importing a file you already
      # imported is normal here, so that alone must not look like a failure —
      # but a validation problem ([a117] and friends) must.
      log=$(mktemp)
      trap 'rm -f "$log"' EXIT
      set +e
      sudo -u ${importerUser} ${importerPhp} \
        ${importerPkg}/artisan importer:auto-import ${importDir} 2>&1 | tee "$log"
      set -e
      if grep -oE '\[a[0-9]+\]' "$log" | grep -qv 'a115'; then
        echo "==> import reported problems other than duplicates; see above" >&2
        exit 1
      fi
      dupes=$(grep -c 'a115' "$log" || true)
      [ "$dupes" -gt 0 ] && echo "==> $dupes row(s) already present, skipped"

      for f in "''${pending[@]}"; do
        mv -- "$f" "${importArchive}/$(basename "$f")"
        [ -f "''${f%.csv}.json" ] && mv -- "''${f%.csv}.json" "${importArchive}/"
      done
      echo "==> moved processed files to ${importArchive}"
      echo "    verify with: firefly-verify.sh ${importArchive}/*.csv"
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
  # import: UBS E-Banking → Konten → Bewegungen → Export → CSV.
  #
  # CSV is the only usable format. camt.053, which the importer parses natively
  # and which carries structured counterparty accounts, is not offered for these
  # private accounts. MT940 is — but it has no counterparty IBANs at all, no
  # purchase dates, no FX detail, and drops transactions outright (47 entries
  # against 60 CSV rows on one statement). See scripts/ubs-csv-to-firefly.py.
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
      # auto-import pairs each CSV with a same-named .json, and the converter
      # emits exactly that — built from the column list it just wrote, so the
      # roles can never drift from the file they describe. The directory-wide
      # _fallback.json this used to rely on was maintained by hand and would
      # silently mis-map every column once the converter changed.
      FALLBACK_IN_DIR = false;
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

  # Bootstrap, in order (steps 1-3 are done on this host):
  #   1. Deploy. secrets/firefly-iii-app-key.age holds the generated key.
  #   2. Open https://${host}:${toString fireflyPort} — the Tailscale login
  #      auto-creates the first user and gives it the owner role.
  #   3. Options → Profile → OAuth → "Create new Personal Access Token", then
  #        agenix -e secrets/firefly-iii-importer-token.age   # paste the token
  #      and redeploy (or: systemctl restart firefly-iii-data-importer-setup
  #      phpfpm-firefly-iii-data-importer).
  #   4. Seed the accounts, then set their opening balances from the earliest
  #      export of each — both read tables kept outside this public repo:
  #        scripts/firefly-accounts.sh
  #        scripts/firefly-opening-balances.sh --force ${importInbox}/*.csv
  #   5. Drop every account's export for the period into ${importInbox} and
  #        firefly-import --convert-only   # read the reconciliation report
  #        firefly-import
  #        scripts/firefly-verify.sh ${importArchive}/*.csv
  #   6. Categories: scripts/firefly-rules.sh, then apply the rule group to the
  #      transactions already imported (Rules → group → "Apply rule group").
  #
  # `scripts/firefly-undo-import.sh TAG` deletes an import by its tag, so a bad
  # run is fully reversible.
  #
  # Note: the data importer ships a hardcoded Laravel APP_KEY upstream (it keeps
  # no persistent data), so its session cookies are not secret. `tailscale_auth`
  # is what actually protects it — do not expose that vhost to the LAN.
}
