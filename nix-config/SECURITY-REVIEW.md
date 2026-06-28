# Security Review — sagittarius (NixOS NAS) + nix-darwin

Date: 2026-06-14 · Scope: `nix-config/` (NixOS host `sagittarius` + nix-darwin laptop).

> **Framing:** the `mwerlberger/dotfiles` repo is **public on GitHub**. Every finding
> below is exposed to the public internet, not just to people with repo access.
> The `agenix` setup itself is sound — no encrypted `.age` secret leaked. The problems
> are values committed *outside* agenix, plus network-exposure defaults.

Priority order: **1 → 2 → 3 → 4**, then medium/low as time allows.

---

## 🔴 Critical

### 1. Leaked Mullvad WireGuard private keys
- [ ] **Rotate** the Mullvad WireGuard keys in the Mullvad portal (this is what actually closes the leak).
- [ ] Delete the stale backup files containing the cleartext key
      (`PrivateKey = oPvFxz1LYsTllIPnLZ3rpArp6hf99rAeafoyyi5RpVg=`):
  - `hosts/nixos/sagittarius/services/_bck/vpn-wg-mullvad.nix:83`
  - `hosts/nixos/sagittarius/services/_bck/vpn.nix.old:50`
- [ ] Optionally purge from git history (`git filter-repo`) the deleted configs that still
      contain private keys: `ch-zrh-wg-202.conf`, `ch-zrh-wg-404.conf`
      (history commits `f7ff26a`, `1314b77`). Rotation matters more than purging.

> Live config is already correct: `vpn.nix` uses `config.age.secrets.mullvad-privatekey-...`.

---

## 🟠 High — remote-root chain

These three combine: a crackable hash + password SSH + passwordless sudo = remote root.

### 2. Login password hash committed publicly
- [ ] Move `users.users.mw.hashedPassword` (`hosts/nixos/sagittarius/default.nix`) out of the
      repo into agenix via `hashedPasswordFile` / `users.users.mw.hashedPasswordFile`.

### 3. SSH password authentication enabled
- [ ] Set `PasswordAuthentication = false` (key-only) in `services/ssh.nix`.
- [ ] Confirm key-based access works first (host keys already managed).
- [ ] Consider restricting `AllowUsers` (currently `null` = all users).

### 4. Passwordless sudo
- [ ] Re-evaluate `security.sudo.wheelNeedsPassword = false` (`default.nix`).
      Acceptable only once #2/#3 are closed.

### 5. Samba/SMB exposed on all interfaces (incl. public IPv6)
- [ ] Scope SMB ports off the public interface. `network.nix` opens TCP `445,139` +
      UDP `137,138` globally; host has a public IPv6 (`2a02:168:ff46::10`).
- [ ] Restrict to the LAN interface or `tailscale0`
      (e.g. `networking.firewall.interfaces.<lan>.allowedTCPPorts`).
- [ ] Same review for SSH port `22` (currently global).

---

## 🟡 Medium

### 6. NFS read-write to the entire tailnet
- [ ] `services/nfs.nix` grants `rw` on `backups/documents/media/photos` to `100.64.0.0/10`
      (all Tailscale CGNAT). Narrow to specific tailnet IPs or make most exports `ro`.
      (`all_squash` limits to uid 1000, but any tailnet device gets write access.)

### 7. Trust-header auth assumes a single user
- [ ] Grafana (`monitoring.nix`): `default_role = "Admin"` + `auto_sign_up = true`
      → every tailnet user auto-becomes admin.
- [ ] Paperless (`paperless.nix`): `PAPERLESS_AUTO_LOGIN_USERNAME = "admin"`.
- [ ] Home Assistant (`home-assistant.nix`): `trusted_networks` includes `100.64.0.0/10`
      with `allow_bypass_login = true`.

> Header allow-listing (`whitelist = 127.0.0.1`) is correct, so the gate is sound.
> Risk is only the "any authenticated tailnet user = admin" assumption — fine for solo use.

---

## 🟢 Low / hygiene

- [ ] Grafana `secret_key = "SW2YcwTIb9zpOOhoPsMm"` committed (`monitoring.nix`).
      Documented as acceptable (old default, no sensitive datasource); still a public static key.
- [ ] Mosquitto `allow_anonymous = true` (`home-assistant.nix`) — localhost-only, but any
      local process can control Zigbee. The `hashedPassword` there is a fake placeholder.
- [ ] Drop EOL `aspnetcore-runtime-6.0.36` from `permittedInsecurePackages` (`default.nix`)
      while Bookshelf is disabled.
- [ ] Remove stale "replace with the real hash" comment in `caddy.nix` (cosmetic).

---

## ✅ Done well (no action)

- `agenix` correctly wired — per-secret `mode`/`owner`/`group`, host-key identity, encrypted files.
- App backends bound to `127.0.0.1`, fronted by Caddy with `tailscale_auth`.
- qBittorrent + SABnzbd isolated in a WireGuard netns, `bindsTo` the VPN (fails closed).
- NFSv4-only (v2/v3 disabled), `all_squash` everywhere, `PermitRootLogin = "no"`.
- nix-darwin laptop config is clean — no secrets, nothing exposed.
