{ config, pkgs, lib, ... }:

let
  immichHost = "photos.sagittarius.taildb4b48.ts.net";
  certDir = "/var/lib/tailscale/certs";
in
{
  services.immich = {
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    openFirewall = false;
  };

  systemd.tmpfiles.rules = [
    "d ${certDir} 0750 root nginx -"
    "f ${certDir}/${immichHost}.crt 0640 root nginx -"
    "f ${certDir}/${immichHost}.key 0640 root nginx -"
  ];

  systemd.services."tailscale-cert-${immichHost}" = {
    description = "Fetch/renew Tailscale cert for ${immichHost}";
    after = [ "tailscaled.service" ];
    requires = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.tailscale}/bin/tailscale cert --cert-file ${certDir}/${immichHost}.crt --key-file ${certDir}/${immichHost}.key ${immichHost}";
      ExecStartPost = [
        "${pkgs.coreutils}/bin/chgrp nginx ${certDir}/${immichHost}.crt ${certDir}/${immichHost}.key"
        "${pkgs.coreutils}/bin/chmod 640 ${certDir}/${immichHost}.crt ${certDir}/${immichHost}.key"
      ];
    };
  };

  systemd.timers."tailscale-cert-${immichHost}" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  services.nginx.virtualHosts."${immichHost}" = {
    serverName = immichHost;
    addSSL = true;
    sslCertificate = "${certDir}/${immichHost}.crt";
    sslCertificateKey = "${certDir}/${immichHost}.key";
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.immich.port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
      extraConfig = ''
        client_max_body_size 50000M;
        proxy_read_timeout   600s;
        proxy_send_timeout   600s;
        send_timeout         600s;
      '';
    };
  };

  systemd.services.nginx.after = lib.mkAfter [ "tailscale-cert-${immichHost}.service" ];
  systemd.services.nginx.requires = lib.mkAfter [ "tailscale-cert-${immichHost}.service" ];
}
