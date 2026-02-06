# frozen_string_literal: true

module MASTER
  class Budget
    RATES = {
      "deepseek-r1" => { input: 0.55, output: 2.19 },
      "deepseek-v3" => { input: 0.27, output: 1.10 },
      "claude-sonnet-4" => { input: 3.00, output: 15.00 },
      "gpt-4.1-mini" => { input: 0.15, output: 0.60 },
      "gpt-4.1-nano" => { input: 0.04, output: 0.16 }
    }.freeze

    attr_reader :limit

    def initialize(db, limit: 10.0)
      @db = db
      @limit = limit
    end

    def spent
      result = @db.connection.get_first_value("SELECT SUM(cost) FROM costs")
      result ? result.to_f : 0.0
    end

    def remaining
      limit - spent
    end

    def record(model:, tokens_in:, tokens_out:)
      rate = RATES[model] || { input: 0.0, output: 0.0 }
      cost = (tokens_in / 1_000_000.0 * rate[:input]) + (tokens_out / 1_000_000.0 * rate[:output])
      
      @db.connection.execute(
        "INSERT INTO costs (model, tokens_in, tokens_out, cost) VALUES (?, ?, ?, ?)",
        [model, tokens_in, tokens_out, cost]
      )
      
      cost
    end

    def affordable_tier
      return :strong if remaining > 5
      return :fast if remaining > 1
      :cheap
    end
  end
end
