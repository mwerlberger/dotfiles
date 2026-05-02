{
  config,
  pkgs,
  lib,
  ...
}:

let
  repo = "sftp:hetzner-backup:./restic";
  passwordFile = config.age.secrets.restic-password.path;
  dbDumpDir = "/var/backups/db";
in
{
  systemd.tmpfiles.rules = [
    "d ${dbDumpDir} 0700 root root -"
  ];

  services.restic.backups.nas = {
    repository = repo;
    inherit passwordFile;

    paths = [
      "/etc/nixos"
      "/var/lib"
      "/var/backups/db"
      "/data/lake/photos"
      "/data/lake/documents"
      "/home"
    ];

    exclude = [
      # Phase 1: skip the 2.1T raw-photo dump; re-add after first backup completes.
      "/data/lake/photos/synology_photos"

      # Postgres lives at /var/lib/postgresql but is dumped via backupPrepareCommand.
      "/var/lib/postgresql"

      # Container/VM scratch.
      "/var/lib/docker"
      "/var/lib/containers"
      "/var/lib/machines"
      "/var/lib/portables"

      # NixOS / system internals — recreated on rebuild or boot.
      "/var/lib/systemd"
      "/var/lib/private"
      "/var/lib/nixos"
      "/var/lib/colord"
      "/var/lib/dhcpcd"
      "/var/lib/lastlog"
      "/var/lib/logrotate.status"

      # Caches/queues, recoverable.
      "/var/lib/redis-immich"
      "/var/lib/redis-nextcloud"
      "/var/lib/redis-paperless"

      # Generic noise.
      "**/.cache"
      "**/Cache"
      "**/node_modules"
      "**/*.tmp"
    ];

    backupPrepareCommand = ''
      set -euo pipefail
      install -d -m 0700 ${dbDumpDir}
      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/pg_dumpall \
        | ${pkgs.zstd}/bin/zstd -19 -T0 \
        > ${dbDumpDir}/postgres.sql.zst.tmp
      mv ${dbDumpDir}/postgres.sql.zst.tmp ${dbDumpDir}/postgres.sql.zst
    '';

    backupCleanupCommand = ''
      rm -f ${dbDumpDir}/postgres.sql.zst
    '';

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 12"
      "--keep-yearly 2"
    ];

    extraBackupArgs = [
      "--exclude-caches"
    ];
  };

  # Weekly integrity check: index validation + 5% sample of pack data.
  systemd.services.restic-check = {
    description = "Restic repo integrity check (sample)";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
    script = ''
      ${pkgs.restic}/bin/restic \
        -r ${repo} \
        --password-file ${passwordFile} \
        check --read-data-subset=5%
    '';
  };

  systemd.timers.restic-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "2h";
    };
  };
}
