{ config, pkgs, lib, ... }:

{
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

    table = "off";
    
    postUp = ''
      # Create custom routing table for selective routing
      ${pkgs.iproute2}/bin/ip route add default dev mullvad table 51820
      ${pkgs.iproute2}/bin/ip rule add fwmark 0x1 table 51820 priority 100
      
      # Mark service traffic for VPN routing
      ${pkgs.iptables}/bin/iptables -t mangle -A OUTPUT -m owner --uid-owner sonarr -j MARK --set-mark 0x1
      ${pkgs.iptables}/bin/iptables -t mangle -A OUTPUT -m owner --uid-owner radarr -j MARK --set-mark 0x1
      ${pkgs.iptables}/bin/iptables -t mangle -A OUTPUT -m owner --uid-owner prowlarr -j MARK --set-mark 0x1
      ${pkgs.iptables}/bin/iptables -t mangle -A OUTPUT -m owner --uid-owner qbittorrent -j MARK --set-mark 0x1
    '';
    
    preDown = ''
      ${pkgs.iproute2}/bin/ip rule del fwmark 0x1 table 51820 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -t mangle -D OUTPUT -m owner --uid-owner sonarr -j MARK --set-mark 0x1 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -t mangle -D OUTPUT -m owner --uid-owner radarr -j MARK --set-mark 0x1 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -t mangle -D OUTPUT -m owner --uid-owner prowlarr -j MARK --set-mark 0x1 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -t mangle -D OUTPUT -m owner --uid-owner qbittorrent -j MARK --set-mark 0x1 2>/dev/null || true
    '';
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