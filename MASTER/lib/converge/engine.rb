# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "set"
require "sqlite3"

module Converge
  class Engine
    MAX_CYCLES = 16

    attr_reader :rules, :event_stream, :db

    def initialize(canon_path)
      @rules = Canon.load(canon_path)
      @event_stream = EventStream.new
      @context = {
        violations: [],
        events: @event_stream,
        execution_depth: 0,
        tracking_hashes: Set.new
      }
      init_storage
    end

    def run(initial_context = {})
      @context.merge!(initial_context)
      cycles = 0
      capped = false

      loop do
        changed = apply_rules_once
        cycles += 1
        @context[:execution_depth] = cycles
        capped = changed && cycles >= max_iterations
        break unless changed && cycles < max_iterations
      end

      emit_iteration_cap(cycles) if capped
      @event_stream.emit(:convergence_complete, cycles: cycles)
      @context
    end

    def subscribe(&block)
      @event_stream.subscribe(&block)
    end

    private

    def max_iterations
      configured = @context[:max_iterations] || @context["max_iterations"]
      configured.to_i.positive? ? configured.to_i : MAX_CYCLES
    end

    def emit_iteration_cap(cycles)
      @event_stream.emit(:"convergence:max_iterations", cycles: cycles, max_iterations: max_iterations)
    end

    def apply_rules_once
      changed = false

      @rules.each do |rule|
        @db.transaction do
          before = JSON.generate(serializable_context)
          apply_rule(rule)
          after = JSON.generate(serializable_context)
          next if after == before

          log_state_delta(rule.id, after)
          changed = true
        end
      end

      changed
    end

    def apply_rule(rule)
      @context = rule.apply(@context.dup)
      track_state_hashes(rule.id)
    rescue StandardError => error
      violation = { rule: rule.id, error: error.message }
      @context[:violations] << violation
      @event_stream.emit(:violation, violation)
    end

    def init_storage
      db_path = File.expand_path("~/.master/state.db")
      FileUtils.mkdir_p(File.dirname(db_path))
      @db = SQLite3::Database.new(db_path, timeout: 5_000)
      @db.execute_batch <<~SQL
        CREATE TABLE IF NOT EXISTS runtime_ledger (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          rule_id TEXT,
          delta_blob TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        CREATE TABLE IF NOT EXISTS feedback_loops (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          signature TEXT UNIQUE,
          hit_count INTEGER DEFAULT 1,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
      SQL
    end

    def track_state_hashes(rule_id)
      current_hash = Digest::SHA256.hexdigest(JSON.generate(serializable_context))
      signature = "#{rule_id}:#{current_hash}"

      if @context[:tracking_hashes].include?(signature)
        sql = <<~SQL
          INSERT INTO feedback_loops (signature) VALUES (?)
          ON CONFLICT(signature) DO UPDATE SET
            hit_count = hit_count + 1, updated_at = CURRENT_TIMESTAMP
        SQL
        @db.execute(sql, [signature])
        raise "oscillation_detected: rule #{rule_id} generated a cyclical state mutation"
      end

      @context[:tracking_hashes] << signature
    end

    def log_state_delta(rule_id, current_dump)
      payload = {
        rule: rule_id,
        sha256: Digest::SHA256.hexdigest(current_dump),
        violations_count: @context[:violations]&.size || 0,
        timestamp: Time.now.to_i
      }
      @db.execute("INSERT INTO runtime_ledger (rule_id, delta_blob) VALUES (?, ?)", [rule_id, JSON.generate(payload)])
      @event_stream.emit(:rule_applied, payload)
    end

    def serializable_context
      @context.reject { |key, _| %i[events tracking_hashes].include?(key) }
    end
  end
end
