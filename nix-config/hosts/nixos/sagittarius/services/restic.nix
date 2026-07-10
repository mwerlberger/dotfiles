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

  # Must match textfileDir in services/monitoring.nix (node_exporter reads here).
  textfileDir = "/var/lib/node-exporter-textfile";

  # Atomically write a small set of health metrics for one restic job so the
  # node_exporter textfile collector can expose them to Prometheus/Grafana.
  # Usage: restic-write-metric <job> <success 0|1> <duration_seconds>
  writeMetric = pkgs.writeShellScript "restic-write-metric" ''
    set -u
    job="$1"; success="$2"; duration="$3"
    now="$(date +%s)"
    f="${textfileDir}/restic-$job.prom"
    tmp="$(mktemp "${textfileDir}/.restic-$job.XXXXXX")"
    {
      printf '# HELP restic_%s_success 1 if the last restic %s run succeeded, else 0\n' "$job" "$job"
      printf '# TYPE restic_%s_success gauge\n' "$job"
      printf 'restic_%s_success %s\n' "$job" "$success"
      printf '# HELP restic_%s_last_run_timestamp_seconds Unix time the last restic %s run finished\n' "$job" "$job"
      printf '# TYPE restic_%s_last_run_timestamp_seconds gauge\n' "$job"
      printf 'restic_%s_last_run_timestamp_seconds %s\n' "$job" "$now"
      printf '# HELP restic_%s_duration_seconds Wall-clock duration of the last restic %s run\n' "$job" "$job"
      printf '# TYPE restic_%s_duration_seconds gauge\n' "$job"
      printf 'restic_%s_duration_seconds %s\n' "$job" "$duration"
    } > "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$f"
  '';
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
      "/data/lake/nextcloud"
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
      # Record start time so the cleanup hook can report backup duration.
      date +%s > ${dbDumpDir}/.backup-start
      ${pkgs.util-linux}/bin/runuser -u postgres -- \
        ${config.services.postgresql.package}/bin/pg_dumpall \
        | ${pkgs.zstd}/bin/zstd -19 -T0 \
        > ${dbDumpDir}/postgres.sql.zst.tmp
      mv ${dbDumpDir}/postgres.sql.zst.tmp ${dbDumpDir}/postgres.sql.zst
    '';

    # Runs as ExecStopPost regardless of outcome; $SERVICE_RESULT reflects the
    # backup result. Emit health metrics before cleaning up.
    backupCleanupCommand = ''
      end="$(date +%s)"
      start="$(cat ${dbDumpDir}/.backup-start 2>/dev/null || echo "$end")"
      if [ "''${SERVICE_RESULT:-success}" = "success" ]; then success=1; else success=0; fi
      ${writeMetric} backup "$success" "$((end - start))"
      rm -f ${dbDumpDir}/.backup-start
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
      start="$(date +%s)"
      rc=0
      ${pkgs.restic}/bin/restic \
        -r ${repo} \
        --password-file ${passwordFile} \
        check --read-data-subset=5% || rc=$?
      end="$(date +%s)"
      if [ "$rc" -eq 0 ]; then success=1; else success=0; fi
      ${writeMetric} check "$success" "$((end - start))"
      exit "$rc"
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
