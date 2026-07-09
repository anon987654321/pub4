#!/bin/sh
# Sweep amber Solid Queue backlog on vm23. Uses sqlite3 (no full Rails boot).
set -e
APP=amber
DIR=/home/${APP}/app
QUEUE_DB="${DIR}/storage/production_queue.sqlite3"

report_queue() {
  echo "==> amber queue report (${QUEUE_DB})"
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
  echo "==> amber queue sweep"
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