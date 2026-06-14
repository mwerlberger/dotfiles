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

    # Note: Nextcloud's database + role are created by its own module
    # (services.nextcloud.database.createLocally = true).
  };
}
