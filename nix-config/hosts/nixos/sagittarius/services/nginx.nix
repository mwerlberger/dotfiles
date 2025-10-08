{ config, pkgs, lib, ... }:

let
  tsHost = "sagittarius.taildb4b48.ts.net";
  certDir = "/var/lib/tailscale/certs";
in
{
  # Ensure parent and cert directory are group-accessible
  systemd.tmpfiles.rules = [
    "d /var/lib/tailscale 0750 root nginx -"
    "d ${certDir} 0750 root nginx -"
    "f ${certDir}/${tsHost}.crt 0640 root nginx -"
    "f ${certDir}/${tsHost}.key 0640 root nginx -"
  ];

  systemd.services."tailscale-cert-${tsHost}" = {
    description = "Fetch/renew Tailscale cert for ${tsHost}";
    after = [ "tailscaled.service" ];
    requires = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.tailscale}/bin/tailscale cert --cert-file ${certDir}/${tsHost}.crt --key-file ${certDir}/${tsHost}.key ${tsHost}";
      # Tailscale certificates are automatically owned root:root and nginx can't access them. Lets fix that here as post start.
      ExecStartPost = [
        "${pkgs.coreutils}/bin/chgrp nginx ${certDir}/${tsHost}.crt ${certDir}/${tsHost}.key"
        "${pkgs.coreutils}/bin/chmod 640 ${certDir}/${tsHost}.crt ${certDir}/${tsHost}.key"
      ];
    };
  };

  systemd.timers."tailscale-cert-${tsHost}" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  services.nginx = {
    enable = true;
    user = "nginx";
    group = "nginx";
    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    recommendedTlsSettings = true;

    virtualHosts."${tsHost}" = {
      serverName = tsHost;
      addSSL = true;
      sslCertificate = "${certDir}/${tsHost}.crt";
      sslCertificateKey = "${certDir}/${tsHost}.key";

      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
        proxyWebsockets = true;
      };

      # Health check endpoint
      locations."/health" = {
        return = "200 'OK: nginx is up'";
        extraConfig = ''
          add_header Content-Type text/plain;
        '';
      };

      # Grafana reverse proxy
      locations."/grafana/" = {
        # Preserve the original URI so Grafana receives /grafana/... (Grafana is configured with subUrl)
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
        # rely on the global recommended proxy_set_header include to avoid duplicate headers
      };


      # Prometheus reverse proxy
      locations."/prometheus/" = {
        # Keep the /prometheus/ prefix when forwarding (Prometheus usually expects /)
        proxyPass = "http://127.0.0.1:9090";
        # rely on the global recommended proxy_set_header include to avoid duplicate headers
      };
    };
  };

  systemd.services.nginx.after = [ "tailscale-cert-${tsHost}.service" ];
  systemd.services.nginx.requires = [ "tailscale-cert-${tsHost}.service" ];
}
