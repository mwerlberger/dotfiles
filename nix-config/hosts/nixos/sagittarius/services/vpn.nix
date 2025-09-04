{ config, pkgs, lib, ... }:

{
  # Create network namespace for VPN-routed services
  systemd.services."netns-vpn" = {
    description = "Create VPN network namespace";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iproute2}/bin/ip netns add vpn";
      ExecStop = "${pkgs.iproute2}/bin/ip netns delete vpn";
    };
    unitConfig.ConditionPathExists = "!/var/run/netns/vpn";
  };

  # WireGuard VPN service in the network namespace
  systemd.services.wg-vpn = {
    description = "WireGuard VPN tunnel in network namespace";
    after = [ "netns-vpn.service" ];
    requires = [ "netns-vpn.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "wg-vpn-start" ''
        set -e
        
        # Clean up any existing interfaces
        ${pkgs.iproute2}/bin/ip link delete veth-host 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip -n vpn link delete wg-mullvad 2>/dev/null || true
        
        # Create veth pair for namespace communication
        ${pkgs.iproute2}/bin/ip link add veth-vpn type veth peer name veth-host
        ${pkgs.iproute2}/bin/ip link set veth-vpn netns vpn
        
        # Configure host side
        ${pkgs.iproute2}/bin/ip addr add 192.168.100.1/24 dev veth-host || true
        ${pkgs.iproute2}/bin/ip link set veth-host up
        
        # Configure namespace side
        ${pkgs.iproute2}/bin/ip -n vpn addr add 192.168.100.2/24 dev veth-vpn || true
        ${pkgs.iproute2}/bin/ip -n vpn link set veth-vpn up
        ${pkgs.iproute2}/bin/ip -n vpn link set lo up
        
        # Add default route through host
        ${pkgs.iproute2}/bin/ip -n vpn route add default via 192.168.100.1 || true
        
        # Create WireGuard interface in namespace
        ${pkgs.iproute2}/bin/ip -n vpn link add wg-mullvad type wireguard
        
        # Create WireGuard config without Address/DNS lines for wg setconf
        grep -E "^\[(Interface|Peer)\]|^PrivateKey|^PublicKey|^AllowedIPs|^Endpoint" ${config.age.secrets.mullvad-zrh.path} > /tmp/wg-config
        ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.wireguard-tools}/bin/wg setconf wg-mullvad /tmp/wg-config
        rm -f /tmp/wg-config
        
        ${pkgs.iproute2}/bin/ip -n vpn addr add 10.75.190.152/32 dev wg-mullvad || true
        ${pkgs.iproute2}/bin/ip -n vpn addr add fc00:bbbb:bbbb:bb01::c:be97/128 dev wg-mullvad || true
        ${pkgs.iproute2}/bin/ip -n vpn link set wg-mullvad up
        
        # Replace default route with VPN
        ${pkgs.iproute2}/bin/ip -n vpn route del default via 192.168.100.1 || true
        ${pkgs.iproute2}/bin/ip -n vpn route add default dev wg-mullvad || true
        
        # Add route back to host for local communication
        ${pkgs.iproute2}/bin/ip -n vpn route add 192.168.100.0/24 via 192.168.100.1 dev veth-vpn || true
      '';
      ExecStop = pkgs.writeShellScript "wg-vpn-stop" ''
        ${pkgs.iproute2}/bin/ip link delete veth-host || true
        ${pkgs.iproute2}/bin/ip -n vpn link delete wg-mullvad || true
      '';
    };
  };

  # Enable IP forwarding for namespace communication
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Firewall rules for namespace traffic
  networking.firewall.extraCommands = ''
    # Allow traffic between host and VPN namespace
    iptables -A INPUT -i veth-host -j ACCEPT
    iptables -A FORWARD -i veth-host -j ACCEPT
    iptables -A FORWARD -o veth-host -j ACCEPT
    
    # Allow reverse proxy access to ARR services in namespace
    iptables -A OUTPUT -o veth-host -j ACCEPT
    
    # NAT for namespace traffic (backup route)
    iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o ens3 -j MASQUERADE
  '';

  # Open firewall ports for ARR services (accessed via reverse proxy)
  networking.firewall.allowedTCPPorts = [
    8989  # Sonarr
    7878  # Radarr  
    9696  # Prowlarr
    8080  # qBittorrent
  ];
}