{ config, pkgs, lib, ... }:

{
  # PostgreSQL database server
  services.postgresql = {
    enable = true;

    # Extensions required for Immich (VectorChord for vector search)
    extensions = with pkgs.postgresql16Packages; [
      pgvector
      vectorchord
    ];

    # Load vector extensions at startup
    settings = {
      shared_preload_libraries = "vchord.so";
    };

    # Ensure PostgreSQL is ready for Nextcloud and other services
    ensureDatabases = [ "nextcloud" ];
    ensureUsers = [
      {
        name = "nextcloud";
        ensureDBOwnership = true;
      }
    ];
  };
}
