# frozen_string_literal: true

require "minitest/autorun"
require "sqlite3"
require_relative "../lib/result"
require_relative "../lib/db"

class TestDB < Minitest::Test
  def setup
    # Use in-memory database for tests
    @original_db = MASTER::DB.instance_variable_get(:@connection)
    @db = SQLite3::Database.new(":memory:")
    @db.results_as_hash = true
    MASTER::DB.instance_variable_set(:@connection, @db)
    MASTER::DB.initialize_schema
  end

  def teardown
    MASTER::DB.instance_variable_set(:@connection, @original_db)
  end

  def test_initialize_schema_creates_tables
    tables = @db.execute("SELECT name FROM sqlite_master WHERE type='table'")
    table_names = tables.map { |t| t["name"] }
    
    assert_includes table_names, "principles"
    assert_includes table_names, "personas"
    assert_includes table_names, "config"
    assert_includes table_names, "costs"
    assert_includes table_names, "circuits"
  end

  def test_get_persona_returns_nil_when_not_found
    result = MASTER::DB.get_persona("nonexistent")
    assert_nil result
  end

  def test_get_persona_returns_data_when_found
    @db.execute("INSERT INTO personas (name, role, instructions, weight) VALUES (?, ?, ?, ?)",
                ["test", "tester", "test instructions", 5])
    
    result = MASTER::DB.get_persona("test")
    refute_nil result
    assert_equal "test", result[:name]
    assert_equal "test instructions", result[:instructions]
  end

  def test_get_principles_filters_by_protection_level
    @db.execute("INSERT INTO principles (name, text, protection_level) VALUES (?, ?, ?)",
                ["p1", "text1", 0])
    @db.execute("INSERT INTO principles (name, text, protection_level) VALUES (?, ?, ?)",
                ["p2", "text2", 5])
    
    results = MASTER::DB.get_principles(protection_level: 3)
    assert_equal 1, results.length
    assert_equal "p2", results[0][:name]
  end

  def test_set_and_get_config
    MASTER::DB.set_config("test_key", "test_value")
    result = MASTER::DB.get_config("test_key")
    assert_equal "test_value", result
  end

  def test_set_config_updates_existing_key
    MASTER::DB.set_config("key", "value1")
    MASTER::DB.set_config("key", "value2")
    result = MASTER::DB.get_config("key")
    assert_equal "value2", result
  end
end
