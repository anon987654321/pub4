# frozen_string_literal: true

module MASTER
  module DB
    extend self

    # --- Costs ---

    # Log LLM API cost
    # @param model [String] Model identifier
    # @param tokens_in [Integer] Input tokens
    # @param tokens_out [Integer] Output tokens
    # @param cost [Float] Cost in dollars
    # @return [Hash] Created cost record
    def log_cost(model:, tokens_in:, tokens_out:, cost:)
      record = {
        model: model,
        tokens_in: tokens_in,
        tokens_out: tokens_out,
        cost: cost,
        created_at: Time.now.utc.iso8601,
      }
      append("costs", record)
    end

    # Get total cost across all logged API calls
    # @return [Float] Total cost in dollars
    def total_cost
      costs = read_collection("costs")
      costs.sum { |c| c[:cost] || 0 }
    end

    # Get recent cost records
    # @param limit [Integer] Number of records to return
    # @return [Array<Hash>] Recent cost records
    def recent_costs(limit: 10)
      read_collection("costs").last(limit)
    end

    # --- Circuits ---
    def circuit(model)
      circuits = read_collection("circuits")
      circuits.find { |c| c[:model] == model }
    end

    def trip!(model)
      circuits = read_collection("circuits")
      existing = circuits.find { |c| c[:model] == model }

      if existing
        existing[:state] = "open"
        existing[:failures] = (existing[:failures] || 0) + 1
        existing[:last_failure] = Time.now.utc.iso8601
        write_collection("circuits", circuits)
      else
        record = {
          model: model,
          state: "open",
          failures: 1,
          last_failure: Time.now.utc.iso8601,
        }
        append("circuits", record)
      end
    end

    def reset!(model)
      circuits = read_collection("circuits")
      existing = circuits.find { |c| c[:model] == model }

      return unless existing

      existing[:state] = "closed"
      existing[:failures] = 0
      write_collection("circuits", circuits)
    end

    def increment_failure!(model)
      circuits = read_collection("circuits")
      existing = circuits.find { |c| c[:model] == model }

      if existing
        existing[:failures] = (existing[:failures] || 0) + 1
        existing[:last_failure] = Time.now.utc.iso8601
        # Keep state as-is (don't open yet)
        write_collection("circuits", circuits)
      else
        record = {
          model: model,
          state: "closed",
          failures: 1,
          last_failure: Time.now.utc.iso8601,
        }
        append("circuits", record)
      end
    end

    # --- Sessions ---
    # WARNING: This DB.save_session is for learning feedback only.
    # For actual session storage, use Memory.save_session in session.rb
    def save_session(id:, data:)
      sessions = read_collection("sessions")
      existing = sessions.find { |s| s[:id] == id }
      now = Time.now.utc.iso8601

      if existing
        existing[:data] = data
        existing[:updated_at] = now
        write_collection("sessions", sessions)
      else
        record = { id: id, data: data, created_at: now, updated_at: now }
        append("sessions", record)
      end
    end

    def load_session(id)
      sessions = read_collection("sessions")
      session = sessions.find { |s| s[:id] == id }
      session&.dig(:data)
    end

    # --- Patterns ---
    def patterns(category = nil)
      all = read_collection("patterns")
      return all unless category

      all.select { |p| p[:category] == category }
    end

    def add_pattern(category:, pattern:, replacement: nil, description: nil)
      record = {
        category: category,
        pattern: pattern,
        replacement: replacement,
        description: description,
      }
      append("patterns", record.compact)
    end

    # --- Models ---
    def models
      read_collection("models")
    end

    def add_model(name:, tier:, rate_in:, rate_out:)
      record = { name: name, tier: tier, rate_in: rate_in, rate_out: rate_out }
      append("models", record)
    end
  end
end
