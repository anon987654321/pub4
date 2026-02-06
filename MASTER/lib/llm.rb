# frozen_string_literal: true

require "ruby_llm"

module MASTER
  module LLM
    TIERS = {
      strong: %w[deepseek-r1 claude-sonnet-4],
      fast:   %w[deepseek-v3 gpt-4.1-mini],
      cheap:  %w[gpt-4.1-nano]
    }.freeze

    TIER_ORDER = %i[strong fast cheap].freeze

    RATES = {
      "deepseek-r1"     => { input: 0.55, output: 2.19 },
      "claude-sonnet-4" => { input: 3.00, output: 15.00 },
      "deepseek-v3"     => { input: 0.27, output: 1.10 },
      "gpt-4.1-mini"    => { input: 0.40, output: 1.60 },
      "gpt-4.1-nano"    => { input: 0.10, output: 0.40 }
    }.freeze

    CIRCUIT_THRESHOLD = 3
    CIRCUIT_COOLDOWN  = 300
    BUDGET_LIMIT      = 10.0

    def self.configure
      RubyLLM.configure do |c|
        c.openai_api_key     = ENV["OPENAI_API_KEY"]
        c.anthropic_api_key  = ENV["ANTHROPIC_API_KEY"]
        c.deepseek_api_key   = ENV["DEEPSEEK_API_KEY"]
        c.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
      end
    end

    def self.chat(model:) = RubyLLM.chat(model: model)

    # --- Model selection (circuit + budget aware) ---

    def self.select_model(text_length)
      desired = text_length > 1000 ? :strong : text_length > 200 ? :fast : :cheap
      start = [TIER_ORDER.index(desired), TIER_ORDER.index(affordable_tier)].max

      TIER_ORDER[start..].each do |tier|
        TIERS[tier].each { |m| return { model: m, tier: tier } if circuit_available?(m) }
      end
      nil
    end

    # --- Circuit breaker ---

    def self.circuit_available?(model)
      row = DB.connection.get_first_row(
        "SELECT failures, last_failure, state FROM circuits WHERE model = ?", [model]
      )
      return true unless row
      return true if row["state"] == "closed"
      if Time.now.utc - Time.parse(row["last_failure"]) > CIRCUIT_COOLDOWN
        reset_circuit(model)
        true
      else
        false
      end
    end

    def self.record_failure(model)
      DB.connection.execute(<<~SQL, [model, Time.now.utc.iso8601])
        INSERT INTO circuits (model, failures, last_failure, state) VALUES (?, 1, ?, 'closed')
        ON CONFLICT(model) DO UPDATE SET
          failures = failures + 1, last_failure = excluded.last_failure,
          state = CASE WHEN failures + 1 >= #{CIRCUIT_THRESHOLD} THEN 'open' ELSE 'closed' END
      SQL
    end

    def self.record_success(model)
      DB.connection.execute("DELETE FROM circuits WHERE model = ?", [model])
    end

    def self.reset_circuit(model)
      DB.connection.execute("DELETE FROM circuits WHERE model = ?", [model])
    end

    # --- Budget ---

    def self.spent
      (DB.connection.get_first_value("SELECT COALESCE(SUM(cost), 0) FROM costs") || 0).to_f
    end

    def self.remaining = BUDGET_LIMIT - spent

    def self.record_cost(model:, tokens_in:, tokens_out:)
      rates = RATES.fetch(model, { input: 1.0, output: 1.0 })
      cost = (tokens_in * rates[:input] + tokens_out * rates[:output]) / 1_000_000.0
      DB.connection.execute(
        "INSERT INTO costs (model, tokens_in, tokens_out, cost) VALUES (?, ?, ?, ?)",
        [model, tokens_in, tokens_out, cost]
      )
      cost
    end

    def self.affordable_tier
      r = remaining
      r > 5.0 ? :strong : r > 1.0 ? :fast : :cheap
    end
  end
end
