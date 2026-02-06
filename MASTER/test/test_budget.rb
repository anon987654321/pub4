# frozen_string_literal: true

require "minitest/autorun"
require "sqlite3"
require_relative "../lib/result"
require_relative "../lib/budget"

class TestBudget < Minitest::Test
  def setup
    @db_conn = SQLite3::Database.new(":memory:")
    @db_conn.results_as_hash = true
    @db_conn.execute_batch <<~SQL
      CREATE TABLE costs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        model TEXT NOT NULL,
        tokens_in INTEGER DEFAULT 0,
        tokens_out INTEGER DEFAULT 0,
        cost REAL DEFAULT 0.0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    SQL
    
    # Mock DB module
    @db_mock = Object.new
    def @db_mock.connection; @conn; end
    @db_mock.instance_variable_set(:@conn, @db_conn)
    
    @budget = MASTER::Budget.new(@db_mock, limit: 10.0)
  end

  def test_spent_returns_zero_when_no_costs
    assert_equal 0.0, @budget.spent
  end

  def test_spent_returns_sum_of_costs
    @db_conn.execute("INSERT INTO costs (model, cost) VALUES (?, ?)", ["model-1", 2.5])
    @db_conn.execute("INSERT INTO costs (model, cost) VALUES (?, ?)", ["model-2", 3.5])
    assert_equal 6.0, @budget.spent
  end

  def test_remaining_calculates_correctly
    @db_conn.execute("INSERT INTO costs (model, cost) VALUES (?, ?)", ["model-1", 3.0])
    assert_equal 7.0, @budget.remaining
  end

  def test_record_calculates_and_stores_cost
    cost = @budget.record(model: "deepseek-r1", tokens_in: 1_000_000, tokens_out: 1_000_000)
    
    # 1M in @ 0.55 + 1M out @ 2.19 = 2.74
    assert_in_delta 2.74, cost, 0.01
    
    row = @db_conn.get_first_row("SELECT * FROM costs WHERE model = ?", "deepseek-r1")
    assert_equal 1_000_000, row["tokens_in"]
    assert_equal 1_000_000, row["tokens_out"]
    assert_in_delta 2.74, row["cost"], 0.01
  end

  def test_affordable_tier_returns_strong_when_budget_high
    budget = MASTER::Budget.new(@db_mock, limit: 10.0)
    assert_equal :strong, budget.affordable_tier
  end

  def test_affordable_tier_returns_fast_when_budget_medium
    @db_conn.execute("INSERT INTO costs (model, cost) VALUES (?, ?)", ["model-1", 6.0])
    budget = MASTER::Budget.new(@db_mock, limit: 10.0)
    assert_equal :fast, budget.affordable_tier
  end

  def test_affordable_tier_returns_cheap_when_budget_low
    @db_conn.execute("INSERT INTO costs (model, cost) VALUES (?, ?)", ["model-1", 9.5])
    budget = MASTER::Budget.new(@db_mock, limit: 10.0)
    assert_equal :cheap, budget.affordable_tier
  end
end
