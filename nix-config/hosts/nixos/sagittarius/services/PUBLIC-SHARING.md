# Public sharing runbook

How a hand-picked group of people outside the tailnet gets at an Immich album — and how to
add, revoke, or extend that.

Config lives in [`public-edge.nix`](public-edge.nix). Everything below assumes you are on the
tailnet for the admin steps.

## How it works

```
family browser
   │ HTTPS
   ▼
Cloudflare edge ── Access policy (email OTP, reusable policy `family`) ── WAF / cache bypass
   │  signed Cf-Access-Jwt-Assertion
   │  tunnel — outbound-initiated, so no inbound port on sagittarius
   ▼
cloudflared  (DynamicUser, sandboxed; can reach the Cloudflare edge and loopback, nothing else)
   │ 127.0.0.1:8460                    │ 127.0.0.1:8462
   ▼                                    ▼
Caddy vhost, bind 127.0.0.1 ×2
   ├─ remote_ip must be 127.0.0.1
   ├─ path deny-list → 404
   ├─ jwtauth → verify Cloudflare's JWT (team JWKS + this app's AUD tag)
   ▼                                    ▼
Immich 127.0.0.1:2283               Nextcloud nginx 127.0.0.1:8447
  /share/<key>, uploads on            File drop /s/<token>, chunked upload
```

Four gates. Any one alone stops an unauthorised request:

1. the Cloudflare Access policy (allow-list of email addresses)
2. `jwtauth` in Caddy — a token minted for a different app is rejected by the audience check
3. the per-service path deny-list
4. the application's own share-token auth

`networking.firewall` is deliberately untouched: the tunnel dials out, so there is no new
listener on the LAN or on the host's public IPv6.

## Why two links

Cloudflare caps **request bodies** at 100 MB on Free and Pro, not configurable. That is roughly
1–2 min of 4K phone video. **Responses are not capped** — streaming or downloading a multi-GB
video out of the album works fine.

Immich's web uploader sends a single-shot POST. Its mobile app works around the cap with
`Transfer-Encoding: chunked`, but browsers are not permitted to set that header, so the web
client cannot. Upstream PR #26026 ("chunked upload to bypass Cloudflare 100MB limit") was closed
unmerged; a separate implementation with 90 MiB parts was still in progress in a fork as of
Sep 2026.

Nextcloud's web uploader chunks by default (~10 MiB parts via DAV) and is unaffected. Hence:
Immich share link for photos and clips, Nextcloud file drop for anything larger.

**When upstream Immich ships chunked web uploads, delete the `drop` entry from `published` and
retire the Nextcloud share.**

## One-time setup

Nothing works until the placeholders in `public-edge.nix` are replaced and `enable` is flipped
to `true`. Order matters — agenix fails the rebuild if the `.age` file is missing.

1. **Tunnel — must be created from the CLI, not the dashboard.**

   A tunnel's `config_src` is fixed when it is created: dashboard-created tunnels are
   `cloudflare` (remotely managed, token-based, routes configured in the UI), CLI-created ones
   are `local`. **With a remotely-managed tunnel, cloudflared ignores local ingress rules
   entirely** and always pulls its config from the Cloudflare API — the `published` attrset in
   `public-edge.nix` would be silently dead. There is no supported way to flip `config_src` on
   an existing tunnel, so create a fresh one:

   Run this on the NAS over SSH — no local install needed, and `cloudflared login` prints a
   URL when it cannot open a browser, so headless is fine:

   ```bash
   nix run nixpkgs#cloudflared -- tunnel login
   # open the printed URL on any device, pick the werlberger.org zone
   # → writes ~/.cloudflared/cert.pem

   nix run nixpkgs#cloudflared -- tunnel create sagittarius-public
   # → writes ~/.cloudflared/<UUID>.json
   ```

   `<UUID>.json` *is* the credentials file. Note the UUID → `tunnelId`, then:

   ```bash
   cd ~/dotfiles/nix-config
   agenix -e secrets/cloudflared-credentials.age   # paste the contents of <UUID>.json
   ```

   Creating a *new* secret needs no private key — ragenix only reads the recipient public keys
   from `secrets.nix`. Editing it **later** does need one, and there is no `~/.ssh/id_ed25519`
   on the NAS, so rotations go through the host key:

   ```bash
   sudo env EDITOR="$EDITOR" agenix -i /etc/ssh/ssh_host_ed25519_key -e secrets/cloudflared-credentials.age
   ```

   The `env` is load-bearing: sudo strips `EDITOR`, and ragenix then blocks on an interactive
   editor with no visible prompt.

   While cert.pem is still present, create the DNS records too (step 2), then remove it — it is
   a zone-scoped management credential that can create and delete tunnels and DNS records, and
   nothing at runtime needs it:

   ```bash
   shred -u ~/.cloudflared/cert.pem ~/.cloudflared/<UUID>.json
   ```

   Re-run `cloudflared tunnel login` if you ever need it again.

   Delete any tunnel you already created in the dashboard — it cannot be reused.

   > If you would rather not do the browser login, you can create a local-config tunnel
   > straight from the API with a token carrying `Cloudflare Tunnel:Edit`:
   > `POST /accounts/<account_id>/cfd_tunnel` with
   > `{"name":"sagittarius-public","config_src":"local","tunnel_secret":"<32 random bytes, base64>"}`.
   > The credentials file is then
   > `{"AccountTag":"<account_id>","TunnelID":"<id from the response>","TunnelSecret":"<the same secret>"}`.

   Note `cloudflared tunnel run` does **not** need cert.pem when the tunnel is identified by
   UUID, which is why `public-edge.nix` deliberately sets no `certificateFile`. That is what
   makes the shred above safe: the running tunnel needs only the credentials file, which agenix
   holds.

2. **DNS.** `CNAME photos.werlberger.org → <tunnel-uuid>.cfargotunnel.com`, and the same for
   `drop.werlberger.org`. Both proxied (orange cloud) — a tunnel CNAME always is. Either add
   these by hand in the DNS tab, or — while cert.pem from step 1 is still around — run:

   ```bash
   nix run nixpkgs#cloudflared -- tunnel route dns sagittarius-public photos.werlberger.org
   nix run nixpkgs#cloudflared -- tunnel route dns sagittarius-public drop.werlberger.org
   ```

   Do **not** add routes to the tunnel in the dashboard. Routing is `published` in
   `public-edge.nix`; the DNS record is the only Cloudflare-side piece.

3. **Enable the One-time PIN login method — do this first.** New Zero Trust organizations
   default to the Cloudflare identity provider; **OTP is no longer added automatically**, and
   until it exists you cannot select it in a policy.

   Zero Trust → Integrations → Identity providers → Add new → **One-time PIN**.

4. **Reusable policy `family`.** Cloudflare renamed the old "Access Groups" to **Rule Groups**
   and narrowed their purpose (they now express OR logic inside Require rules). The thing that
   actually gives one allow-list shared across applications is a **reusable policy**:

   Cloudflare One → **Access Controls → Policies** → add a policy named `family`:
   - Action: **Allow**
   - Rule: **Include** → selector **Emails** → the exact family addresses
     (use *Emails ending in* for a whole domain)
   - Session duration ~24h

   This is the reusable "selected group" — every published service attaches this same policy,
   and editing it propagates to all of them.

5. **Access applications.** Zero Trust → **Access controls → Applications** → Create new
   application → **Self-hosted and private** → **Add public hostname**. One per hostname:
   - Subdomain `photos` / `drop`, domain `werlberger.org`, path empty
   - Session duration ~24h
   - Policies: **add existing** → `family` (do not rewrite the rules inline)
   - Identity providers: **One-time PIN only**; with a single IdP you can also turn on
     *Apply instant authentication* to skip the provider-picker screen
   - No service-auth policies, no Bypass policies
   - Then **Configure → Overview** (or *Additional settings*) → copy the
     **Application Audience (AUD) Tag** → `audTag`

   The AUD is stable — it only changes if the application is deleted and recreated. Each app
   has its own, and the mismatch is deliberate: it is what stops a token minted for one
   hostname being replayed against the other.

6. **Cache rule: bypass cache** on both hostnames. Cloudflare caches some responses by
   extension; family photos should not sit in an edge cache.

7. **Team name** → `cfTeam` (the `<team>` in `https://<team>.cloudflareaccess.com`).

8. Optional: a WAF rate-limiting rule on both hostnames.

9. Flip `enable = true` in `public-edge.nix` and rebuild.

> **Navigation keeps moving.** Cloudflare rolled out a new Zero Trust dashboard and renamed
> several of these objects; tunnels also moved to the main dashboard under Networking → Tunnels.
> If a path above does not match what you see, the object is almost certainly still there under
> a nearby name — search the dashboard for "Policies", "Identity providers" or "Applications"
> rather than following the breadcrumb literally.

Then set Immich's external domain so its "Copy link" button emits the public URL:
Administration → Settings → Server → External domain → `https://photos.werlberger.org`.
Since `services.immich.settings = null`, the authoritative copy is inside
`secrets/immich-config.json.age` — update it there too, or the next deploy reverts it.

Finally, in Nextcloud: create a folder (e.g. `/family-drop`), share it as a public link with
**File drop (upload only)**. Family can upload but cannot browse what others contributed.

## Day-to-day

**Share an album.** Immich → album → Share → Create link. Enable **Allow uploads**, set an
expiry, optionally a password. Hand out `https://photos.werlberger.org/share/<key>` plus the
Nextcloud drop link for big video.

**Add a person.** Access Controls → Policies → `family` → add their email to the Include rule.
Nothing to deploy, and it propagates to every application using that policy.

**Remove a person.** Same place, remove the email. Their existing session dies at the next
session-duration boundary; to cut it immediately, Zero Trust → Logs → revoke their session.

**Revoke a shared album.** Immich → album → Share → delete the link. This is independent of
Access — deleting a link locks out everyone, including people still in `family`.

**Move dropped files into Immich.** Manual for now. Files land under
`/data/lake/nextcloud/<user>/files/family-drop/`; move them into the Immich album over the
tailnet. If this gets tedious, the upgrade paths are an Immich external library pointed at that
directory, or a timer running `immich-cli upload`.

## Publishing another service

Add one entry to `published` in `public-edge.nix`:

```nix
<name> = {
  hostname  = "<name>.werlberger.org";
  localPort = <free port>;        # check the README port table and `ss -tlnp`
  upstream  = "127.0.0.1:<app port>";
  audTag    = "<from the new Access app>";
  denyPaths = [ "/admin*" "/login" ... ];
};
```

then create the DNS CNAME and an Access application for it, attaching the existing `family`
policy (or a new reusable policy for a different audience). Nothing else changes.

Two things to weigh first:

- **Native clients will not work.** Cloudflare Access authenticates via a browser OTP flow, so
  Jellyfin on Android TV / Apple TV / Roku, and the Immich mobile app, cannot get through. This
  is why Jellyfin is deliberately left tailnet-only. If a native client is required, the
  realistic options are Tailscale node sharing (see the caveat below) or a VPS relay with TLS
  passthrough.
- **Cloudflare sees the plaintext.** TLS terminates at their edge — inherent to Access, and no
  paid tier changes it. Keep genuinely sensitive services (Firefly III, Paperless) tailnet-only.

### If you ever share a Tailscale node with an outsider

`modules/tailscale.nix` sets `trustedInterfaces = [ "tailscale0" ]`, so several services answer
on the tailnet with no auth at all: Prometheus 9090, node_exporter 9100, Homepage 8082, Jellyfin
8096, matter-server 5580. A shared external node reaches all of them. Write a tailnet ACL
**first** — see the trusted-interface finding in `SECURITY-REVIEW.md`.

## After an Immich or Nextcloud upgrade

The path deny-lists are defence-in-depth, not the primary control (both apps return 401 on those
endpoints unauthenticated anyway), but they are the part most likely to drift. Re-check that:

- the share page still renders and uploads still work
- `/admin` and `/login` still return 404 through the public hostname
- no new admin API prefix has appeared outside the deny-list

## Verification

On the NAS:

```bash
systemctl status cloudflared-tunnel-<uuid>
journalctl -u cloudflared-tunnel-<uuid> -n 50        # expect "Registered tunnel connection"
systemd-analyze security cloudflared-tunnel-<uuid>.service

# IPAddress{Allow,Deny} silently no-op without cgroup-v2 BPF — this must be non-empty
systemctl show -p IPAddressDeny cloudflared-tunnel-<uuid>.service

sudo ss -tlnp | grep -E '846[02]'                    # both must be 127.0.0.1 only
```

Gate behaviour, locally:

```bash
# no JWT → rejected before the app sees it
curl -so /dev/null -w '%{http_code}\n' -H 'Host: photos.werlberger.org' http://127.0.0.1:8460/
# → 401

# deny-list
curl -so /dev/null -w '%{http_code}\n' -H 'Host: photos.werlberger.org' http://127.0.0.1:8460/api/auth/login
curl -so /dev/null -w '%{http_code}\n' -H 'Host: drop.werlberger.org'   http://127.0.0.1:8462/login
# → 404, 404
```

Externally, from a phone on cellular (not the tailnet):

- `https://photos.werlberger.org/share/<key>` → OTP prompt → album renders
- upload a photo → appears in the album in the tailnet Immich UI
- play a video **larger than 100 MB** → must work (confirms the cap is request-side only)
- upload a **>100 MB** file via the Nextcloud drop → succeeds; the same file via the Immich
  share page → 413. Confirm both, so the documented split is real rather than assumed
- `https://photos.werlberger.org/admin` → 404
- an email **not** in `family` → Access denies, never reaches the NAS

No-regression:

- tailnet Immich `:8444` and LAN `192.168.1.206:8088` still work
- tailnet Nextcloud `:8450` still works; desktop sync unaffected
- `sudo nmap -6 -p- 2a02:168:ff46::10` from outside shows **no new open ports**
- `tailscale_auth` still gates Grafana, Firefly and Paperless (the Caddy binary changed)

## Troubleshooting

**Everything 404s, or traffic goes somewhere unexpected.** Check that the tunnel is actually
locally managed. In the dashboard a remotely-managed tunnel shows its routes in the UI; a
locally-managed one shows none. If cloudflared logs mention retrieving configuration from the
edge, the tunnel is `config_src: cloudflare` and your Nix ingress is being ignored — recreate it
from the CLI per step 1.

**`cloudflared tunnel run` complains about cert.pem.** It only needs cert.pem when the tunnel is
named rather than identified by UUID. `public-edge.nix` keys the tunnel by UUID precisely to
avoid this; check `tunnelId` is the UUID, not the name.

**Access prompts, but Caddy still 401s.** The JWT audience check is failing. Confirm `audTag`
matches the Application Audience tag of the Access app for *that* hostname — each app has its
own, and a token minted for one is deliberately rejected by another.

## Rollback

Set `enable = false` in `public-edge.nix` and rebuild. Delete the two Cloudflare DNS records.
Nothing else on the host is touched — the module adds no firewall rules and no persistent state.
