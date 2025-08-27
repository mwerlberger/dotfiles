{ config, pkgs, lib, ... }:

{
  # Enable Tailscale daemon and open required firewall ports
  services.tailscale = {
    enable = true;
    openFirewall = true; # opens UDP 41641 and allows tailscale0 traffic
    # useRoutingFeatures = "client"; # set to "both" if you plan to advertise routes/exit-node
    # extraUpFlags = [ "--ssh" ]; # optional: enable Tailscale SSH
  };

  # Trust the Tailscale interface so internal services (e.g., Samba, Grafana) are reachable over Tailscale
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 80 443 ];

  # Provide the CLI tools system-wide (handy for `tailscale status`, `tailscale up`, etc.)
  environment.systemPackages = [ pkgs.tailscale ];
}
