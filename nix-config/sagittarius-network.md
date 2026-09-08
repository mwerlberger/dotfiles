# Sagittarius — Network Layout

Service URLs, ports and firewall state live in
[`hosts/nixos/sagittarius/README.md`](hosts/nixos/sagittarius/README.md). This file covers the
host's network plumbing only.

## Interfaces

| Interface | Address | Role |
|-----------|---------|------|
| `enp5s0` | `192.168.1.206/24` (+ `2a02:168:ff46::10/64`) | home LAN, default gateway `192.168.1.1` |
| `enp6s0` | `192.168.2.207/24` | separate VLAN used as the VPN uplink, gateway `192.168.2.1` |
| `tailscale0` | `100.119.78.108` | tailnet; a **trusted** firewall interface |
| `veth-vpn` | `10.200.200.1` (host) ↔ `10.200.200.2` (namespace) | host ↔ VPN namespace link |

Policy routing (`network.nix`) adds tables `201 enp6s0` and `200 vpn`;
`setup-enp6s0-routing.service` installs the `enp6s0` table and a `from 192.168.2.207` rule at
priority 300 so enp6s0 traffic (including DNS to 1.1.1.1 / 8.8.8.8 / 100.100.100.100) leaves via
`192.168.2.1`.

## VPN namespace

`vpn-namespace.service` creates the `vpn` netns; `wg-quick-mullvad.service` brings up the
`mullvad` WireGuard interface inside it.

| | |
|---|---|
| Mullvad server | `ch-zrh-wg-202`, endpoint `46.19.136.226:51820` |
| Tunnel address | `10.71.28.122/32`, `fc00:bbbb:bbbb:bb01::8:1c79/128` |
| Tunnel DNS | `10.64.0.1` |
| Exit IP (as of 2026-09-08) | `46.19.136.231` |
| Host WAN IP | `81.6.40.114` |

Services in the namespace: Sonarr, Radarr, Lidarr, Prowlarr, Bindery, qBittorrent, SABnzbd. They listen on
all interfaces *inside* the namespace and are reachable only through Caddy on the host, via
`10.200.200.2`. Each one `bindsTo` `wg-quick-mullvad.service`, so a dropped tunnel stops them
rather than leaking traffic.

Namespace listeners: Prowlarr `9696`, Sonarr `8989`, Radarr `7878`, Lidarr `8686`,
Bindery `8787`, qBittorrent WebUI `8081` (BitTorrent port `25055` on the Mullvad interface),
SABnzbd `8085`.
