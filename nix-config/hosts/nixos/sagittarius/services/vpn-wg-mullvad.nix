{ config, pkgs, lib, ... }:

{
  # Create VPN network namespace for *arr services
  systemd.services.vpn-namespace = {
    description = "Create VPN network namespace for *arr services";
    wantedBy = [ "multi-user.target" ];
    before = [ "radarr.service" "sonarr.service" "prowlarr.service" "qbittorrent.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = with pkgs; [ iproute2 iptables coreutils ];
    script = ''
      # Clean up any existing resources first
      ${pkgs.iproute2}/bin/ip netns del vpn 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link del veth-host 2>/dev/null || true
      
      # Create network namespace
      ${pkgs.iproute2}/bin/ip netns add vpn
      
      # Create veth pair to connect namespace to host
      ${pkgs.iproute2}/bin/ip link add veth-host type veth peer name veth-vpn
      
      # Move one end to the namespace
      ${pkgs.iproute2}/bin/ip link set veth-vpn netns vpn
      
      # Configure host side
      ${pkgs.iproute2}/bin/ip addr add 192.168.100.1/24 dev veth-host
      ${pkgs.iproute2}/bin/ip link set veth-host up
      
      # Configure namespace side
      ${pkgs.iproute2}/bin/ip netns exec vpn ip addr add 192.168.100.2/24 dev veth-vpn
      ${pkgs.iproute2}/bin/ip netns exec vpn ip link set veth-vpn up
      ${pkgs.iproute2}/bin/ip netns exec vpn ip link set lo up
      ${pkgs.iproute2}/bin/ip netns exec vpn ip route add default via 192.168.100.1
      
      # Enable IP forwarding and NAT for the namespace
      echo 1 > /proc/sys/net/ipv4/ip_forward
      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o mullvad -j MASQUERADE 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -A FORWARD -i veth-host -o mullvad -j ACCEPT 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -A FORWARD -i mullvad -o veth-host -j ACCEPT 2>/dev/null || true
    '';
    
    preStop = ''
      # Clean up namespace
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 192.168.100.0/24 -o mullvad -j MASQUERADE 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D FORWARD -i veth-host -o mullvad -j ACCEPT 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D FORWARD -i mullvad -o veth-host -j ACCEPT 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link del veth-host 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip netns del vpn 2>/dev/null || true
    '';
  };

  # Simple WireGuard configuration for the host
  networking.wg-quick.interfaces.mullvad = {
    address = [ "10.66.146.127/32" "fc00:bbbb:bbbb:bb01::3:927e/128" ];
    dns = [ "10.64.0.1" ];
    privateKeyFile = "/etc/wireguard/mullvad.key";
    
    peers = [{
      publicKey = "gSLSfY2zNFRczxHndeda258z+ayMvd7DqTlKYlKWJUo=";
      allowedIPs = [ "0.0.0.0/0" "::0/0" ];
      endpoint = "46.19.136.226:51820";
      persistentKeepalive = 25;
    }];

    # Don't manage routing automatically
    table = "off";
  };

  # Create key file with proper permissions
  systemd.services.mullvad-key-setup = {
    description = "Setup Mullvad WireGuard private key";
    wantedBy = [ "multi-user.target" ];
    before = [ "wg-quick-mullvad.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /etc/wireguard
      echo "oPvFxz1LYsTllIPnLZ3rpArp6hf99rAeafoyyi5RpVg=" > /etc/wireguard/mullvad.key
      chmod 600 /etc/wireguard/mullvad.key
      chown root:root /etc/wireguard/mullvad.key
    '';
  };

  networking.firewall.allowedTCPPorts = [
    8989 7878 9696 8080
  ];
}