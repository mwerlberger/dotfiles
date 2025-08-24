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
  # Only expose 443 to tailnet clients.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 443 ];

  # Provide the CLI tools system-wide (handy for `tailscale status`, `tailscale up`, etc.)
  environment.systemPackages = [ pkgs.tailscale ];

  # Optional (commented) agenix integration example:
  # If you prefer auto-join with an auth key, create an age secret `secrets/tailscale-authkey.age`
  # containing ONLY the tailscale auth key string, then uncomment below lines and adjust path:
  age.secrets.tailscale-authkey = {
    file = ../secrets/tailscale-authkey.age;
    mode = "0400";
    owner = "root";
    group = "root";
  };
  services.tailscale.authKeyFile = config.age.secrets.tailscale-authkey.path;


}
