{ config, pkgs, lib, ... }:

{
  networking.hostId = "5A6AE005"; # Must be set to a unique 8-char hex string for ZFS
  networking.hostName = "sagittarius"; # Define your hostname.

  networking.interfaces.enp5s0 = {
    ipv4.addresses = [
      {
        address = "192.168.1.206";
        prefixLength = 24;
      }
    ];
    ipv6.addresses = [
      {
        address = "2a02:168:ff46::10";
        prefixLength = 64;
      }
    ];
  };

  networking.interfaces.enp6s0 = {
    ipv4.addresses = [
      {
        address = "192.168.2.207";
        prefixLength = 24;
      }
    ];
  };

  networking.defaultGateway = "192.168.1.1";

    # Custom routing tables
  networking.iproute2 = {
    enable = true;
    rttablesExtraConfig = ''
      201 enp6s0
    '';
  };

  # Source-based routing
  networking.localCommands = ''
    # Add default route for enp6s0 traffic
    ip route add default via 192.168.2.1 dev enp6s0 table enp6s0
    ip rule add from 192.168.2.207 table enp6s0
    
    # Also add local subnet route to enp6s0 table
    ip route add 192.168.2.0/24 dev enp6s0 table enp6s0
  '';

  # Enable IP forwarding for VPN subnet
  # boot.kernel.sysctl."net.ipv4.ip_forward" = true;
  
  # DNS configuration for VPN
  networking.nameservers = [ "192.168.1.1" "8.8.8.8" ];  # Primary DNS
  
  networking.firewall.allowedTCPPorts = [
    22
    445
    139 # Samba
    8444  # Immich local LAN access
  ];
  networking.firewall.allowedUDPPorts = [
    137
    138 # Samba
  ];
}