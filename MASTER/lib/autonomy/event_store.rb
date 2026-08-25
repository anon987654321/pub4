# frozen_string_literal: true

require "fileutils"
require "json"
require "sqlite3"
require "time"

module Master
  module Autonomy
    # Durable event log and task store.
    #
    # SQLite is intentionally boring here. It gives MASTER transactions,
    # indexes, crash recovery and a single portable file without inventing a
    # second persistence protocol. The event table is append-only; task/goal
    # rows are projections that make resume/status cheap.
    class EventStore
      SCHEMA = <<~SQL
        PRAGMA journal_mode = WAL;
        PRAGMA busy_timeout = 5000;

        CREATE TABLE IF NOT EXISTS goals (
          id TEXT PRIMARY KEY,
          objective TEXT NOT NULL,
          risk TEXT NOT NULL,
          status TEXT NOT NULL,
          budget_json TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS tasks (
          id TEXT PRIMARY KEY,
          goal_id TEXT NOT NULL,
          parent_id TEXT,
          title TEXT NOT NULL,
          state TEXT NOT NULL,
          position INTEGER NOT NULL DEFAULT 0,
          attempts INTEGER NOT NULL DEFAULT 0,
          payload_json TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_tasks_goal_state
          ON tasks(goal_id, state, position);

        CREATE TABLE IF NOT EXISTS events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          goal_id TEXT NOT NULL,
          task_id TEXT,
          kind TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          created_at TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_events_goal
          ON events(goal_id, id);

        CREATE TABLE IF NOT EXISTS checkpoints (
          id TEXT PRIMARY KEY,
          goal_id TEXT NOT NULL,
          task_id TEXT,
          digest TEXT NOT NULL,
          status TEXT NOT NULL,
          payload_json TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      SQL

      def initialize(path)
        FileUtils.mkdir_p(File.dirname(path))
        @db = SQLite3::Database.new(path)
        @db.results_as_hash = true
        @db.execute_batch(SCHEMA)
      end

      def close
        @db.close unless @db.closed?
      end

      def transaction(&block)
        @db.transaction(&block)
      end

      def create_goal(goal)
        now = Time.now.utc.iso8601
        @db.execute("INSERT INTO goals(id, objective, risk, status, budget_json, created_at, updated_at)
           VALUES(?,?,?,?,?,?,?)",
                    [goal.id, goal.objective, goal.risk.to_s, goal.status.to_s, JSON.generate(goal.budget), now, now])
        append(goal.id, nil, "goal.created", goal.to_h)
        goal
      end

      def update_goal(id, status:, budget: nil)
        now = Time.now.utc.iso8601
        if budget
          @db.execute("UPDATE goals SET status=?, budget_json=?, updated_at=? WHERE id=?",
                      [status.to_s, JSON.generate(budget), now, id])
        else
          @db.execute("UPDATE goals SET status=?, updated_at=? WHERE id=?",
                      [status.to_s, now, id])
        end
      end

      def goal(id)
        row = @db.get_first_row("SELECT * FROM goals WHERE id=?", id)
        return unless row

        row
      end

      def create_task(task)
        now = Time.now.utc.iso8601
        @db.execute("INSERT INTO tasks(id, goal_id, parent_id, title, state, position, attempts, payload_json, updated_at)
           VALUES(?,?,?,?,?,?,?,?,?)",
                    [task.id, task.goal_id, task.parent_id, task.title, task.state.to_s, task.position, task.attempts, JSON.generate(task.payload), now])
        append(task.goal_id, task.id, "task.created", task.to_h)
        task
      end

      def update_task(id, state:, attempts: nil, payload: nil)
        row = @db.get_first_row("SELECT * FROM tasks WHERE id=?", id)
        raise "unknown task #{id}" unless row

        @db.execute("UPDATE tasks SET state=?, attempts=?, payload_json=?, updated_at=? WHERE id=?",
                    [state.to_s, attempts.nil? ? row["attempts"] : attempts, payload ? JSON.generate(payload) : row["payload_json"], Time.now.utc.iso8601, id])
      end

      def tasks(goal_id)
        @db.execute("SELECT * FROM tasks WHERE goal_id=? ORDER BY position, id",
                    [goal_id])
      end

      def append(goal_id, task_id, kind, payload = {})
        @db.execute("INSERT INTO events(goal_id, task_id, kind, payload_json, created_at) VALUES(?,?,?,?,?)",
                    [goal_id, task_id, kind.to_s, JSON.generate(payload), Time.now.utc.iso8601])
      end

      def events(goal_id, limit: 200)
        @db.execute("SELECT * FROM events WHERE goal_id=? ORDER BY id DESC LIMIT ?",
                    [goal_id, limit])
      end

      def save_checkpoint(id:, goal_id:, task_id:, digest:, status:, payload:)
        @db.execute("INSERT OR REPLACE INTO checkpoints(id, goal_id, task_id, digest, status, payload_json, created_at)
           VALUES(?,?,?,?,?,?,?)",
                    [id, goal_id, task_id, digest, status.to_s, JSON.generate(payload), Time.now.utc.iso8601])
      end

      def checkpoints(goal_id)
        @db.execute("SELECT * FROM checkpoints WHERE goal_id=? ORDER BY created_at DESC",
                    [goal_id])
      end

      def active_goals
        @db.execute("SELECT * FROM goals WHERE status IN ('running','paused','blocked') ORDER BY updated_at DESC")
      end
    end
  end
end
