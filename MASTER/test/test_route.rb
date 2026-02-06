# frozen_string_literal: true

require "minitest/autorun"
require "sqlite3"
require_relative "../lib/result"
require_relative "../lib/db"
require_relative "../lib/circuit"
require_relative "../lib/budget"
require_relative "../lib/stages/route"

class TestRoute < Minitest::Test
  def setup
    # Setup in-memory DB
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
      CREATE TABLE circuits (
        model TEXT PRIMARY KEY,
        failures INTEGER DEFAULT 0,
        last_failure TEXT,
        state TEXT DEFAULT 'closed'
      );
    SQL
    
    # Mock DB module
    @original_db = MASTER::DB.instance_variable_get(:@connection)
    MASTER::DB.instance_variable_set(:@connection, @db_conn)
    
    @route = MASTER::Stages::Route.new
  end

  def teardown
    MASTER::DB.instance_variable_set(:@connection, @original_db)
  end

  def test_selects_model_based_on_complexity
    input = { text: "simple" }
    result = @route.call(input)
    
    assert result.ok?
    assert result.value[:model]
    assert result.value[:tier]
  end

  def test_short_text_gets_cheap_tier
    input = { text: "hi" }
    result = @route.call(input)
    
    assert result.ok?
    # Should get cheap tier due to short text and high budget
    assert_includes [:cheap, :fast], result.value[:tier]
  end

  def test_long_text_gets_higher_tier
    input = { text: "complex " * 100 }
    result = @route.call(input)
    
    assert result.ok?
    # Should get strong tier due to complexity
    assert_includes [:strong, :fast, :cheap], result.value[:tier]
  end

  def test_respects_budget_constraints
    # Spend most of budget
    @db_conn.execute("INSERT INTO costs (model, cost) VALUES (?, ?)", ["model", 9.5])
    
    route = MASTER::Stages::Route.new
    input = { text: "test" }
    result = route.call(input)
    
    assert result.ok?
    # Should select cheap tier due to low budget
    assert_equal :cheap, result.value[:tier]
  end

  def test_returns_error_when_all_models_unavailable
    # Mark all models as unavailable
    MASTER::Stages::Route::TIERS.values.flatten.each do |model|
      @db_conn.execute("INSERT INTO circuits (model, failures, state) VALUES (?, ?, ?)", [model, 3, "open"])
    end
    
    route = MASTER::Stages::Route.new
    input = { text: "test" }
    result = route.call(input)
    
    assert result.err?
    assert_match(/unavailable/, result.error)
  end
end
