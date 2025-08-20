{ config
, pkgs
, username
, ...
}:
{
    security.acme = {
      acceptTerms = true;
      defaults.email = "web@werlberger.org";
      certs.werlberger.org = {
        reloadServices = [ "caddy.service" ];
        domain = "sagittarius.werlberger.org";
        extraDomainNames = [ "*.sagittarius.werlberger.org" ];
        dnsProvider = "cloudflare";
        dnsResolver = "1.1.1.1:53";
        dnsPropagationCheck = true;
        group = config.services.caddy.group;
        environmentFile = "/etc/caddy/cloudflare-token";
      };
    };
    services.caddy = {
      enable = true;
      globalConfig = ''
        auto_https off
      '';
      virtualHosts = {
        "http://sagittarius.werlberger.org" = {
          extraConfig = ''
            redir https://{host}{uri}
          '';
        };
        "http://*.sagittarius.werlberger.org" = {
          extraConfig = ''
            redir https://{host}{uri}
          '';
        };

      };
    };


  imports = [
    # ./reverse-proxy.nix
    ./ssh.nix
    ./samba.nix
    ./monitoring.nix
  ];
}