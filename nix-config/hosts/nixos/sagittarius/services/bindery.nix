{ config, pkgs, pkgs-unstable, lib, ... }:

let
  version = "1.34.0";

  src = pkgs.fetchFromGitHub {
    owner = "vavallee";
    repo = "bindery";
    rev = "v${version}";
    hash = "sha256-rOOaSuSReWMhChhiod7syu8r7KhqsiPO4sILHLvBDg8=";
  };

  # The React frontend is built separately and embedded into the Go binary at
  # compile time — upstream's Dockerfile builds web/ with npm and copies the
  # result to internal/webui/dist before `go build`. buildNpmPackage works off
  # the committed package-lock.json; no mkYarnPackage, which is what stranded
  # Bookshelf on nixpkgs 26.05.
  bindery-web = pkgs-unstable.buildNpmPackage {
    pname = "bindery-web";
    inherit version src;
    sourceRoot = "${src.name}/web";

    # Set to lib.fakeHash, build, then copy the hash from the error output.
    npmDepsHash = "sha256-+0y4u9ZmaPUbPC97elc+ClvVjm0WZAU50XC3ryJmpyo=";

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

  bindery = pkgs-unstable.buildGoModule {
    pname = "bindery";
    inherit version src;

    # Same procedure as npmDepsHash above.
    vendorHash = "sha256-GIIr7/owPoEyH1B5On0xO2c7+fAQbvDDBn15toHaglA=";

    subPackages = [ "cmd/bindery" ];

    preBuild = ''
      mkdir -p internal/webui/dist
      cp -r ${bindery-web}/. internal/webui/dist/
    '';

    ldflags = [
      "-s"
      "-w"
      "-X main.version=${version}"
    ];

    meta = {
      description = "Automated ebook and audiobook download manager (Readarr replacement)";
      homepage = "https://github.com/vavallee/bindery";
      license = lib.licenses.mit;
      mainProgram = "bindery";
    };
  };

  port = 8787;
  dataDir = "/var/lib/bindery";
  mediaDir = "/data/lake/media";
in
{
  users.users.bindery = {
    isSystemUser = true;
    group = "bindery";
    # "nas" owns /data/lake, so this is what lets Bindery import into the library.
    extraGroups = [ "nas" ];
    home = dataDir;
  };
  users.groups.bindery = { };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 bindery bindery - -"
  ];

  systemd.services.bindery = {
    description = "Bindery — ebook & audiobook automation";
    wantedBy = [ "multi-user.target" ];
    after = [
      "vpn-namespace.service"
      "wg-quick-mullvad.service"
      "network.target"
    ];
    requires = [ "vpn-namespace.service" ];
    # Stop rather than leak: no tunnel, no indexer traffic.
    bindsTo = [ "wg-quick-mullvad.service" ];

    environment = {
      BINDERY_PORT = toString port;
      BINDERY_DATA_DIR = dataDir;
      BINDERY_DB_PATH = "${dataDir}/bindery.db";

      BINDERY_LIBRARY_DIR = "${mediaDir}/books";
      BINDERY_AUDIOBOOK_DIR = "${mediaDir}/audiobooks";
      BINDERY_DOWNLOAD_DIR = "${mediaDir}/downloads/complete";

      # Caddy runs on the host and reaches this namespace over the veth pair, so
      # requests arrive from the host-side address.
      BINDERY_TRUSTED_PROXY = "10.200.200.1";
      # Matches the header the Caddy vhost below injects from the tailnet
      # identity, same arrangement as Navidrome. Note that these two only take
      # effect once the auth *mode* is switched to "proxy" in Settings — it is a
      # stored setting, not an env var, and it defaults to "enabled" (Bindery's
      # own login). Until then Caddy's tailscale_auth is the only gate, which is
      # still a real one.
      BINDERY_PROXY_AUTH_HEADER = "Remote-User";

      # Opt out before the first ping; checked ahead of any database setting.
      # Must be the exact string "true".
      BINDERY_TELEMETRY_DISABLED = "true";

      # Prowlarr lives in this same namespace, so the Torznab download links it
      # hands back point at loopback. Bindery treats indexer-supplied download
      # URLs as untrusted data and blocks loopback for them by default (a hostile
      # indexer could otherwise aim a grab at 127.0.0.1); without this opt-in the
      # indexer sync succeeds but every grab fails. Safe here: nothing else runs
      # in this namespace. Link-local and cloud-metadata stay blocked regardless.
      BINDERY_DOWNLOAD_ALLOW_LOOPBACK = "1";
    };

    serviceConfig = {
      User = "bindery";
      Group = "bindery";
      NetworkNamespacePath = "/run/netns/vpn";
      ExecStart = lib.getExe bindery;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Reachable at https://sagittarius.taildb4b48.ts.net:8787 — the port Readarr
  # and then Bookshelf used, so old bookmarks keep working.
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:${toString port}" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 10.200.200.2:${toString port} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up Remote-User {http.request.header.Tailscale-User-Login}
      }
    '';
  };

  # First run (all of this is configured in the web UI, nothing else to declare):
  #   1. Settings → Download Clients: qBittorrent at 127.0.0.1:8081 and SABnzbd
  #      at 127.0.0.1:8085 — both are localhost from inside the VPN namespace.
  #   2. Settings → Indexers: add a Prowlarr instance at http://127.0.0.1:9696
  #      with Prowlarr's API key and hit Sync. Bindery pulls the indexer list
  #      itself (GET /api/v1/indexer) — do NOT try to add Bindery under
  #      Prowlarr's own "Apps", which only supports the official *arr apps.
  #      Only indexers carrying book/audiobook categories are kept; the rest are
  #      skipped with a debug-level log and no visible error.
  #   3. Settings → Metadata: OpenLibrary works unauthenticated. Hardcover needs
  #      the token from secrets/hardcover-token.age (the one rreading-glasses
  #      used) pasted in — there is no env var for it outside upstream's test
  #      suite — and Audnex/Audible cover the audiobook side.
  #   5. Settings → Auth: switch the mode to "proxy" to accept the tailnet
  #      identity Caddy forwards, instead of maintaining a separate password.
  #   4. Root folders are pre-set from the environment above; confirm they
  #      resolved to ${mediaDir}/books and ${mediaDir}/audiobooks.
  # Migrating an existing Readarr database: see docs/Migrating-From-Readarr-Wiki.md
  # upstream — not applicable here, Readarr's state was already dropped.
}
