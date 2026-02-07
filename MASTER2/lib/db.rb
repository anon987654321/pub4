# frozen_string_literal: true

require "sqlite3"
require "yaml"

module MASTER
  module DB
    class << self
      attr_accessor :connection

      def setup(path: "#{MASTER.root}/master.db")
        @connection = SQLite3::Database.new(path)
        @connection.results_as_hash = true
        create_schema
        seed_data
      end

      def create_schema
        @connection.execute_batch <<~SQL
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

          CREATE TABLE IF NOT EXISTS zsh_patterns (
            id TEXT PRIMARY KEY,
            category TEXT,
            command TEXT,
            replacement TEXT
          );

          CREATE TABLE IF NOT EXISTS openbsd_patterns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT,
            key TEXT,
            value TEXT,
            command TEXT,
            replacement TEXT
          );
        SQL
      end

      def seed_data
        seed_axioms
        seed_council
        seed_zsh_patterns
        seed_openbsd_patterns
      end

      def seed_axioms
        axioms_path = "#{MASTER.root}/data/axioms.yml"
        return unless File.exist?(axioms_path)

        axioms = YAML.safe_load_file(axioms_path)
        return unless axioms.is_a?(Array)

        axioms.each do |axiom|
          @connection.execute(
            "INSERT OR REPLACE INTO axioms (id, category, protection, title, statement, source) VALUES (?, ?, ?, ?, ?, ?)",
            [axiom["id"], axiom["category"], axiom["protection"], axiom["title"], axiom["statement"], axiom["source"]]
          )
        end
      end

      def seed_council
        council_path = "#{MASTER.root}/data/council.yml"
        return unless File.exist?(council_path)

        data = YAML.safe_load_file(council_path)
        return unless data.is_a?(Array)

        # Filter out council parameters (non-hash entries or entries without slug)
        personas = data.select { |item| item.is_a?(Hash) && item["slug"] }

        personas.each do |persona|
          @connection.execute(
            "INSERT OR REPLACE INTO council (slug, name, weight, temperature, veto, directive) VALUES (?, ?, ?, ?, ?, ?)",
            [persona["slug"], persona["name"], persona["weight"], persona["temperature"], persona["veto"] ? 1 : 0, persona["directive"]]
          )
        end

        # Store council parameters in config table
        params = data.find { |item| item.is_a?(Hash) && !item["slug"] }
        if params
          params.each do |key, value|
            next if key == "veto_precedence" # Special handling for arrays

            @connection.execute(
              "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
              ["council_#{key}", value.to_s]
            )
          end
          
          # Store veto_precedence as comma-separated string
          if params["veto_precedence"]
            @connection.execute(
              "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
              ["council_veto_precedence", params["veto_precedence"].join(",")]
            )
          end
        end
      end

      def seed_zsh_patterns
        patterns_path = "#{MASTER.root}/data/zsh_patterns.yml"
        return unless File.exist?(patterns_path)

        data = YAML.safe_load_file(patterns_path)
        return unless data.is_a?(Hash)

        # Seed forbidden commands
        if data["forbidden_commands"]&.is_a?(Array)
          data["forbidden_commands"].each_with_index do |item, idx|
            @connection.execute(
              "INSERT OR REPLACE INTO zsh_patterns (id, category, command, replacement) VALUES (?, ?, ?, ?)",
              ["forbidden_#{idx}", "forbidden", item["command"], item["replacement"]]
            )
          end
        end

        # Seed native patterns
        if data["native_patterns"]&.is_a?(Hash)
          data["native_patterns"].each_with_index do |(name, pattern), idx|
            @connection.execute(
              "INSERT OR REPLACE INTO zsh_patterns (id, category, command, replacement) VALUES (?, ?, ?, ?)",
              ["native_#{idx}", "native", name.to_s, pattern]
            )
          end
        end
      end

      def seed_openbsd_patterns
        patterns_path = "#{MASTER.root}/data/openbsd_patterns.yml"
        return unless File.exist?(patterns_path)

        data = YAML.safe_load_file(patterns_path)
        return unless data.is_a?(Hash)

        # Seed forbidden commands
        if data["forbidden"]&.is_a?(Array)
          data["forbidden"].each do |item|
            @connection.execute(
              "INSERT OR REPLACE INTO openbsd_patterns (category, command, replacement) VALUES (?, ?, ?)",
              ["forbidden", item["command"], item["replacement"]]
            )
          end
        end

        # Seed service management patterns
        if data["service_management"]&.is_a?(Hash)
          data["service_management"].each do |key, value|
            @connection.execute(
              "INSERT OR REPLACE INTO openbsd_patterns (category, key, value) VALUES (?, ?, ?)",
              ["service_management", key.to_s, value]
            )
          end
        end

        # Seed config paths
        if data["config_paths"]&.is_a?(Hash)
          data["config_paths"].each do |key, value|
            @connection.execute(
              "INSERT OR REPLACE INTO openbsd_patterns (category, key, value) VALUES (?, ?, ?)",
              ["config_paths", key.to_s, value]
            )
          end
        end

        # Seed package management patterns
        if data["package_management"]&.is_a?(Hash)
          data["package_management"].each do |key, value|
            @connection.execute(
              "INSERT OR REPLACE INTO openbsd_patterns (category, key, value) VALUES (?, ?, ?)",
              ["package_management", key.to_s, value]
            )
          end
        end

        # Seed security patterns
        if data["security"]&.is_a?(Hash)
          data["security"].each do |key, value|
            @connection.execute(
              "INSERT OR REPLACE INTO openbsd_patterns (category, key, value) VALUES (?, ?, ?)",
              ["security", key.to_s, value]
            )
          end
        end
      end

      def get_zsh_patterns
        @connection.execute("SELECT * FROM zsh_patterns ORDER BY category, command")
      end

      def get_openbsd_patterns(category: nil)
        if category
          @connection.execute("SELECT * FROM openbsd_patterns WHERE category = ? ORDER BY category, key, command", [category])
        else
          @connection.execute("SELECT * FROM openbsd_patterns ORDER BY category, key, command")
        end
      end

      def get_axioms(category: nil, protection: nil)
        query = "SELECT * FROM axioms"
        conditions = []
        params = []

        if category
          conditions << "category = ?"
          params << category
        end

        if protection
          conditions << "protection = ?"
          params << protection
        end

        query += " WHERE #{conditions.join(" AND ")}" unless conditions.empty?
        query += " ORDER BY CASE protection WHEN 'ABSOLUTE' THEN 1 WHEN 'PROTECTED' THEN 2 ELSE 3 END"

        @connection.execute(query, params)
      end

      def get_council_members(veto_only: false)
        query = "SELECT * FROM council"
        query += " WHERE veto = 1" if veto_only
        query += " ORDER BY weight DESC, name ASC"
        @connection.execute(query)
      end

      def record_cost(model:, tokens_in:, tokens_out:, cost:)
        @connection.execute(
          "INSERT INTO costs (model, tokens_in, tokens_out, cost) VALUES (?, ?, ?, ?)",
          [model, tokens_in, tokens_out, cost]
        )
      end

      def get_total_cost
        result = @connection.execute("SELECT SUM(cost) as total FROM costs").first
        result["total"].to_f
      end

      def record_circuit_failure(model)
        @connection.execute(
          "INSERT INTO circuits (model, failures, last_failure, state) VALUES (?, 1, datetime('now'), 'closed')
           ON CONFLICT(model) DO UPDATE SET failures = failures + 1, last_failure = datetime('now')",
          [model]
        )
      end

      def record_circuit_success(model)
        @connection.execute(
          "INSERT INTO circuits (model, failures, state) VALUES (?, 0, 'closed')
           ON CONFLICT(model) DO UPDATE SET failures = 0, state = 'closed'",
          [model]
        )
      end

      def get_circuit(model)
        @connection.execute("SELECT * FROM circuits WHERE model = ?", [model]).first
      end

      def get_config(key)
        result = @connection.execute("SELECT value FROM config WHERE key = ?", [key]).first
        result ? result["value"] : nil
      end
    end
  end
end
