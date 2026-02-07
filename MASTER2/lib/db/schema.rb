# frozen_string_literal: true

module MASTER
  module DB
    module Schema
      TABLES = <<~SQL
        CREATE TABLE IF NOT EXISTS axioms (
          id TEXT PRIMARY KEY,
          category TEXT,
          protection TEXT,
          title TEXT,
          statement TEXT,
          source TEXT
        );

        CREATE TABLE IF NOT EXISTS council (
          slug TEXT PRIMARY KEY,
          name TEXT,
          weight REAL,
          temperature REAL,
          veto BOOLEAN,
          directive TEXT
        );

        CREATE TABLE IF NOT EXISTS config (
          key TEXT PRIMARY KEY,
          value TEXT
        );

        CREATE TABLE IF NOT EXISTS costs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          model TEXT,
          tokens_in INTEGER,
          tokens_out INTEGER,
          cost REAL,
          created_at TEXT DEFAULT (datetime('now'))
        );

        CREATE TABLE IF NOT EXISTS circuits (
          model TEXT PRIMARY KEY,
          failures INTEGER DEFAULT 0,
          last_failure TEXT,
          state TEXT DEFAULT 'closed'
        );

        CREATE TABLE IF NOT EXISTS agents (
          id TEXT PRIMARY KEY,
          parent_id TEXT,
          scope TEXT,
          status TEXT DEFAULT 'pending',
          task_json TEXT,
          result_json TEXT,
          budget REAL,
          budget_spent REAL DEFAULT 0,
          user_agent TEXT,
          created_at TEXT DEFAULT (datetime('now')),
          finished_at TEXT
        );

        CREATE TABLE IF NOT EXISTS agent_reputation (
          agent_scope TEXT PRIMARY KEY,
          total_runs INTEGER DEFAULT 0,
          successful INTEGER DEFAULT 0,
          rejected INTEGER DEFAULT 0,
          injection_attempts INTEGER DEFAULT 0,
          timeouts INTEGER DEFAULT 0,
          trust_score REAL DEFAULT 1.0
        );
      SQL

      def self.migrate!(db)
        db.execute_batch(TABLES)
      end
    end
  end
end
