# Restic First-Run Checklist

How to validate the `restic.nix` config and kick off the first backup to the
Hetzner Storage Box. Companion doc to `RESTORE.md` (recovery) and `restic.nix`
(declaration).

## 1. Validate config

```bash
cd ~/dotfiles/nix-config
just nas-build-dr   # dry build — catches eval/syntax errors without applying
```

If clean, apply:

```bash
just nas-switch
```

## 2. Pre-flight checks (as root)

```bash
sudo -i

# Secret was decrypted by activation
ls -la /run/agenix/restic-password
cat /run/agenix/restic-password   # should print the password

# restic is now in PATH system-wide
restic version

# SSH host key is cached for the systemd-run case (no interactive prompt)
ssh -p 23 -i /root/.ssh/hetzner_storage u585627@u585627.your-storagebox.de exit

# Restic can talk to the repo
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  snapshots
# Should print "no snapshots found" with no errors.

# Units are loaded
systemctl list-timers 'restic-*'
```

## 3. Small smoke test first

Don't kick off 1.2 T blind. Back up just `/etc/nixos` manually to confirm the
whole pipeline works:

```bash
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  backup /etc/nixos
```

Should finish in seconds. Verify:

```bash
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  snapshots
```

## 4. Trigger the first real backup

It will take a *long* time (rough math: 1.2 TB at 50 Mbps ≈ 56 h; at gigabit
symmetric ≈ 3 h). Run it in `tmux`/`screen` so the watch session can come and
go:

```bash
tmux new -s restic
# inside tmux:
systemctl start restic-backups-nas
journalctl -fu restic-backups-nas
# Ctrl-b d to detach, tmux a -t restic to reattach.
```

The systemd unit holds a lock, so the daily timer firing midway is a no-op.

## 5. After it finishes

```bash
# Confirm snapshot landed
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  snapshots

# FUSE-mount and spot-check a few files
mkdir -p /mnt/restic
restic -r sftp:hetzner-backup:./restic \
  --password-file /run/agenix/restic-password \
  mount /mnt/restic &
ls /mnt/restic/snapshots/latest/etc/nixos
diff -r /mnt/restic/snapshots/latest/etc/nixos /etc/nixos | head
fusermount -u /mnt/restic

# Run the integrity check (5% sample)
systemctl start restic-check
journalctl -fu restic-check
```

## Things that may bite you

- **Postgres dump permissions**: if `pg_dumpall -U postgres` errors with auth,
  we need either `sudo -u postgres` or a peer-auth rule. Will show up in the
  journal on the first systemd-driven run.
- **Upload throttling**: if backups saturate your uplink, add
  `--limit-upload <KiB/s>` to `extraBackupArgs` in `restic.nix`, e.g.
  `"--limit-upload=20000"` caps at ~20 MB/s.
- **Timer first run**: `Persistent = true` means if the first scheduled time
  is missed (e.g. machine off), it'll fire on next boot.

## Phase 2: add the raw photo dump

Once the initial backup is done and you're ready to include the 2.1 T raw
Synology photos:

1. Remove `"/data/lake/photos/synology_photos"` from the `exclude` list in
   `restic.nix`.
2. `just nas-switch`.
3. The next backup run will upload them. Expect another long initial run.
