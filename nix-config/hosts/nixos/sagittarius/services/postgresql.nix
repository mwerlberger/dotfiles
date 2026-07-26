{ config, pkgs, lib, ... }:

{
  # PostgreSQL database server
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;

    # Extensions required for Immich (VectorChord for vector search)
    extensions = with pkgs.postgresql16Packages; [
      pgvector
      vectorchord
    ];
  };
}
