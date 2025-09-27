{ config, pkgs, lib, ... }:

{
  networking.hostId = "5A6AE005";
  networking.hostName = "sagittarius";

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
      200 vpn
    '';
  };

  # Enable WireGuard and networking
  networking.wireguard.enable = true;
  boot.kernel.sysctl = {
    "net.ipv4.conf.enp6s0.rp_filter" = 0;
    "net.ipv4.ip_forward" = true;
  };

  # Remove the problematic systemd service - use networking.localCommands instead
  # systemd.services.setup-enp6s0-routing = lib.mkForce {};

  # # Source-based routing (this seems to work from your earlier tests)
  # networking.localCommands = ''
  #   # Clean up any existing rules first
  #   ip rule del from 192.168.2.207 table enp6s0 2>/dev/null || true
  #   ip route flush table enp6s0 2>/dev/null || true
    
  #   # Add routing for enp6s0
  #   ip route add default via 192.168.2.1 dev enp6s0 table enp6s0
  #   ip route add 192.168.2.0/24 dev enp6s0 table enp6s0
  #   ip rule add from 192.168.2.207 table enp6s0
  # '';

  systemd.services.setup-enp6s0-routing = {
    description = "Setup routing for enp6s0 with VPN support";
    after = [ "network-online.target" "systemd-resolved.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "setup-enp6s0-routing" ''
        # Wait for interface to be ready
        while ! ${pkgs.iproute2}/bin/ip link show enp6s0 | grep -q "state UP"; do
          sleep 1
        done
        
        # Clean up existing rules for enp6s0 table
        ${pkgs.iproute2}/bin/ip rule del from 192.168.2.207 table enp6s0 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip route flush table enp6s0 2>/dev/null || true
        
        # Setup basic enp6s0 routing (for LAN access and fallback)
        ${pkgs.iproute2}/bin/ip route add default via 192.168.2.1 dev enp6s0 table enp6s0
        ${pkgs.iproute2}/bin/ip route add 192.168.1.0/24 via 192.168.2.1 dev enp6s0 table enp6s0
        ${pkgs.iproute2}/bin/ip route add 192.168.2.0/24 dev enp6s0 table enp6s0
        
        # Add fallback rule with lower priority (higher number) than VPN rules
        ${pkgs.iproute2}/bin/ip rule add from 192.168.2.207 table enp6s0 priority 300
        
        # Add static ARP entries for gateway
        ${pkgs.iproute2}/bin/ip neigh add 8.8.8.8 lladdr 70:a7:41:b6:f3:21 dev enp6s0 || true
        ${pkgs.iproute2}/bin/ip neigh add 1.1.1.1 lladdr 70:a7:41:b6:f3:21 dev enp6s0 || true
      '';
    };
  };

  # DNS will be handled by systemd-resolved (required for Mullvad VPN)
  # networking.nameservers = [ "192.168.1.1" "8.8.8.8" ];
  
  networking.firewall.allowedTCPPorts = [
    22 445 139 8444
  ];
  networking.firewall.allowedUDPPorts = [
    137 138 51820  # Add WireGuard port
  ];
}