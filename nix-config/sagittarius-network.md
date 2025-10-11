● Here's a comprehensive network configuration table for all services running on your Sagittarius NAS:

  | Service     | Local Port | Local IP (LAN)                   | VPN Namespace IP  | Tailscale Reverse Proxy            | Notes                            |
  |-------------|------------|----------------------------------|-------------------|------------------------------------|----------------------------------|
  | Caddy       | -          | -                                | -                 | sagittarius.taildb4b48.ts.net      | Status page                      |
  | Prometheus  | 9090       | 127.0.0.1:9090                   | -                 | sagittarius.taildb4b48.ts.net:8442 | Monitoring                       |
  | Grafana     | 3000       | 127.0.0.1:3000                   | -                 | sagittarius.taildb4b48.ts.net:8443 | Dashboards                       |
  | Immich      | 2283       | 127.0.0.1:2283192.168.1.206:8444 | -                 | sagittarius.taildb4b48.ts.net:8444 | Photos (TS auth)Local LAN access |
  | Jellyfin    | 8096       | 127.0.0.1:8096192.168.1.206:8445 | -                 | sagittarius.taildb4b48.ts.net:8445 | Media streamingLocal LAN access  |
  | Navidrome   | 4534       | 127.0.0.1:4534                   | -                 | sagittarius.taildb4b48.ts.net:4533 | Music streaming                  |
  | Homepage    | 8082       | 127.0.0.1:8082                   | -                 | sagittarius.taildb4b48.ts.net:8441 | Dashboard                        |
  | Prowlarr    | 9696       | -                                | 10.200.200.2:9696 | sagittarius.taildb4b48.ts.net:9696 | VPN routed                       |
  | Sonarr      | 8989       | -                                | 10.200.200.2:8989 | sagittarius.taildb4b48.ts.net:8989 | VPN routed                       |
  | Radarr      | 7878       | -                                | 10.200.200.2:7878 | sagittarius.taildb4b48.ts.net:7878 | VPN routed                       |
  | Lidarr      | 8686       | -                                | 10.200.200.2:8686 | sagittarius.taildb4b48.ts.net:8686 | VPN routed                       |
  | Readarr     | 8787       | -                                | 10.200.200.2:8787 | sagittarius.taildb4b48.ts.net:8787 | VPN routed                       |
  | qBittorrent | 8081       | -                                | 10.200.200.2:8081 | sagittarius.taildb4b48.ts.net:8080 | VPN routed                       |
  | SABnzbd     | 8085       | -                                | 10.200.200.2:8085 | sagittarius.taildb4b48.ts.net:8090 | VPN routed                       |

  Network Summary:

  VPN Namespace Configuration:
  - Host veth IP: 10.200.200.1/24
  - VPN namespace veth IP: 10.200.200.2/24
  - VPN External IP: 146.70.134.29 (Mullvad Zurich)
  - Host External IP: 81.6.40.114

  LAN Configuration:
  - Primary Interface (enp5s0): 192.168.1.206
  - Secondary Interface (enp6s0): Separate VLAN for VPN traffic
  - Tailscale IP: 100.119.78.108

  Key Points:
  - Services marked VPN routed run in the VPN namespace and all their traffic goes through Mullvad
  - All services are accessible via Tailscale with authentication
  - Immich and Jellyfin also have local LAN access (192.168.1.206)
  - ARR stack services communicate with each other via localhost within the VPN namespace