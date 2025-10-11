{ config, pkgs, lib, ... }:

{
  # Enable Mullvad VPN service
  services.mullvad-vpn.enable = true;

  # WireGuard configuration running in VPN namespace
  # The namespace is created by services/vpn-namespace.nix
  networking.wg-quick.interfaces.mullvad = {
    privateKeyFile = config.age.secrets.mullvad-privatekey-ch-zrh-505.path;
    address = [ "10.73.245.111/32" "fc00:bbbb:bbbb:bb01::a:f56e/128" ];
    dns = [ "10.64.0.1" ];

    peers = [{
      publicKey = "dc16Gcid7jLcHRD7uHma1myX3vWhEy/bZIBtqZw0B2I=";
      endpoint = "146.70.134.2:51820";
      # Route all traffic through VPN when in namespace
      allowedIPs = [ "0.0.0.0/0" "::/0" ];
      persistentKeepalive = 25;
    }];

    # Custom postUp to set routing properly in namespace
    # wg-quick creates policy routing by default, we simplify to use main table
    postUp = ''
      # These commands run inside the vpn namespace due to NetworkNamespacePath

      # Remove wg-quick's policy routing setup (we want simpler main table routing)
      ${pkgs.iproute2}/bin/ip route del default dev mullvad table 51820 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -6 route del default dev mullvad table 51820 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del not fwmark 51820 table 51820 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -6 rule del not fwmark 51820 table 51820 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip rule del table main suppress_prefixlength 0 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip -6 rule del table main suppress_prefixlength 0 2>/dev/null || true

      # Set simple default route in main table to go through WireGuard
      ${pkgs.iproute2}/bin/ip route add default dev mullvad || true

      # Keep explicit route to veth for host communication
      ${pkgs.iproute2}/bin/ip route add 10.200.200.0/24 dev veth-vpn || true
    '';

    preDown = ''
      # These commands run inside the vpn namespace
      ${pkgs.iproute2}/bin/ip route del default dev mullvad 2>/dev/null || true
    '';
  };

  # Configure WireGuard service to run in the VPN namespace
  systemd.services.wg-quick-mullvad = {
    after = [ "vpn-namespace.service" ];
    requires = [ "vpn-namespace.service" ];
    bindsTo = [ "vpn-namespace.service" ];

    serviceConfig = {
      NetworkNamespacePath = "/run/netns/vpn";
    };
  };

  # Firewall rules for WireGuard
  networking.firewall.allowedUDPPorts = [ 51820 ];

  # Additional kernel parameters for VPN and namespace support
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 0;
    "net.ipv4.conf.default.rp_filter" = 0;
  };
}