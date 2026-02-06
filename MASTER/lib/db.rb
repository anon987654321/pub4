# frozen_string_literal: true

require "sqlite3"

module MASTER
  module DB
    class << self
      def connection
        @connection ||= begin
          db = SQLite3::Database.new(db_path)
          db.results_as_hash = true
          db
        end
      end

      def db_path
        File.join(MASTER.root, "master.db")
      end

      def initialize_schema
        connection.execute_batch <<~SQL
          CREATE TABLE IF NOT EXISTS principles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            text TEXT NOT NULL,
            protection_level INTEGER DEFAULT 0,
            category TEXT
          );

          CREATE TABLE IF NOT EXISTS personas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            role TEXT,
            instructions TEXT NOT NULL,
            weight INTEGER DEFAULT 0
          );

          CREATE TABLE IF NOT EXISTS config (
            key TEXT PRIMARY KEY,
            value TEXT
          );

          CREATE TABLE IF NOT EXISTS costs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model TEXT NOT NULL,
            tokens_in INTEGER DEFAULT 0,
            tokens_out INTEGER DEFAULT 0,
            cost REAL DEFAULT 0.0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
          );

          CREATE TABLE IF NOT EXISTS circuits (
            model TEXT PRIMARY KEY,
            failures INTEGER DEFAULT 0,
            last_failure TEXT,
            state TEXT DEFAULT 'closed'
          );
        SQL
      end

      def get_persona(name)
        row = connection.get_first_row("SELECT * FROM personas WHERE name = ? LIMIT 1", name)
        row ? row.transform_keys(&:to_sym) : nil
      end

      def get_principles(protection_level: 0)
        connection.execute("SELECT * FROM principles WHERE protection_level >= ?", protection_level).map do |row|
          row.transform_keys(&:to_sym)
        end
      end

      def get_config(key)
        row = connection.get_first_row("SELECT value FROM config WHERE key = ? LIMIT 1", key)
        row ? row["value"] : nil
      end

      def set_config(key, value)
        connection.execute("INSERT INTO config (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?", [key, value, value])
      end
    end
  end
end
