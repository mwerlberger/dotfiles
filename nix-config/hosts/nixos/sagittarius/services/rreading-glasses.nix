{ config, pkgs, pkgs-unstable, lib, ... }:

let
  # Run:   nix-prefetch-github blampe rreading-glasses
  # then fill in rev + hash below.
  rreading-glasses = pkgs-unstable.buildGoModule {
    pname = "rreading-glasses";
    version = "unstable-2025-01-01";

    src = pkgs.fetchFromGitHub {
      owner = "blampe";
      repo = "rreading-glasses";
      rev = "4b583285ceee48bd7fdbed1598377ff4d0771eea";
      hash = "sha256-7r717o18G0YcDmAT+FmgZtIQcUvdFb1SEdayqiLb5ZU=";
    };

    # Hardcover variant (rghc); use cmd/rgg for Goodreads (not recommended for fresh installs)
    subPackages = [ "cmd/rghc" ];

    # Upstream go.sum is incomplete; proxy fetches the missing transitive deps.
    proxyVendor = true;

    # Set to lib.fakeHash, run nixos-rebuild build, replace with hash from error output
    vendorHash = "sha256-4HdqCWS7o1tSfDXfrm0UF5otHCi2NU5YwqeIy9T9ris=";
  };

  port = 8788;
  dbName = "rreading_glasses";
  dbUser = "rreading_glasses";
in
{
  # PostgreSQL database — trust auth from localhost, no password secret required
  services.postgresql = {
    ensureDatabases = [ dbName ];
    ensureUsers = [
      {
        name = dbUser;
        ensureDBOwnership = true;
      }
    ];
    authentication = lib.mkAfter ''
      host ${dbName} ${dbUser} 127.0.0.1/32 trust
    '';
  };

  systemd.services.rreading-glasses = {
    description = "rreading-glasses — Readarr metadata service backed by Hardcover";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "postgresql.service" ];
    requires = [ "postgresql.service" ];

    serviceConfig = {
      DynamicUser = true;
      # Exposes the token file at $CREDENTIALS_DIRECTORY/hardcover-token
      # without putting it in /proc/<pid>/environ
      LoadCredential = [
        "hardcover-token:${config.age.secrets.hardcover-token.path}"
      ];
      Restart = "on-failure";
      RestartSec = "5s";
    };

    script = ''
      export HARDCOVER_AUTH="$(cat "$CREDENTIALS_DIRECTORY/hardcover-token")"
      export POSTGRES_HOST="127.0.0.1"
      export POSTGRES_USER="${dbUser}"
      export POSTGRES_DATABASE="${dbName}"
      export POSTGRES_PORT="5432"
      export PORT="${toString port}"
      exec ${rreading-glasses}/bin/rghc serve
    '';
  };
}
