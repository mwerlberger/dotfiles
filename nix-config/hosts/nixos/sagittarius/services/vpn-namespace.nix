{ config, pkgs, ... }:

{
  # Create the VPN network namespace
  # This service only creates the namespace and veth pair
  # It does NOT modify host networking or DNS
  systemd.services.vpn-namespace = {
    description = "VPN Network Namespace";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStopSec = "15s";
    };

    script = ''
      set -e

      # Create namespace if it doesn't exist
      if ! ${pkgs.iproute2}/bin/ip netns list | grep -q "^vpn"; then
        ${pkgs.iproute2}/bin/ip netns add vpn
      fi

      # Clean up any existing veth pair
      ${pkgs.iproute2}/bin/ip link delete veth-host 2>/dev/null || true

      # Create veth pair for host <-> namespace communication
      ${pkgs.iproute2}/bin/ip link add veth-host type veth peer name veth-vpn

      # Move one end into the namespace
      ${pkgs.iproute2}/bin/ip link set veth-vpn netns vpn

      # Configure host side of veth pair
      ${pkgs.iproute2}/bin/ip addr add 10.200.200.1/24 dev veth-host
      ${pkgs.iproute2}/bin/ip link set veth-host up

      # Configure namespace side of veth pair
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iproute2}/bin/ip addr add 10.200.200.2/24 dev veth-vpn
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iproute2}/bin/ip link set veth-vpn up
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iproute2}/bin/ip link set lo up

      # Add route to reach VPN endpoint through host (uses existing host routing)
      ${pkgs.iproute2}/bin/ip netns exec vpn ${pkgs.iproute2}/bin/ip route add 146.70.134.2/32 via 10.200.200.1 dev veth-vpn

      # Set up NAT for namespace to reach VPN endpoint via host
      # Use ! -d to exclude local veth traffic from NAT
      if ! ${pkgs.iptables}/bin/iptables -t nat -C POSTROUTING -s 10.200.200.0/24 ! -d 10.200.200.0/24 -j MASQUERADE 2>/dev/null; then
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.200.200.0/24 ! -d 10.200.200.0/24 -j MASQUERADE
      fi

      # Allow forwarding for namespace traffic
      if ! ${pkgs.iptables}/bin/iptables -C FORWARD -i veth-host -j ACCEPT 2>/dev/null; then
        ${pkgs.iptables}/bin/iptables -A FORWARD -i veth-host -j ACCEPT
      fi
      if ! ${pkgs.iptables}/bin/iptables -C FORWARD -o veth-host -j ACCEPT 2>/dev/null; then
        ${pkgs.iptables}/bin/iptables -A FORWARD -o veth-host -j ACCEPT
      fi
    '';

    preStop = ''
      # Clean up iptables rules
      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.200.200.0/24 ! -d 10.200.200.0/24 -j MASQUERADE 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D FORWARD -i veth-host -j ACCEPT 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D FORWARD -o veth-host -j ACCEPT 2>/dev/null || true

      # Delete veth pair (automatically removes both ends)
      ${pkgs.iproute2}/bin/ip link delete veth-host 2>/dev/null || true

      # Delete namespace
      ${pkgs.iproute2}/bin/ip netns delete vpn 2>/dev/null || true
    '';
  };
}
