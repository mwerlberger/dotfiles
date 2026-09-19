# Sagittarius NAS — Service Overview

## Network

| | Address |
|---|---|
| Tailscale hostname | `sagittarius.taildb4b48.ts.net` |
| Tailscale IP | `100.119.78.108` |
| LAN IP (enp5s0) | `192.168.1.206` |
| VPN-uplink IP (enp6s0) | `192.168.2.207` |

How to read the tables below:

- Caddy fronts everything user-facing. Tailscale vhosts use HTTPS with a Tailscale-issued cert and
  are gated by the `tailscale_auth` plugin (an active tailnet session is required). LAN vhosts are
  plain HTTP unless the table says `https` — Paperless, Spliit and Home Assistant use Caddy's
  internal CA, so the browser will warn unless that CA is trusted.
- `tailscale0` is a **trusted firewall interface** (`modules/tailscale.nix`), so anything bound to
  `0.0.0.0` is reachable from the tailnet directly, bypassing Caddy and therefore `tailscale_auth`.
  Those listeners are called out in [Direct listeners](#direct-listeners-not-behind-caddy).
- LAN reachability needs both a Caddy vhost bound to `192.168.1.206` **and** an open firewall port.

---

## Public (internet) endpoints

Off by default. `services/public-edge.nix` ships an `enable` flag that is `false` until the
Cloudflare side exists; see [`services/PUBLIC-SHARING.md`](services/PUBLIC-SHARING.md).

| Service | Public URL | Loopback vhost | Backend | Auth |
|---------|-----------|----------------|---------|------|
| Immich share links | `https://photos.werlberger.org` | `127.0.0.1:8460` | `127.0.0.1:2283` | Cloudflare Access (email OTP, reusable policy `family`) + JWT check in Caddy + Immich share key |
| Nextcloud file drop | `https://drop.werlberger.org` | `127.0.0.1:8462` | `127.0.0.1:8447` | same Access group + JWT check + Nextcloud link token |

Reached over a Cloudflare Tunnel: `cloudflared` dials **out**, so the firewall tables below are
**unchanged** — there is no new listener on the LAN or on the public IPv6, and no port to
forward. The two loopback vhosts are bound to `127.0.0.1` and only cloudflared talks to them.

The drop exists because Cloudflare caps request bodies at 100 MB and Immich's *web* uploader
sends a single-shot POST; Nextcloud's chunks. Responses are not capped, so viewing and
downloading large video through the tunnel is fine. Retire the drop when upstream Immich ships
chunked web uploads.

Jellyfin is deliberately **not** published: Cloudflare Access authenticates via a browser OTP
flow, which native TV and mobile clients cannot complete.

---

## Web endpoints

| Service | Tailscale URL | LAN URL | Backend | Auth |
|---------|---------------|---------|---------|------|
| Caddy status | `https://sagittarius.taildb4b48.ts.net` | — | — | none, returns 200 |
| Navidrome | `https://sagittarius.taildb4b48.ts.net:4533` | — | `127.0.0.1:4534` | Tailscale (+ proxy auth) |
| Radarr | `https://sagittarius.taildb4b48.ts.net:7878` | — | VPN ns `10.200.200.2:7878` | Tailscale |
| qBittorrent | `https://sagittarius.taildb4b48.ts.net:8080` | — | VPN ns `10.200.200.2:8081` | Tailscale |
| Immich | `https://sagittarius.taildb4b48.ts.net:8444` | `http://192.168.1.206:8088` | `127.0.0.1:2283` | Tailscale / none on LAN |
| Bindery | `https://sagittarius.taildb4b48.ts.net:8787` | — | VPN ns `10.200.200.2:8787` | Tailscale (`set_headers` → `Remote-User`) |
| SABnzbd | `https://sagittarius.taildb4b48.ts.net:8090` | — | VPN ns `10.200.200.2:8085` | Tailscale |
| Home Assistant | `https://sagittarius.taildb4b48.ts.net:8123` | (vhost exists, port closed) | `127.0.0.1:8123` | Tailscale |
| Homepage | `https://sagittarius.taildb4b48.ts.net:8441` | — | `127.0.0.1:8082` | Tailscale |
| Prometheus | `https://sagittarius.taildb4b48.ts.net:8442` | — | `127.0.0.1:9090` | Tailscale |
| Grafana | `https://sagittarius.taildb4b48.ts.net:8443` | — | `127.0.0.1:3000` | Tailscale + proxy auth |
| Jellyfin | `https://sagittarius.taildb4b48.ts.net:8445` | `http://192.168.1.206:8445` | `127.0.0.1:8096` | Tailscale / none on LAN |
| Audiobookshelf | `https://sagittarius.taildb4b48.ts.net:8446` | `http://192.168.1.206:8446` | `127.0.0.1:8000` | Tailscale / none on LAN |
| Homarr | `https://sagittarius.taildb4b48.ts.net:8447` | — | `127.0.0.1:7575` (docker) | Tailscale |
| Paperless | `https://sagittarius.taildb4b48.ts.net:8448` | `https://192.168.1.206:8448` | `127.0.0.1:28981` | Tailscale / internal CA |
| Spliit | `https://sagittarius.taildb4b48.ts.net:8449` | `https://192.168.1.206:8449` | `127.0.0.1:3001` (docker) | Tailscale / internal CA |
| Nextcloud | `https://sagittarius.taildb4b48.ts.net:8450` | `http://192.168.1.206:8450` | `127.0.0.1:8447` (nginx) | Tailscale / none on LAN |
| Firefly III | `https://sagittarius.taildb4b48.ts.net:8451` | — | php-fpm socket | Tailscale (`set_headers` → remote user) |
| Firefly III importer | `https://sagittarius.taildb4b48.ts.net:8452` | — | php-fpm socket | Tailscale only |
| Lidarr | `https://sagittarius.taildb4b48.ts.net:8686` | — | VPN ns `10.200.200.2:8686` | Tailscale |
| Sonarr | `https://sagittarius.taildb4b48.ts.net:8989` | — | VPN ns `10.200.200.2:8989` | Tailscale |
| Prowlarr | `https://sagittarius.taildb4b48.ts.net:9696` | — | VPN ns `10.200.200.2:9696` | Tailscale |

Firefly III is deliberately Tailscale-only (financial data, no LAN vhost). It also has a
loopback-only vhost on `127.0.0.1:8461` that the data importer uses for API calls, because a request
from localhost carries no tailnet identity and would be rejected by the public vhost.

Home Assistant has a LAN vhost on `192.168.1.206:8123` (`tls internal`), but 8123 is **not** in the
firewall's allowed ports, so LAN clients can't reach it — only the Tailscale URL works today. Open
the port in `services/home-assistant.nix` if LAN access is wanted.

Note the port reuse: **8447** is Homarr externally (on the Tailscale IP) and Nextcloud's internal
nginx on `127.0.0.1`. Different bind addresses, so they coexist, but don't reuse 8447 elsewhere.

---

## Non-HTTP services

| Port | Proto | Service | Reachable from |
|------|-------|---------|----------------|
| 22 | tcp | SSH | Tailscale + LAN |
| 111 | tcp/udp | rpcbind (NFS) | Tailscale + LAN |
| 139, 445 | tcp | Samba | LAN (+ Tailscale) |
| 137, 138 | udp | NetBIOS | LAN |
| 2049 | tcp | NFSv4 | Tailscale + LAN; NFSv4 only, `all_squash` → uid/gid 1000 |
| 5353 | udp | mDNS (Avahi / OTBR) | LAN, `enp5s0` only |
| 21063 | tcp | HomeKit bridge (Home Assistant) | LAN, `enp5s0` only |
| 25055 | tcp/udp | qBittorrent BitTorrent port | inside VPN namespace, via Mullvad |
| 41641 | udp | Tailscale | WAN |
| 51820 | udp | WireGuard (Mullvad) | WAN |
| 60000–61000 | udp | mosh | Tailscale + LAN |

---

## Direct listeners (not behind Caddy)

These bind `0.0.0.0`/`*` rather than loopback. The LAN firewall blocks them, but `tailscale0` is a
trusted interface, so they answer on the tailnet **without** `tailscale_auth` in front:

| Port | Service | Note |
|------|---------|------|
| 5580 | matter-server websocket | used by the Home Assistant `matter` integration |
| 8082 | Homepage dashboard | also served with auth on 8441 |
| 8096 | Jellyfin | also served with auth on 8445 |
| 9090 | Prometheus | also served with auth on 8442 |
| 9100 | node_exporter | scraped by Prometheus |

Loopback-only listeners (`127.0.0.1`), reachable only from the host itself:

| Port | Service |
|------|---------|
| 2019 | Caddy admin API |
| 2283 | Immich server |
| 3000 | Grafana |
| 3003 | Immich machine learning |
| 4534 | Navidrome |
| 5432 | PostgreSQL |
| 6379 | Redis — Nextcloud |
| 6380 | Redis — Paperless |
| 7575 | Homarr (docker-proxy) |
| 8000 | Audiobookshelf |
| 8081 | otbr-agent |
| 8083 | otbr-web (OpenThread Border Router UI) |
| 8123 | Home Assistant |
| 8447 | Nextcloud nginx backend |
| 8460 | Caddy, public vhost for Immich share links (cloudflared only; off by default) |
| 8461 | Firefly III, loopback vhost for the data importer |
| 8462 | Caddy, public vhost for the Nextcloud file drop (cloudflared only; off by default) |
| 28981 | Paperless (granian) |

---

## Firewall

Globally open TCP: `22`, `80`, `443` (Caddy's `openFirewall`), `139`, `445`, `2049`, `8088`, `8444`,
`8445`, `8446`, `8447`, `8448`, `8449`, `8450`, `8451`, `8452`.
Interface-scoped: `21063/tcp` and `5353/udp` on `enp5s0` only.

The public-sharing vhosts (`8460`, `8462`) add **nothing** to these lists: the Cloudflare
tunnel is outbound-only.

`8444`, `8447`, `8451` and `8452` are open on every interface, but Caddy binds those vhosts to
`100.119.78.108` only — there is no LAN listener, so they are effectively Tailscale-only.

Ports 80 and 443 on the LAN IP serve Caddy's status page and the HTTP→HTTPS redirects that Caddy
generates for the `tls internal` LAN vhosts (Paperless, Spliit, Home Assistant).

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
dedicated network namespace (`vpn-namespace.service`) with a Mullvad WireGuard tunnel
(`ch-zrh-wg-202`, endpoint `46.19.136.226:51820`). Caddy reaches them via the veth peer at
`10.200.200.2` (host side `10.200.200.1`). They are bound to the namespace and stop if the tunnel
drops (`bindsTo = wg-quick-mullvad.service`).

Inside the namespace the services listen on all interfaces; the reverse-proxied ports above are the
only way in from outside.

---

## Books & Audiobooks

| Piece | State |
|-------|-------|
| Audiobookshelf | playback/library server on 8446, serves `/data/lake/media/audiobooks` and `/data/lake/media/books` |
| Bindery | automation on 8787 — monitors authors, searches indexers, imports ebooks *and* audiobooks |

Bindery replaces Readarr, which upstream archived in June 2025 when its Goodreads metadata backend
went offline for good. It draws metadata from OpenLibrary, Google Books, Hardcover, DNB, Audnex and
Audible, so it needs no separate metadata proxy — `rreading-glasses` was removed along with the
disabled `bookshelf.nix` Readarr fork.

It runs inside the VPN namespace like the rest of the \*arr stack and reaches qBittorrent
(`127.0.0.1:8081`), SABnzbd (`127.0.0.1:8085`) and Prowlarr (`127.0.0.1:9696`) as localhost from in
there. Everything else is configured in its web UI; see the first-run notes at the bottom of
`services/bindery.nix`.

---

## Disabled / Placeholder Services

| Service | File | Reason |
|---------|------|--------|
| Pydio Cells | `pydio-cells*.nix` | both variants commented out in `services/default.nix` |
| Home Assistant | — | enabled; the LAN vhost works only once 8123 is opened in the firewall |

Removed outright: `readarr` (upstream archived), `bookshelf.nix` (Readarr fork, `mkYarnPackage`
dropped in nixpkgs 26.05) and `rreading-glasses.nix` (metadata proxy with no remaining consumer) —
all superseded by Bindery.
