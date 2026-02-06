#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require 'json'

module MASTER
  # SQLite database layer - single source of truth
  module DB
    # Constants
    ROOT = File.expand_path('..', __dir__)
    DB_PATH = File.join(ROOT, 'master.db')
    SCHEMA_PATH = File.join(ROOT, 'db', 'schema.sql')

    class << self
      # Get or create database connection
      def connection
        @db ||= begin
          db = SQLite3::Database.new(DB_PATH)
          db.results_as_hash = true
          db.execute("PRAGMA journal_mode=WAL")
          db.execute("PRAGMA foreign_keys=ON")
          db.execute("PRAGMA synchronous=NORMAL")
          db
        end
      end

      # Initialize database with schema
      def init!
        return if File.exist?(DB_PATH)
        
        schema = File.read(SCHEMA_PATH)
        connection.execute_batch(schema)
      end

      # Reset database (for testing)
      def reset!
        @db&.close
        @db = nil
        File.delete(DB_PATH) if File.exist?(DB_PATH)
        init!
      end

      # ===== PRINCIPLES =====

      # Get principles, optionally filtered by protection level
      def principles(level: nil, active: true)
        if level
          query = "SELECT * FROM principles WHERE protection_level = ?"
          query += " AND active = 1" if active
          connection.execute(query, [level])
        else
          query = "SELECT * FROM principles"
          query += " WHERE active = 1" if active
          query += " ORDER BY priority ASC"
          connection.execute(query)
        end
      end

      # Get principle by name
      def principle(name)
        connection.get_first_row("SELECT * FROM principles WHERE name = ?", [name])
      end

      # Add or update principle
      def upsert_principle(name:, text:, protection_level:, **opts)
        connection.execute(<<~SQL, [name, text, protection_level, opts[:category], opts[:tier], opts[:priority] || 50, opts[:weight] || 1.0, opts[:auto_fixable] ? 1 : 0])
          INSERT INTO principles (name, text, protection_level, category, tier, priority, weight, auto_fixable)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(name) DO UPDATE SET
            text = excluded.text,
            protection_level = excluded.protection_level,
            category = excluded.category,
            tier = excluded.tier,
            priority = excluded.priority,
            weight = excluded.weight,
            auto_fixable = excluded.auto_fixable,
            updated_at = strftime('%s', 'now')
        SQL
      end

      # ===== PERSONAS =====

      # Get all active personas
      def personas(active: true)
        query = "SELECT * FROM personas"
        query += " WHERE active = 1" if active
        connection.execute(query)
      end

      # Get persona by name
      def persona(name)
        connection.get_first_row("SELECT * FROM personas WHERE name = ?", [name])
      end

      # Add or update persona
      def upsert_persona(name:, **opts)
        params = [
          name,
          opts[:description],
          opts[:greeting],
          opts[:traits].is_a?(Array) ? opts[:traits].to_json : opts[:traits],
          opts[:style],
          opts[:focus].is_a?(Array) ? opts[:focus].to_json : opts[:focus],
          opts[:sources].is_a?(Array) ? opts[:sources].to_json : opts[:sources],
          opts[:rules].is_a?(Array) ? opts[:rules].to_json : opts[:rules],
          opts[:system_prompt],
          opts[:weight] || 0.15,
          opts[:veto_domains].is_a?(Array) ? opts[:veto_domains].to_json : opts[:veto_domains]
        ]
        
        connection.execute(<<~SQL, params)
          INSERT INTO personas (name, description, greeting, traits, style, focus, sources, rules, system_prompt, weight, veto_domains)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(name) DO UPDATE SET
            description = excluded.description,
            greeting = excluded.greeting,
            traits = excluded.traits,
            style = excluded.style,
            focus = excluded.focus,
            sources = excluded.sources,
            rules = excluded.rules,
            system_prompt = excluded.system_prompt,
            weight = excluded.weight,
            veto_domains = excluded.veto_domains,
            updated_at = strftime('%s', 'now')
        SQL
      end

      # ===== COSTS =====

      # Track LLM usage cost
      def track_cost(model:, tier:, tokens_in:, tokens_out:, cost:, session_id: nil)
        connection.execute(
          "INSERT INTO costs (model, tier, tokens_in, tokens_out, cost_usd, session_id, created_at) VALUES (?,?,?,?,?,?,?)",
          [model, tier, tokens_in, tokens_out, cost, session_id, Time.now.to_i]
        )
      end

      # Get today's spending
      def daily_spend
        today = Time.now.to_i - (Time.now.to_i % 86400)
        connection.get_first_value("SELECT COALESCE(SUM(cost_usd), 0) FROM costs WHERE created_at >= ?", [today]) || 0.0
      end

      # Get spending for last N days
      def spending_history(days: 7)
        cutoff = Time.now.to_i - (days * 86400)
        connection.execute(<<~SQL, [cutoff])
          SELECT date(created_at, 'unixepoch', 'localtime') as date,
                 SUM(cost_usd) as total,
                 COUNT(*) as requests
          FROM costs
          WHERE created_at >= ?
          GROUP BY date
          ORDER BY date DESC
        SQL
      end

      # ===== MEMORY =====

      # Store memory
      def store_memory(content:, context: nil, embedding: nil)
        connection.execute(
          "INSERT INTO memory (content, context, embedding, created_at, accessed_at) VALUES (?, ?, ?, ?, ?)",
          [content, context, embedding, Time.now.to_i, Time.now.to_i]
        )
        connection.last_insert_row_id
      end

      # Retrieve recent memories
      def recall_memories(context: nil, limit: 10)
        if context
          connection.execute(
            "SELECT * FROM memory WHERE context = ? ORDER BY accessed_at DESC LIMIT ?",
            [context, limit]
          )
        else
          connection.execute(
            "SELECT * FROM memory ORDER BY accessed_at DESC LIMIT ?",
            [limit]
          )
        end
      end

      # Update memory access time
      def touch_memory(id)
        connection.execute(
          "UPDATE memory SET accessed_at = ?, decay_factor = decay_factor * 1.1 WHERE id = ?",
          [Time.now.to_i, id]
        )
      end

      # ===== CONFIG =====

      # Get config value
      def config(key, default = nil)
        row = connection.get_first_row("SELECT value FROM config WHERE key = ?", [key])
        row ? row['value'] : default
      end

      # Set config value
      def set_config(key, value, protection_level: 'flexible', description: nil)
        connection.execute(<<~SQL, [key, value, protection_level, description])
          INSERT INTO config (key, value, protection_level, description)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(key) DO UPDATE SET
            value = excluded.value,
            updated_at = strftime('%s', 'now')
        SQL
      end

      # ===== CIRCUIT BREAKERS =====

      # Get circuit breaker state
      def circuit_state(model)
        row = connection.get_first_row("SELECT * FROM circuit_breakers WHERE model = ?", [model])
        row || { 'model' => model, 'state' => 'closed', 'failure_count' => 0 }
      end

      # Record circuit breaker failure
      def record_failure(model)
        now = Time.now.to_i
        connection.execute(<<~SQL, [model, now])
          INSERT INTO circuit_breakers (model, failure_count, last_failure_at, updated_at)
          VALUES (?, 1, ?, ?)
          ON CONFLICT(model) DO UPDATE SET
            failure_count = failure_count + 1,
            last_failure_at = excluded.last_failure_at,
            state = CASE WHEN failure_count + 1 >= 3 THEN 'open' ELSE state END,
            opened_at = CASE WHEN failure_count + 1 >= 3 THEN excluded.last_failure_at ELSE opened_at END,
            updated_at = excluded.updated_at
        SQL
      end

      # Record circuit breaker success
      def record_success(model)
        connection.execute(<<~SQL, [model, Time.now.to_i])
          INSERT INTO circuit_breakers (model, failure_count, state, updated_at)
          VALUES (?, 0, 'closed', ?)
          ON CONFLICT(model) DO UPDATE SET
            failure_count = 0,
            state = 'closed',
            opened_at = NULL,
            updated_at = excluded.updated_at
        SQL
      end

      # ===== QUALITY =====

      # Record quality check
      def record_quality(file_path:, check_type:, passed:, score: nil, details: nil)
        connection.execute(
          "INSERT INTO quality_checks (file_path, check_type, passed, score, details, created_at) VALUES (?, ?, ?, ?, ?, ?)",
          [file_path, check_type, passed ? 1 : 0, score, details.is_a?(Hash) ? details.to_json : details, Time.now.to_i]
        )
      end

      # Get quality history for file
      def quality_history(file_path, check_type: nil, limit: 10)
        if check_type
          connection.execute(
            "SELECT * FROM quality_checks WHERE file_path = ? AND check_type = ? ORDER BY created_at DESC LIMIT ?",
            [file_path, check_type, limit]
          )
        else
          connection.execute(
            "SELECT * FROM quality_checks WHERE file_path = ? ORDER BY created_at DESC LIMIT ?",
            [file_path, limit]
          )
        end
      end
    end
  end
end
