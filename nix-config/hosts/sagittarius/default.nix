# hosts/nixos-vm/default.nix
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/default.nix
    ../../modules/shared/default.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "nixos-vm";
  time.timeZone = "Europe/Zurich";

  # Create your user
  users.users.mw = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # for sudo
  };
  
  # Install some packages system-wide
  environment.systemPackages = with pkgs; [
    vim
    curl
  ];

  system.stateVersion = "24.05";
}