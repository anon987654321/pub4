# frozen_string_literal: true

require "sqlite3"
require "yaml"

module MASTER
  module DB
    def self.connection
      @connection ||= begin
        db = SQLite3::Database.new(File.join(MASTER.root, "master.db"))
        db.results_as_hash = true
        db
      end
    end

    def self.setup
      schema
      seed_if_empty
    end

    def self.schema
      connection.execute_batch(<<~SQL)
        CREATE TABLE IF NOT EXISTS principles (
          id INTEGER PRIMARY KEY, name TEXT UNIQUE, text TEXT,
          protection_level TEXT DEFAULT 'NEGOTIABLE', category TEXT
        );
        CREATE TABLE IF NOT EXISTS personas (
          id INTEGER PRIMARY KEY, name TEXT UNIQUE, role TEXT,
          instructions TEXT, weight REAL DEFAULT 1.0
        );
        CREATE TABLE IF NOT EXISTS config (
          key TEXT PRIMARY KEY, value TEXT
        );
        CREATE TABLE IF NOT EXISTS costs (
          id INTEGER PRIMARY KEY, model TEXT, tokens_in INTEGER,
          tokens_out INTEGER, cost REAL, created_at TEXT DEFAULT (datetime('now'))
        );
        CREATE TABLE IF NOT EXISTS circuits (
          model TEXT PRIMARY KEY, failures INTEGER DEFAULT 0,
          last_failure TEXT, state TEXT DEFAULT 'closed'
        );
      SQL
    end

    def self.seed_if_empty
      return unless connection.get_first_value("SELECT COUNT(*) FROM principles").to_i.zero?

      seed_file("principles", File.join(MASTER.root, "data", "principles.yml"))
      seed_file("personas", File.join(MASTER.root, "data", "personas.yml"))
    end

    def self.seed_file(table, path)
      return unless File.exist?(path)
      data = YAML.load_file(path)
      key = data.keys.find { |k| k == table } || data.keys.first
      return unless data[key].is_a?(Hash)

      data[key].each do |name, entry|
        case table
        when "principles"
          connection.execute(
            "INSERT OR IGNORE INTO principles (name, text, protection_level, category) VALUES (?, ?, ?, ?)",
            [entry["name"] || name, entry["description"] || "", entry["tier"] == "core" ? "PROTECTED" : "NEGOTIABLE", entry["tier"] || "general"]
          )
        when "personas"
          connection.execute(
            "INSERT OR IGNORE INTO personas (name, role, instructions, weight) VALUES (?, ?, ?, ?)",
            [entry["name"] || name, entry["description"] || "", entry["system_prompt"] || entry["style"] || "", 1.0]
          )
        end
      end
    end

    def self.get_persona(name)
      connection.get_first_row("SELECT * FROM personas WHERE name = ?", [name])
    end

    def self.get_config(key)
      row = connection.get_first_row("SELECT value FROM config WHERE key = ?", [key])
      row && row["value"]
    end

    def self.set_config(key, value)
      connection.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", [key, value])
    end
  end
end
