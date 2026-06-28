{
  config,
  pkgs,
  lib,
  ...
}:

let
  # LAN interface that already carries IPv6 (see network.nix). This is the
  # "backbone" the Thread mesh prefix is advertised on, so Apple devices on the
  # LAN can route to/from the Thread network.
  backbone = "enp5s0";

  # Home Assistant Connect ZBT-2 flashed with OpenThread RCP firmware.
  # The /dev/serial/by-id path is stable across reboots.
  zbt2 = "/dev/serial/by-id/usb-Nabu_Casa_ZBT-2_94A990D02094-if00";
in
{
  # Thread Border Router. The module also enables IPv6 forwarding + accept_ra on
  # the backbone, sets up otbr-firewall, and turns on Avahi for mDNS publishing.
  services.openthread-border-router = {
    enable = true;
    backboneInterfaces = [ backbone ];
    radio = {
      device = zbt2;
      baudRate = 460800;
      flowControl = false;
    };
    # REST API stays on 127.0.0.1:8081 for Home Assistant's `otbr` integration.
    # Optional local web UI on 127.0.0.1:8082.
    web.enable = true;
  };

  # Matter controller. Home Assistant's `matter` integration connects to its
  # websocket on 127.0.0.1:5580. Lets HA commission/control Matter-over-Thread
  # devices (e.g. shared from Apple Home) over the Thread network.
  services.matter-server.enable = true;

  # LAN-scoped firewall: reachable only from the home LAN (enp5s0), not Tailscale
  # or enp6s0.
  #   5353/udp  -> mDNS/DNS-SD discovery (HomeKit bridge, Thread/Matter, OTBR)
  #   21063/tcp -> HomeKit bridge accessory server (Apple Home)
  networking.firewall.interfaces.${backbone} = {
    allowedUDPPorts = [ 5353 ];
    allowedTCPPorts = [ 21063 ];
  };
}
