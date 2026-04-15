{ config, pkgs, lib, ... }:

let
  bookshelfSrc = pkgs.fetchFromGitHub {
    owner = "pennydreadful";
    repo = "Bookshelf";
    rev = "c21c4134fdb710481ed69db05bf943b0acdbbf60";
    hash = "sha256-dHQLZVFKvOz7BD6C7qxmlns0eDgLD/+K6CLMWF1f+cQ=";
  };

  bookshelfUi = pkgs.mkYarnPackage {
    pname = "bookshelf-ui";
    version = "0.0.1";
    src = bookshelfSrc;
    buildPhase = ''
      export HOME=$(mktemp -d)
      cd deps/readarr
      yarn --offline build
    '';
    installPhase = ''
      mkdir -p $out
      cp -r _output/UI/* $out/
    '';
    distPhase = "true";
  };

  # Run:   nix-prefetch-github pennydreadful Bookshelf
  # then fill in rev + hash below.
  # Re-generate bookshelf-deps.json whenever rev changes.
  bookshelf = pkgs.buildDotnetModule {
    pname = "bookshelf";
    version = "0.0.1";

    src = bookshelfSrc;

    projectFile = [
      "src/NzbDrone.Console/Readarr.Console.csproj"
      "src/NzbDrone.Mono/Readarr.Mono.csproj"
    ];
    nugetDeps = ./bookshelf-deps.json;

    dotnet-sdk = pkgs.dotnetCorePackages.sdk_8_0;
    dotnet-runtime = pkgs.dotnetCorePackages.aspnetcore_6_0;

    # Upstream uses wildcard version strings (e.g. '10.0.0.*') which are
    # incompatible with .NET's Deterministic build flag that Nix enables.
    # The version must also satisfy the "official build" check in RuntimeInfo.cs:
    # Major < 10 and Revision <= 10000, otherwise Bookshelf runs in
    # "developer mode" which blocks HTTP redirects needed for NZB downloads.
    dotnetFlags = [ "/p:Deterministic=false" "/p:AssemblyVersion=1.0.0.0" ];

    # The csproj uses <TargetFrameworks> (plural) which triggers cross-targeting
    # mode and requires an explicit framework for publish.
    dotnetBuildFlags = [ "-f" "net6.0" ];
    dotnetInstallFlags = [ "-f" "net6.0" ];

    executables = [ "Readarr" ];

    runtimeDeps = with pkgs; [ sqlite icu ];

    # Bookshelf expects a UI/ folder next to the binary for the web frontend.
    postInstall = ''
      mkdir -p $out/lib/bookshelf/UI
      cp -r ${bookshelfUi}/* $out/lib/bookshelf/UI/
    '';

    meta = {
      description = "Readarr fork for monitoring and organising book collections";
      homepage = "https://github.com/pennydreadful/Bookshelf";
      license = lib.licenses.gpl3Only;
      mainProgram = "Readarr";
    };
  };

  dataDir = "/var/lib/bookshelf";
  port = 8787;
in
{
  users.users.bookshelf = {
    isSystemUser = true;
    group = "bookshelf";
    extraGroups = [ "nas" ];
    home = dataDir;
  };
  users.groups.bookshelf = { };

  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 bookshelf bookshelf - -"
  ];

  systemd.services.bookshelf = {
    description = "Bookshelf — book collection manager (Readarr fork)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "vpn-namespace.service"
      "wg-quick-mullvad.service"
      "network.target"
      "rreading-glasses.service"
    ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "wg-quick-mullvad.service" ];

    serviceConfig = {
      User = "bookshelf";
      Group = "bookshelf";
      NetworkNamespacePath = "/run/netns/vpn";
      ExecStart = "${bookshelf}/bin/Readarr -nobrowser -data ${dataDir}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  # Bookshelf runs inside the VPN namespace and therefore cannot reach 127.0.0.1 on the host.
  # Configure the metadata URL in Bookshelf → Settings → General to:
  #   http://10.200.200.1:8788
  # (10.200.200.1 is the host-side veth interface, reachable from inside the VPN namespace)
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:${toString port}" = {
    extraConfig = ''
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 10.200.200.2:${toString port} {
        header_up Host {http.request.host}
        header_up X-Real-IP {http.request.remote.host}
        header_up X-Forwarded-For {http.request.remote.host}
        header_up X-Forwarded-Proto {http.request.scheme}
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
        header_up Remote-User {http.request.header.Tailscale-User-Login}
      }
    '';
  };
}
