# frozen_string_literal: true
# Database abstraction layer for MASTER2 system state and configuration

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

      # ============================================================================
      # SCHEMA
      # ============================================================================

      def create_schema
        @connection.execute_batch <<-SQL
          CREATE TABLE IF NOT EXISTS schema_versions (
            component TEXT PRIMARY KEY,
            version INTEGER,
            updated_at TEXT DEFAULT (datetime('now'))
          );

          CREATE TABLE IF NOT EXISTS axioms (
            id TEXT PRIMARY KEY,
            category TEXT,
            protection TEXT,
            title TEXT,
            statement TEXT,
            source TEXT,
            weight REAL,
            check TEXT
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

          CREATE TABLE IF NOT EXISTS shell_commands (
            name TEXT PRIMARY KEY,
            category TEXT,
            danger TEXT,
            requires_root BOOLEAN
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
        SQL
      end

      # ============================================================================
      # SEED
      # ============================================================================

      def seed_data
        return if data_is_current?
        seed_axioms
        seed_aesthetics
        seed_council
        seed_config
        seed_shell_commands
        mark_data_current
      end

      def data_is_current?
        version = @connection.execute("SELECT version FROM schema_versions WHERE component = 'seed_data'").first
        return false unless version
        
        tables_empty = @connection.execute("SELECT COUNT(*) as count FROM axioms").first["count"] == 0
        return false if tables_empty
        
        version["version"] == current_data_version
      end

      def current_data_version
        1
      end

      def mark_data_current
        @connection.execute(
          "INSERT OR REPLACE INTO schema_versions (component, version, updated_at) VALUES (?, ?, datetime('now'))",
          ["seed_data", current_data_version]
        )
      end

      def reseed!
        @connection.execute("DELETE FROM axioms")
        @connection.execute("DELETE FROM council")
        @connection.execute("DELETE FROM config WHERE key NOT LIKE 'runtime_%'")
        @connection.execute("DELETE FROM shell_commands")
        @connection.execute("DELETE FROM schema_versions WHERE component = 'seed_data'")
        seed_data
      end

      def seed_axioms
        axioms_path = "#{MASTER.root}/data/axioms.yml"
        return unless File.exist?(axioms_path)

        axioms = YAML.safe_load_file(axioms_path)
        return unless axioms.is_a?(Array)

        axioms.each do |axiom|
          @connection.execute(
            "INSERT OR REPLACE INTO axioms (id, category, protection, title, statement, source, weight, check) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            [axiom["id"], axiom["category"], axiom["protection"], axiom["title"], axiom["statement"], axiom["source"], axiom["weight"], axiom["check"]]
          )
        end
      end

      def seed_aesthetics
        aesthetics_path = "#{MASTER.root}/data/aesthetics.yml"
        return unless File.exist?(aesthetics_path)

        aesthetics = YAML.safe_load_file(aesthetics_path)
        return unless aesthetics.is_a?(Array)

        aesthetics.each do |aesthetic|
          @connection.execute(
            "INSERT OR REPLACE INTO axioms (id, category, protection, title, statement, source, weight, check) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            ["aesthetic.#{aesthetic["id"]}", "aesthetic", "GUIDANCE", aesthetic["principle"], aesthetic["application"], "Japanese Aesthetics", nil, nil]
          )
        end
      end

      def seed_council
        council_path = "#{MASTER.root}/data/council.yml"
        return unless File.exist?(council_path)

        data = YAML.safe_load_file(council_path)
        return unless data.is_a?(Hash)

        config = data["config"]
        personas = data["personas"]

        return unless config && personas

        personas.each do |persona|
          @connection.execute(
            "INSERT OR REPLACE INTO council (slug, name, weight, temperature, veto, directive) VALUES (?, ?, ?, ?, ?, ?)",
            [persona["slug"], persona["name"], persona["weight"], persona["temperature"], persona["veto"] ? 1 : 0, persona["directive"]]
          )
        end

        config.each do |key, value|
          if key == "veto_precedence"
            @connection.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", ["council_veto_precedence", value.join(",")])
          else
            @connection.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", ["council_#{key}", value.to_s])
          end
        end
      end

      def seed_config
        config_path = "#{MASTER.root}/data/config.yml"
        return unless File.exist?(config_path)

        data = YAML.safe_load_file(config_path)
        return unless data.is_a?(Hash)

        data.each do |key, value|
          if key == "rates" && value.is_a?(Hash)
            value.each do |model, rates|
              @connection.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", ["rate_#{model}_in", rates["in"].to_s])
              @connection.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", ["rate_#{model}_out", rates["out"].to_s])
              @connection.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", ["rate_#{model}_tier", rates["tier"].to_s])
            end
          else
            @connection.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", [key, value.to_s])
          end
        end
      end

      def seed_shell_commands
        shell_path = "#{MASTER.root}/data/shell.yml"
        return unless File.exist?(shell_path)

        data = YAML.safe_load_file(shell_path)
        return unless data.is_a?(Hash) && data["commands"]

        data["commands"].each do |cmd|
          @connection.execute(
            "INSERT OR REPLACE INTO shell_commands (name, category, danger, requires_root) VALUES (?, ?, ?, ?)",
            [cmd["name"], cmd["category"], cmd["danger"], cmd["requires_root"] ? 1 : 0]
          )
        end
      end

      # ============================================================================
      # QUERIES
      # ============================================================================

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
