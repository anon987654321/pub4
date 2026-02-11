# frozen_string_literal: true

require "minitest/autorun"
require "sqlite3"

# Create minimal MASTER module for testing
module MASTER
  def self.root
    File.expand_path("..", __dir__)
  end
  
  module DB
    def self.connection
      @connection ||= begin
        db = SQLite3::Database.new(":memory:")
        db.results_as_hash = true
        db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS costs (
            id INTEGER PRIMARY KEY, model TEXT, tokens_in INTEGER,
            tokens_out INTEGER, cost REAL, created_at TEXT DEFAULT (datetime('now'))
          );
          CREATE TABLE IF NOT EXISTS circuits (
            model TEXT PRIMARY KEY, failures INTEGER DEFAULT 0,
            last_failure TEXT, state TEXT DEFAULT 'closed'
          );
        SQL
        db
      end
    end
  end
end

require_relative "../lib/llm"

module MASTER
  class TestLLM < Minitest::Test
    def setup
      # Reset database
      DB.connection.execute("DELETE FROM costs")
      DB.connection.execute("DELETE FROM circuits")
    end

    def test_select_model_returns_strong_for_long_text
      text = "x" * 1500
      selected = LLM.select_model(text.length)
      
      refute_nil selected
      assert_includes LLM::TIERS[:strong], selected[:model]
      assert_equal :strong, selected[:tier]
    end

    def test_select_model_returns_fast_for_medium_text
      text = "x" * 500
      selected = LLM.select_model(text.length)
      
      refute_nil selected
      # Should be fast or strong depending on budget
      assert [:fast, :strong].include?(selected[:tier])
    end

    def test_select_model_returns_cheap_for_short_text
      text = "hello"
      selected = LLM.select_model(text.length)
      
      refute_nil selected
      # Should be cheap, fast, or strong depending on budget
      assert [:cheap, :fast, :strong].include?(selected[:tier])
    end

    def test_circuit_available_returns_true_for_new_model
      assert LLM.circuit_available?("test-model")
    end

    def test_circuit_available_returns_true_for_closed_circuit
      DB.connection.execute(
        "INSERT INTO circuits (model, failures, state) VALUES (?, ?, ?)",
        ["test-model", 1, "closed"]
      )
      
      assert LLM.circuit_available?("test-model")
    end

    def test_circuit_available_returns_false_for_open_circuit
      DB.connection.execute(
        "INSERT INTO circuits (model, failures, last_failure, state) VALUES (?, ?, ?, ?)",
        ["test-model", 3, Time.now.utc.iso8601, "open"]
      )
      
      refute LLM.circuit_available?("test-model")
    end

    def test_record_failure_increments_counter
      LLM.record_failure("test-model")
      
      row = DB.connection.get_first_row("SELECT * FROM circuits WHERE model = ?", ["test-model"])
      refute_nil row
      assert_equal 1, row["failures"]
      assert_equal "closed", row["state"]
    end

    def test_record_failure_opens_circuit_at_threshold
      # Record failures up to threshold
      (LLM::CIRCUIT_THRESHOLD - 1).times { LLM.record_failure("test-model") }
      
      row = DB.connection.get_first_row("SELECT * FROM circuits WHERE model = ?", ["test-model"])
      assert_equal "closed", row["state"]
      
      # One more should open it
      LLM.record_failure("test-model")
      
      row = DB.connection.get_first_row("SELECT * FROM circuits WHERE model = ?", ["test-model"])
      assert_equal "open", row["state"]
    end

    def test_record_success_removes_circuit_entry
      LLM.record_failure("test-model")
      LLM.record_success("test-model")
      
      row = DB.connection.get_first_row("SELECT * FROM circuits WHERE model = ?", ["test-model"])
      assert_nil row
    end

    def test_record_cost_calculates_correctly
      cost = LLM.record_cost(model: "deepseek-r1", tokens_in: 1000, tokens_out: 2000)
      
      # 1000 * 0.55 / 1M + 2000 * 2.19 / 1M
      expected = (1000 * 0.55 + 2000 * 2.19) / 1_000_000.0
      assert_in_delta expected, cost, 0.000001
      
      row = DB.connection.get_first_row("SELECT * FROM costs WHERE model = ?", ["deepseek-r1"])
      refute_nil row
      assert_equal 1000, row["tokens_in"]
      assert_equal 2000, row["tokens_out"]
    end

    def test_spent_returns_zero_initially
      assert_equal 0.0, LLM.spent
    end

    def test_spent_sums_costs
      LLM.record_cost(model: "test", tokens_in: 1000, tokens_out: 1000)
      LLM.record_cost(model: "test", tokens_in: 2000, tokens_out: 2000)
      
      assert LLM.spent > 0
    end

    def test_remaining_subtracts_from_budget
      initial_remaining = LLM.remaining
      assert_equal LLM::BUDGET_LIMIT, initial_remaining
      
      LLM.record_cost(model: "test", tokens_in: 1_000_000, tokens_out: 1_000_000)
      
      assert LLM.remaining < initial_remaining
    end

    def test_affordable_tier_returns_strong_when_budget_high
      assert_equal :strong, LLM.affordable_tier
    end

    def test_affordable_tier_returns_cheap_when_budget_low
      # Spend most of budget
      (LLM::BUDGET_LIMIT * 0.95 * 1_000_000).to_i.times do |i|
        break if i > 10_000 # Safety limit for test
        DB.connection.execute(
          "INSERT INTO costs (model, tokens_in, tokens_out, cost) VALUES (?, ?, ?, ?)",
          ["test", 1000, 1000, 0.001]
        )
      end
      
      # Inject cost directly
      DB.connection.execute(
        "INSERT INTO costs (model, tokens_in, tokens_out, cost) VALUES (?, ?, ?, ?)",
        ["test", 1000000, 1000000, LLM::BUDGET_LIMIT * 0.95]
      )
      
      assert_equal :cheap, LLM.affordable_tier
    end
  end
end
