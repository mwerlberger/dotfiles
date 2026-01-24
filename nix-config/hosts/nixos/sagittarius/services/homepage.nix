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
        "Media & Photos" = {
          style = "row";
          columns = 3;
        };
        "Download Management" = {
          style = "row";
          columns = 3;
        };
        "ARR Stack" = {
          style = "row";
          columns = 3;
        };
        "Productivity & Files" = {
          style = "row";
          columns = 3;
        };
        "Home & Dashboards" = {
          style = "row";
          columns = 3;
        };
        "Monitoring & System" = {
          style = "row";
          columns = 2;
        };
      };
    };

    services = [
      {
        "Media & Photos" = [
          {
            "Immich" = {
              href = "https://sagittarius.taildb4b48.ts.net:8444";
              description = "Photo & video management";
              icon = "immich.png";
            };
          }
          {
            "Jellyfin" = {
              href = "https://sagittarius.taildb4b48.ts.net:8445";
              description = "Movies & TV streaming";
              icon = "jellyfin.png";
            };
          }
          {
            "Navidrome" = {
              href = "https://sagittarius.taildb4b48.ts.net:4533";
              description = "Music streaming";
              icon = "navidrome.png";
            };
          }
        ];
      }
      {
        "Download Management" = [
          {
            "qBittorrent" = {
              href = "https://sagittarius.taildb4b48.ts.net:8080";
              description = "Torrent client (VPN)";
              icon = "qbittorrent.png";
            };
          }
          {
            "SABnzbd" = {
              href = "https://sagittarius.taildb4b48.ts.net:8090";
              description = "Usenet downloader (VPN)";
              icon = "sabnzbd.png";
            };
          }
        ];
      }
      {
        "ARR Stack" = [
          {
            "Sonarr" = {
              href = "https://sagittarius.taildb4b48.ts.net:8989";
              description = "TV series automation";
              icon = "sonarr.png";
            };
          }
          {
            "Radarr" = {
              href = "https://sagittarius.taildb4b48.ts.net:7878";
              description = "Movie automation";
              icon = "radarr.png";
            };
          }
          {
            "Lidarr" = {
              href = "https://sagittarius.taildb4b48.ts.net:8686";
              description = "Music automation";
              icon = "lidarr.png";
            };
          }
          {
            "Readarr" = {
              href = "https://sagittarius.taildb4b48.ts.net:8787";
              description = "Book automation";
              icon = "readarr.png";
            };
          }
          {
            "Prowlarr" = {
              href = "https://sagittarius.taildb4b48.ts.net:9696";
              description = "Indexer manager";
              icon = "prowlarr.png";
            };
          }
        ];
      }
      {
        "Productivity & Files" = [
          {
            "Paperless" = {
              href = "https://sagittarius.taildb4b48.ts.net:8448";
              description = "Document management";
              icon = "paperless.png";
            };
          }
          # {
          #   "Pydio Cells" = {
          #     href = "https://sagittarius.taildb4b48.ts.net:8448";
          #     description = "Enterprise file sharing";
          #     icon = "pydio.png";
          #   };
          # }
        ];
      }
      {
        "Home & Dashboards" = [
          {
            "Home Assistant" = {
              href = "https://sagittarius.taildb4b48.ts.net:8123";
              description = "Home automation";
              icon = "home-assistant.png";
            };
          }
          {
            "Homarr" = {
              href = "https://sagittarius.taildb4b48.ts.net:8447";
              description = "Customizable home page";
              icon = "homarr.png";
            };
          }
          {
            "Homepage" = {
              href = "https://sagittarius.taildb4b48.ts.net:8441";
              description = "This dashboard";
              icon = "homepage.png";
            };
          }
        ];
      }
      {
        "Monitoring & System" = [
          {
            "Grafana" = {
              href = "https://sagittarius.taildb4b48.ts.net:8443";
              description = "Metrics visualization";
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
          # disk = "/";
          cputemp = true;
          tempmin = 0;
          tempmax = 100;
        };
      }
      {
        resources = {
          # label = "Data Lake";
          disk = "/data/lake";
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
        openmeteo = {
          label = "Zurich";
          latitude = 47.3769;
          longitude = 8.5417;
          units = "metric";
          cache = 5;
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
              {
                href = "https://nixos.org/manual/nixos/stable/";
                description = "NixOS Manual";
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
      {
        "Media Resources" = [
          {
            "The Movie DB" = [
              {
                href = "https://www.themoviedb.org/";
                description = "Movie metadata";
              }
            ];
          }
          {
            "TV Maze" = [
              {
                href = "https://www.tvmaze.com/";
                description = "TV show info";
              }
            ];
          }
          {
            "MusicBrainz" = [
              {
                href = "https://musicbrainz.org/";
                description = "Music metadata";
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
