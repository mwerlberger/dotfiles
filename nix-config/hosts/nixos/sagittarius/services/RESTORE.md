# Restic Restore Runbook

Offsite backups for `sagittarius` live on a Hetzner Storage Box, written by the
`restic.nix` module. This document is the recovery side.

The restic password is stored in agenix at `secrets/restic-password.age`, decrypted to
`/run/agenix/restic-password` on the running system. Also stored in my 1Password as `Sagittarius restic password`.

## Repository

- URL: `sftp:hetzner-backup:./restic`
- SSH alias: `hetzner-backup` (defined in `/root/.ssh/config`)
- Underlying host: `u585627.your-storagebox.de:23`
- Identity key: `/root/.ssh/hetzner_storage`
- Repo password: in agenix at `secrets/restic-password.age`, decrypted to
  `/run/agenix/restic-password` on the running system. **Also stored offline**
  (password manager + paper) — losing it = losing the backups.

## On a working system

All commands as root.

### List snapshots

```bash
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  snapshots
```

### Browse a snapshot via FUSE

```bash
mkdir -p /mnt/restic
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  mount /mnt/restic
# Ctrl-C to unmount when done.
```

### Restore specific paths

```bash
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  restore latest --target /tmp/restore --include /etc/nixos
```

### Restore the Postgres dump

The daily backup includes a `pg_dumpall` snapshot at
`/var/backups/db/postgres.sql.zst`.

```bash
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  restore latest --target /tmp/restore --include /var/backups/db

# Stop dependent services first, then:
zstd -d /tmp/restore/var/backups/db/postgres.sql.zst -o /tmp/postgres.sql
sudo -u postgres psql -f /tmp/postgres.sql postgres
```

## Bare-metal recovery

Order of operations after total loss of the NAS:

1. **Reinstall NixOS** from ISO; configure disks & ZFS pool `lake`.
2. **Restore SSH host key** so agenix can decrypt secrets. The host's
   `/etc/ssh/ssh_host_ed25519_key` is the agenix decryption identity. If lost,
   the `restic-password.age` is unreadable on the new host until the new host
   key is added as a recipient and the secret is re-encrypted from the offline
   copy of the password.
3. **Restore `/etc/nixos`** from the latest snapshot.
4. **`nixos-rebuild switch`** — brings up the base system, agenix, services.
5. **Stop all stateful services** before restoring their state:
   ```bash
   systemctl stop immich-server postgresql paperless-* sonarr radarr lidarr \
     prowlarr navidrome jellyfin bookshelf qbittorrent sabnzbd
   ```
6. **Restore `/var/lib`, `/data/lake/{photos,documents}`, `/home`** from the
   latest snapshot.
7. **Restore Postgres** from the dump (see above) into a freshly-initialised
   cluster.
8. **Re-start services** and verify.

## Recovering without the host

If the NAS is gone and you only have a laptop:

1. Install restic locally.
2. Get the repo password from the offline backup of it.
3. Add an SSH key on the laptop with access to the Hetzner Storage Box (Robot
   UI, or via SFTP using the existing key if you still have it).
4. `restic -r sftp:u585627@u585627.your-storagebox.de:23./restic snapshots` etc.
   (You don't need the `hetzner-backup` alias if you spell out the full URL.)

## Schedule

- Backup: daily, randomized 1 h delay (`restic-backups-nas.timer`).
- Integrity check: weekly, 5% read-data sample (`restic-check.timer`).
- Retention: `--keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-yearly 2`.

## First-run / phased inclusion

The first backup excludes `/data/lake/photos/synology_photos` (~2.1 T raw
photo dump) so the initial upload finishes in reasonable time. To include it
later, remove that line from the `exclude` list in `restic.nix` and rebuild.

The following are intentionally **never** backed up offsite:

- `/data/lake/backups` — already redundant copies (synology + old time-machine).
- `/data/lake/media` — re-acquirable movies/tv/music.
- `/data/lake/photos/synology_photos` — phase 1 only (see above).

## Manual operations

```bash
# Trigger a backup right now
systemctl start restic-backups-nas

# Watch it
journalctl -fu restic-backups-nas

# Trigger an integrity check
systemctl start restic-check

# Full integrity check (slow, downloads everything)
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  check --read-data
```
