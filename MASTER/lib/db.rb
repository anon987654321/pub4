# frozen_string_literal: true

require 'sqlite3'
require 'json'

module MASTER
  module DB
    DB_PATH = File.expand_path("../../master.db", __FILE__)

    def self.connection
      @connection ||= SQLite3::Database.new(DB_PATH).tap do |db|
        db.results_as_hash = true
      end
    end

    def self.initialize_schema
      connection.execute_batch <<-SQL
        CREATE TABLE IF NOT EXISTS principles (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          text TEXT NOT NULL,
          protection_level TEXT DEFAULT 'NEGOTIABLE',
          category TEXT
        );

        CREATE TABLE IF NOT EXISTS personas (
          id INTEGER PRIMARY KEY,
          name TEXT NOT NULL UNIQUE,
          role TEXT,
          instructions TEXT,
          weight REAL DEFAULT 1.0
        );

        CREATE TABLE IF NOT EXISTS config (
          key TEXT PRIMARY KEY,
          value TEXT
        );

        CREATE TABLE IF NOT EXISTS memories (
          id INTEGER PRIMARY KEY,
          context TEXT,
          content TEXT NOT NULL,
          embedding TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS costs (
          id INTEGER PRIMARY KEY,
          model TEXT NOT NULL,
          tokens_in INTEGER DEFAULT 0,
          tokens_out INTEGER DEFAULT 0,
          cost REAL DEFAULT 0.0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS circuits (
          model TEXT PRIMARY KEY,
          failures INTEGER DEFAULT 0,
          last_failure DATETIME,
          state TEXT DEFAULT 'closed'
        );

        CREATE TABLE IF NOT EXISTS hooks (
          id INTEGER PRIMARY KEY,
          event TEXT NOT NULL,
          handler TEXT NOT NULL,
          priority INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS sessions (
          id INTEGER PRIMARY KEY,
          started_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          total_cost REAL DEFAULT 0.0
        );

        CREATE TABLE IF NOT EXISTS evolutions (
          id INTEGER PRIMARY KEY,
          file TEXT NOT NULL,
          before_sha TEXT,
          after_sha TEXT,
          tests_passed INTEGER DEFAULT 0,
          rolled_back INTEGER DEFAULT 0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER PRIMARY KEY,
          session_id INTEGER,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          model TEXT,
          tokens INTEGER DEFAULT 0,
          cost REAL DEFAULT 0.0,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (session_id) REFERENCES sessions(id)
        );
      SQL
    end

    def self.track_cost(model:, tokens_in:, tokens_out:, cost: 0.0)
      connection.execute(
        "INSERT INTO costs (model, tokens_in, tokens_out, cost) VALUES (?, ?, ?, ?)",
        [model, tokens_in, tokens_out, cost]
      )
    end

    def self.get_persona(name)
      row = connection.get_first_row(
        "SELECT * FROM personas WHERE name = ?",
        [name]
      )
      row ? Hash[row] : nil
    end

    def self.get_principles(protection_level: nil)
      sql = "SELECT * FROM principles"
      sql += " WHERE protection_level = ?" if protection_level
      connection.execute(sql, protection_level ? [protection_level] : [])
    end

    def self.system_prompt
      get_config("system_prompt") || "You are MASTER, a universal code refactoring and completion engine."
    end

    def self.get_config(key)
      row = connection.get_first_row("SELECT value FROM config WHERE key = ?", [key])
      row ? row["value"] : nil
    end

    def self.set_config(key, value)
      connection.execute(
        "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
        [key, value]
      )
    end

    def self.record_circuit_failure(model)
      connection.execute(
        "INSERT OR REPLACE INTO circuits (model, failures, last_failure, state) 
         VALUES (?, COALESCE((SELECT failures FROM circuits WHERE model = ?), 0) + 1, 
         datetime('now'), ?)",
        [model, model, 'open']
      )
    end

    def self.get_circuit_state(model)
      row = connection.get_first_row("SELECT * FROM circuits WHERE model = ?", [model])
      return nil unless row
      
      failures = row["failures"].to_i
      if failures >= 3
        'open'
      else
        'closed'
      end
    end

    def self.reset_circuit(model)
      connection.execute("DELETE FROM circuits WHERE model = ?", [model])
    end
  end
end
