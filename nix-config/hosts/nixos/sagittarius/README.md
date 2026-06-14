# Sagittarius NAS — Service Overview

## Network

| | Address |
|---|---|
| Tailscale hostname | `sagittarius.taildb4b48.ts.net` |
| Tailscale IP | `100.119.78.108` |
| LAN IP | `192.168.1.206` |

All Caddy-fronted Tailscale endpoints use HTTPS (cert from Tailscale). LAN endpoints use plain HTTP
unless noted. Tailscale-protected services require an active tailnet session (enforced by the
`tailscale_auth` Caddy plugin).

---

## External Ports

| Port | Service | Tailscale | LAN | Auth | Notes |
|------|---------|:---------:|:---:|------|-------|
| 22 | SSH | ✓ | ✓ | key / password | |
| 80 | Caddy status | ✓ | — | none | health probe, returns 200 |
| 2049 | NFS | ✓ | ✓ | — | NFSv4 only; all_squash → uid/gid 1000 |
| 4533 | Navidrome | ✓ | — | Tailscale | music streaming |
| 7878 | Radarr | ✓ | — | Tailscale | movie automation (runs inside VPN ns) |
| 8080 | qBittorrent | ✓ | — | Tailscale | torrent client (runs inside VPN ns) |
| 8088 | Immich | — | ✓ | none | LAN-only photo access |
| 8090 | SABnzbd | ✓ | — | Tailscale | Usenet downloader (runs inside VPN ns) |
| 8441 | Homepage | ✓ | — | Tailscale | main dashboard |
| 8442 | Prometheus | ✓ | — | Tailscale | metrics scraper UI |
| 8443 | Grafana | ✓ | — | Tailscale + proxy auth | metrics visualisation |
| 8444 | Immich | ✓ | — | Tailscale | photo & video management |
| 8445 | Jellyfin | ✓ | ✓ | Tailscale / none | media streaming |
| 8446 | Audiobookshelf | ✓ | ✓ | Tailscale / none | audiobook streaming |
| 8447 | Homarr | ✓ | — | Tailscale | customisable home page |
| 8448 | Paperless | ✓ | ✓ | Tailscale / internal CA | document management |
| 8449 | Spliit | ✓ | ✓ | Tailscale / internal CA | expense sharing |
| 8450 | Nextcloud | ✓ | ✓ | Tailscale / none | file sync |
| 8686 | Lidarr | ✓ | — | Tailscale | music automation (runs inside VPN ns) |
| 8989 | Sonarr | ✓ | — | Tailscale | TV automation (runs inside VPN ns) |
| 9696 | Prowlarr | ✓ | — | Tailscale | indexer manager (runs inside VPN ns) |

---

## Internal Ports (not directly accessible)

| Port | Service | Bind address |
|------|---------|-------------|
| 2019 | Caddy admin API | `127.0.0.1` |
| 2283 | Immich server | `127.0.0.1` |
| 3000 | Grafana | `127.0.0.1` |
| 3001 | Spliit (container) | host network |
| 4534 | Navidrome | `127.0.0.1` |
| 6379 | Redis — Nextcloud | `127.0.0.1` |
| 6380 | Redis — Paperless | `127.0.0.1` |
| 7575 | Homarr (docker) | `127.0.0.1` |
| 7878 | Radarr | VPN ns `10.200.200.2` |
| 8000 | Audiobookshelf | `127.0.0.1` |
| 8081 | qBittorrent | VPN ns `10.200.200.2` |
| 8082 | Homepage dashboard | `127.0.0.1` |
| 8085 | SABnzbd | VPN ns `10.200.200.2` |
| 8096 | Jellyfin | default (all interfaces) |
| 8447 | Nextcloud nginx backend | `127.0.0.1` |
| 8686 | Lidarr | VPN ns `10.200.200.2` |
| 8788 | rreading-glasses (Hardcover metadata API) | `0.0.0.0` — internal only, no Caddy vhost |
| 8989 | Sonarr | VPN ns `10.200.200.2` |
| 9090 | Prometheus | `127.0.0.1` |
| 9100 | node_exporter | `127.0.0.1` |
| 9696 | Prowlarr | VPN ns `10.200.200.2` |
| 28981 | Paperless | `127.0.0.1` |

---

## File Shares

| Protocol | Path | Clients | Access |
|----------|------|---------|--------|
| NFS v4 | `/data/lake` (pseudo-root) | LAN + Tailscale | read-only |
| NFS v4 | `/data/lake/backups` | LAN + Tailscale | read-write |
| NFS v4 | `/data/lake/documents` | LAN + Tailscale | read-write |
| NFS v4 | `/data/lake/media` | LAN + Tailscale | read-write |
| NFS v4 | `/data/lake/photos` | LAN + Tailscale | read-write |
| Samba | see `samba.nix` | LAN | per-share |

---

## VPN Namespace

The ARR stack (Sonarr, Radarr, Lidarr, Prowlarr), qBittorrent, and SABnzbd all run inside a
dedicated network namespace (`vpn-namespace.service`) with a Mullvad WireGuard tunnel. Caddy reaches
them via the veth peer at `10.200.200.2`. They are bound to the VPN namespace and stop if the tunnel
drops (`bindsTo = wg-quick-mullvad.service`).

---

## Disabled / Placeholder Services

| Service | File | Reason |
|---------|------|--------|
| Bookshelf | `bookshelf.nix` | `mkYarnPackage` removed in nixpkgs 26.05 |
| Home Assistant | `home-assistant.nix` | commented out in `default.nix` |
| Pydio Cells | `pydio-cells*.nix` | both variants commented out |
| Readarr | (arr.nix) | replaced by `rreading-glasses` (Hardcover-backed metadata) |
