{ config, pkgs, lib, ... }:

{
  # Enable Mullvad VPN service
  services.mullvad-vpn.enable = true;
  
  # Enable systemd-resolved (required for Mullvad VPN DNS to work properly)
  services.resolved.enable = true;
  services.resolved.dnssec = "true";
  services.resolved.domains = [ "~." ];
  services.resolved.fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
  
  # WireGuard configuration for enp6s0-specific routing
  networking.wg-quick.interfaces.mullvad = {
    # You'll need to get these from your Mullvad account
    # Generate WireGuard config at: https://mullvad.net/en/account/#/wireguard-config
    privateKey = "qCkNGHWFIokKTAdU8mPBTqYDUmyyGTh2UM7cAHnjvGg=";
    address = [ "10.73.245.111/32" "fc00:bbbb:bbbb:bb01::a:f56e/128" ];
    dns = [ "10.64.0.1" ]; # Mullvad DNS server
    
    peers = [{
      publicKey = "dc16Gcid7jLcHRD7uHma1myX3vWhEy/bZIBtqZw0B2I=";
      endpoint = "146.70.134.2:51820";
      # Allow all traffic except LAN subnets
      allowedIPs = [ 
        "0.0.0.0/5" "8.0.0.0/7" "11.0.0.0/8" "12.0.0.0/6" "16.0.0.0/4"
        "32.0.0.0/3" "64.0.0.0/2" "128.0.0.0/3" "160.0.0.0/5" "168.0.0.0/6"
        "172.0.0.0/12" "172.32.0.0/11" "172.64.0.0/10" "172.128.0.0/9"
        "173.0.0.0/8" "174.0.0.0/7" "176.0.0.0/4" "192.0.0.0/9"
        "192.128.0.0/11" "192.160.0.0/13" "192.169.0.0/16" "192.170.0.0/15"
        "192.172.0.0/14" "192.176.0.0/12" "192.192.0.0/10" "193.0.0.0/8"
        "194.0.0.0/7" "196.0.0.0/6" "200.0.0.0/5" "208.0.0.0/4"
        "::/0"
      ];
      persistentKeepalive = 25;
    }];
    
    # Use the existing VPN routing table
    table = "200";
    
    postUp = ''
      # Add rule to route traffic from enp6s0 through VPN with higher priority than LAN
      ${pkgs.iproute2}/bin/ip rule add from 192.168.2.207 table 200 priority 100
      
      # Route traffic coming from enp6s0 interface through VPN
      ${pkgs.iproute2}/bin/ip rule add iif enp6s0 table 200 priority 101
      
      # Ensure LAN traffic from enp6s0 stays local (higher priority = lower number)
      ${pkgs.iproute2}/bin/ip rule add from 192.168.2.207 to 192.168.1.0/24 table enp6s0 priority 50
      ${pkgs.iproute2}/bin/ip rule add from 192.168.2.207 to 192.168.2.0/24 table enp6s0 priority 51
      
      # Allow access to common private networks
      ${pkgs.iproute2}/bin/ip rule add from 192.168.2.207 to 10.0.0.0/8 table enp6s0 priority 52
      ${pkgs.iproute2}/bin/ip rule add from 192.168.2.207 to 172.16.0.0/12 table enp6s0 priority 53
    '';
    
    preDown = ''
      # Clean up VPN rules
      ${pkgs.iproute2}/bin/ip rule del from 192.168.2.207 table 200 priority 100 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del iif enp6s0 table 200 priority 101 2>/dev/null || true
      
      # Clean up LAN rules
      ${pkgs.iproute2}/bin/ip rule del from 192.168.2.207 to 192.168.1.0/24 table enp6s0 priority 50 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del from 192.168.2.207 to 192.168.2.0/24 table enp6s0 priority 51 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del from 192.168.2.207 to 10.0.0.0/8 table enp6s0 priority 52 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del from 192.168.2.207 to 172.16.0.0/12 table enp6s0 priority 53 2>/dev/null || true
    '';
  };
  
  # Firewall rules for WireGuard
  networking.firewall.allowedUDPPorts = [ 51820 ];
  
  # Additional kernel parameters for VPN
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };
}