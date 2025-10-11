{ config, pkgs, lib, ... }:

{
  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;


    settings = {
      title = "Sagittarius NAS Dashboard";
      favicon = "https://github.com/gethomepage/homepage/raw/main/public/android-chrome-192x192.png";
      theme = "dark";
      color = "slate";
      headerStyle = "boxed";
      layout = {
        "Media Services" = {
          style = "row";
          columns = 3;
        };
        "Download Management" = {
          style = "row";
          columns = 3;
        };
        "Monitoring" = {
          style = "row";
          columns = 2;
        };
      };
    };

    services = [
      {
        "Media Services" = [
          {
            "Immich" = {
              href = "https://sagittarius.taildb4b48.ts.net:8444";
              description = "Photo management";
              icon = "immich.png";
            };
          }
          {
            "Jellyfin" = {
              href = "http://192.168.1.206:8096";
              description = "Media streaming";
              icon = "jellyfin.png";
            };
          }
        ];
      }
      {
        "Download Management" = [
          {
            "qBittorrent" = {
              href = "http://192.168.1.206:8080";
              description = "Torrent client";
              icon = "qbittorrent.png";
            };
          }
          {
            "Sonarr" = {
              href = "http://192.168.1.206:8989";
              description = "TV series management";
              icon = "sonarr.png";
            };
          }
          {
            "Radarr" = {
              href = "http://192.168.1.206:7878";
              description = "Movie management";
              icon = "radarr.png";
            };
          }
          {
            "Prowlarr" = {
              href = "http://192.168.1.206:9696";
              description = "Indexer management";
              icon = "prowlarr.png";
            };
          }
        ];
      }
      {
        "Monitoring" = [
          {
            "Grafana" = {
              href = "https://sagittarius.taildb4b48.ts.net:8443";
              description = "Metrics and dashboards";
              icon = "grafana.png";
            };
          }
          {
            "Prometheus" = {
              href = "https://sagittarius.taildb4b48.ts.net:8442";
              description = "Metrics collection";
              icon = "prometheus.png";
            };
          }
        ];
      }
    ];

    widgets = [
      {
        resources = {
          cpu = true;
          memory = true;
          disk = "/";
        };
      }
      {
        datetime = {
          text_size = "xl";
          format = {
            timeStyle = "short";
            dateStyle = "short";
            hourCycle = "h23";
          };
        };
      }
      {
        search = {
          provider = "google";
          target = "_blank";
        };
      }
    ];

    bookmarks = [
      {
        "Developer" = [
          {
            "GitHub" = [
              {
                href = "https://github.com/mwerlberger";
                description = "Personal GitHub";
              }
            ];
          }
          {
            "NixOS" = [
              {
                href = "https://search.nixos.org/packages";
                description = "Package search";
              }
              {
                href = "https://nixos.wiki/";
                description = "NixOS Wiki";
              }
            ];
          }
        ];
      }
      {
        "Infrastructure" = [
          {
            "Tailscale" = [
              {
                href = "https://login.tailscale.com/admin";
                description = "Tailscale Admin";
              }
            ];
          }
          {
            "Cloudflare" = [
              {
                href = "https://dash.cloudflare.com";
                description = "DNS Management";
              }
            ];
          }
        ];
      }
    ];
  };

  # Add homepage to Caddy reverse proxy configuration
  services.caddy.virtualHosts."sagittarius.taildb4b48.ts.net:8441" = {
    extraConfig = ''
      bind 100.119.78.108
      tls {
        get_certificate tailscale
      }
      tailscale_auth set_headers
      reverse_proxy 127.0.0.1:8082 {
        header_up X-Webauth-User {http.request.header.Tailscale-User-Login}
        header_up X-Webauth-Name {http.request.header.Tailscale-User-Name}
        header_up X-Webauth-Email {http.request.header.Tailscale-User-Login}
      }
    '';
  };

  # Configure environment variables for homepage service
  systemd.services.homepage-dashboard.environment = {
    HOMEPAGE_ALLOWED_HOSTS = lib.mkForce "localhost:8082,127.0.0.1:8082,sagittarius.taildb4b48.ts.net:8441";
  };
}
