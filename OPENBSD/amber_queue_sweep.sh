#!/bin/sh
# Sweep a Solid Queue backlog on vm23 with sqlite3, no Rails boot: report, delete
# finished jobs and orphaned executions, drop unfinished Turbo broadcast jobs and
# duplicate media jobs, report again.
#
# Usage: sh OPENBSD/amber_queue_sweep.sh [APP]     (default amber)
#
# The partner is /usr/local/bin/drain-jobs.sh, which RUNS due jobs hourly from
# cron. This one DELETES what should never run; reach for it when a backlog is
# stale broadcasts and duplicates, not when the queue is merely behind. The
# duplicate-media step names amber's job classes and matches nothing elsewhere.
set -eu

case ${1:-} in
-h|--help)
  echo "usage: sh OPENBSD/amber_queue_sweep.sh [APP]   (default amber; deletes, see header)"
  exit 0
  ;;
esac

APP=${1:-amber}
DIR=/home/${APP}/app
QUEUE_DB="${DIR}/storage/production_queue.sqlite3"
# doas test, not [ -f ]: app homes are 750, so dev cannot see the file itself.
doas test -f "$QUEUE_DB" || { echo "amber_queue_sweep: no queue database at ${QUEUE_DB}" >&2; exit 1; }

report_queue() {
  echo "==> ${APP} queue report (${QUEUE_DB})"
  doas su -m "${APP}" -c "sqlite3 '${QUEUE_DB}' \"
    SELECT class_name, COUNT(*) AS c
    FROM solid_queue_jobs
    WHERE finished_at IS NULL
    GROUP BY class_name
    ORDER BY c DESC
    LIMIT 20;
    SELECT 'pending_total', COUNT(*) FROM solid_queue_jobs WHERE finished_at IS NULL;
  \""
}

sweep_queue() {
  echo "==> ${APP} queue sweep"
  doas su -m "${APP}" -c "sqlite3 '${QUEUE_DB}' \"
    DELETE FROM solid_queue_jobs WHERE finished_at IS NOT NULL;
    DELETE FROM solid_queue_ready_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_scheduled_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_claimed_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_blocked_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_failed_executions
      WHERE job_id NOT IN (SELECT id FROM solid_queue_jobs);
    DELETE FROM solid_queue_ready_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_scheduled_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_claimed_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_blocked_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_failed_executions
      WHERE job_id IN (
        SELECT id FROM solid_queue_jobs
        WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob'
      );
    DELETE FROM solid_queue_jobs
      WHERE finished_at IS NULL AND class_name = 'Turbo::Streams::BroadcastStreamJob';
    WITH ranked AS (
      SELECT id, class_name, arguments,
             ROW_NUMBER() OVER (PARTITION BY class_name, arguments ORDER BY id) AS rn
      FROM solid_queue_jobs
      WHERE finished_at IS NULL
        AND class_name IN ('WardrobeMediaJob', 'Shared::MediaProcessingJob')
    )
    DELETE FROM solid_queue_jobs
    WHERE id IN (SELECT id FROM ranked WHERE rn > 1);
  \""
}

report_queue
sweep_queue
report_queue
