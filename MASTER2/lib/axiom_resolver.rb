# frozen_string_literal: true

require "yaml"
require "json"
require "time"

module MASTER
  # Resolves conflicts between axioms using the precedence defined
  # in data/axiom_resolution.yml. Defers losing violations to JSONL
  # so they are tracked rather than silently dropped.
  module AxiomResolver
    module_function

    def config
      @config ||= load_config
    end

    def reload!
      @config = load_config
    end

    def precedence
      config.fetch("absolute_precedence", [])
    end

    # Resolve a conflict between two axiom IDs.
    # Returns the winning axiom ID string.
    def resolve(axiom_a, axiom_b)
      a = axiom_a.to_s
      b = axiom_b.to_s
      return Result.ok(winner: a) if a == b

      order = precedence
      idx_a = order.index(a)
      idx_b = order.index(b)

      # Neither in precedence list — no resolution possible
      return Result.err("No precedence defined for #{a} vs #{b}") if idx_a.nil? && idx_b.nil?

      # Lower index = higher precedence
      winner = if idx_a.nil?
                 b
               elsif idx_b.nil?
                 a
               elsif idx_a <= idx_b
                 a
               else
                 b
               end

      Result.ok(winner: winner, loser: winner == a ? b : a)
    end

    # Append a deferred-debt entry to the JSONL log
    def defer(axiom_id:, file:, line:, reason:, blocking_axiom:)
      entry = {
        axiom_id: axiom_id.to_s,
        file: file.to_s,
        line: line.to_i,
        reason_deferred: reason.to_s,
        blocking_axiom: blocking_axiom.to_s,
        timestamp: Time.now.utc.iso8601,
      }
      path = File.join(MASTER.root, "data", "deferred_debt.jsonl")
      File.open(path, "a") { |f| f.puts(JSON.generate(entry)) }
      Result.ok(entry)
    rescue IOError, SystemCallError => e
      Result.err("Failed to write deferred debt: #{e.message}")
    end

    # Read all deferred debt entries
    def deferred_debts
      path = File.join(MASTER.root, "data", "deferred_debt.jsonl")
      return Result.ok([]) unless File.exist?(path)

      entries = File.readlines(path).filter_map do |line|
        JSON.parse(line.strip, symbolize_names: true) unless line.strip.empty?
      end
      Result.ok(entries)
    rescue JSON::ParserError, IOError => e
      Result.err("Failed to read deferred debt: #{e.message}")
    end

    def load_config
      path = File.join(MASTER.root, "data", "axiom_resolution.yml")
      return {} unless File.exist?(path)

      YAML.safe_load_file(path) || {}
    end
  end
end
