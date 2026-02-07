# frozen_string_literal: true

require "sqlite3"
require "yaml"

module MASTER
  module DB
    class << self
      attr_reader :connection
    end

    def self.setup(path: "#{MASTER.root}/master.db")
      @mutex ||= Mutex.new
      @connection = SQLite3::Database.new(path)
      @connection.results_as_hash = true
      migrate!
      seed!
    end

    def self.synchronize(&block)
      @mutex.synchronize(&block)
    end

    def self.migrate!
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

          CREATE TABLE IF NOT EXISTS models (
            id TEXT PRIMARY KEY,
            alias TEXT,
            tier TEXT,
            input_cost REAL,
            output_cost REAL,
            provider TEXT
          );

          CREATE TABLE IF NOT EXISTS compression_patterns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT,
            pattern TEXT
          );
        SQL
    end

    def self.seed!
        seed_axioms
        seed_council
        seed_zsh_patterns
        seed_openbsd_patterns
        seed_models
        seed_compression
        seed_budget
    end

    def self.seed_axioms
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

    def self.seed_council
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

    def self.seed_zsh_patterns
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

    def self.seed_openbsd_patterns
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

    def self.seed_models
        models_path = "#{MASTER.root}/data/models.yml"
        return unless File.exist?(models_path)

        models = YAML.safe_load_file(models_path)
        return unless models.is_a?(Array)

        models.each do |model|
          @connection.execute(
            "INSERT OR REPLACE INTO models (id, alias, tier, input_cost, output_cost, provider) VALUES (?, ?, ?, ?, ?, ?)",
            [model["id"], model["alias"], model["tier"], model["input_cost"], model["output_cost"], model["provider"]]
          )
        end
    end

    def self.seed_compression
        compression_path = "#{MASTER.root}/data/compression.yml"
        return unless File.exist?(compression_path)

        data = YAML.safe_load_file(compression_path)
        return unless data.is_a?(Hash)

        # Seed filler words
        if data["fillers"]&.is_a?(Array)
          data["fillers"].each do |word|
            @connection.execute(
              "INSERT OR REPLACE INTO compression_patterns (category, pattern) VALUES (?, ?)",
              ["filler", word]
            )
          end
        end

        # Seed phrases
        if data["phrases"]&.is_a?(Array)
          data["phrases"].each do |phrase|
            @connection.execute(
              "INSERT OR REPLACE INTO compression_patterns (category, pattern) VALUES (?, ?)",
              ["phrase", phrase]
            )
          end
        end
    end

    def self.seed_budget
        budget_path = "#{MASTER.root}/data/budget.yml"
        return unless File.exist?(budget_path)

        data = YAML.safe_load_file(budget_path)
        return unless data.is_a?(Hash) && data["budget"]

        budget = data["budget"]
        
        # Store budget limit
        if budget["limit"]
          @connection.execute(
            "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
            ["budget_limit", budget["limit"].to_s]
          )
        end
        
        # Store thresholds
        if budget["thresholds"]&.is_a?(Hash)
          budget["thresholds"].each do |tier, value|
            @connection.execute(
              "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
              ["budget_threshold_#{tier}", value.to_s]
            )
          end
        end
    end

    def self.zsh_patterns
        @connection.execute("SELECT * FROM zsh_patterns ORDER BY category, command")
    end

    def self.openbsd_patterns(category: nil)
        if category
          @connection.execute("SELECT * FROM openbsd_patterns WHERE category = ? ORDER BY category, key, command", [category])
        else
          @connection.execute("SELECT * FROM openbsd_patterns ORDER BY category, key, command")
        end
      end

      def axioms(category: nil, protection: nil)
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

    def self.council(veto_only: false)
        query = "SELECT * FROM council"
        query += " WHERE veto = 1" if veto_only
        query += " ORDER BY weight DESC, name ASC"
        @connection.execute(query)
    end

    def self.log_cost(model:, tokens_in:, tokens_out:, cost:)
        synchronize do
          @connection.execute(
            "INSERT INTO costs (model, tokens_in, tokens_out, cost) VALUES (?, ?, ?, ?)",
            [model, tokens_in, tokens_out, cost]
          )
        end
      end

      def total_cost
        result = @connection.execute("SELECT SUM(cost) as total FROM costs").first
        result["total"].to_f
    end

        def self.trip!(model)
      synchronize do
        @connection.execute(
          "INSERT INTO circuits (model, failures, last_failure, state) VALUES (?, 1, datetime('now'), 'closed')
           ON CONFLICT(model) DO UPDATE SET failures = failures + 1, last_failure = datetime('now')",
          [model]
        )
      end
    end

    def self.reset!(model)
      synchronize do
        @connection.execute(
          "INSERT INTO circuits (model, failures, state) VALUES (?, 0, 'closed')
           ON CONFLICT(model) DO UPDATE SET failures = 0, state = 'closed'",
          [model]
        )
      end
    end

    def self.circuit(model)
      @connection.execute("SELECT * FROM circuits WHERE model = ?", [model]).first
    end

    def self.config(key)
      result = @connection.execute("SELECT value FROM config WHERE key = ?", [key]).first
      result ? result["value"] : nil
    end

    def self.compression_patterns(category: nil)
      if category
        @connection.execute("SELECT * FROM compression_patterns WHERE category = ?", [category])
      else
        @connection.execute("SELECT * FROM compression_patterns")
      end
    end
  end
end
