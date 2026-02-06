# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require_relative '../lib/db'

class TestDB < Minitest::Test
  def setup
    # Use test database
    @original_db_path = MASTER::DB::DB_PATH
    test_db = "/tmp/test_master_#{$$}.db"
    FileUtils.rm_f(test_db)
    MASTER::DB.const_set(:DB_PATH, test_db)
    @connection = MASTER::DB.connection
    MASTER::DB.initialize_schema
  end
  
  def teardown
    @connection.close if @connection
    FileUtils.rm_f(MASTER::DB::DB_PATH)
    MASTER::DB.const_set(:DB_PATH, @original_db_path)
    MASTER::DB.instance_variable_set(:@connection, nil)
  end
  
  def test_schema_initialization
    tables = @connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
    table_names = tables.map { |row| row["name"] }
    
    assert_includes table_names, "principles"
    assert_includes table_names, "personas"
    assert_includes table_names, "config"
    assert_includes table_names, "costs"
    assert_includes table_names, "circuits"
  end
  
  def test_config_operations
    MASTER::DB.set_config("test_key", "test_value")
    value = MASTER::DB.get_config("test_key")
    assert_equal "test_value", value
  end
  
  def test_track_cost
    MASTER::DB.track_cost(
      model: "test-model",
      tokens_in: 100,
      tokens_out: 200,
      cost: 0.01
    )
    
    costs = @connection.execute("SELECT * FROM costs WHERE model = ?", ["test-model"])
    assert_equal 1, costs.length
    assert_equal 100, costs.first["tokens_in"]
    assert_equal 200, costs.first["tokens_out"]
  end
  
  def test_circuit_breaker
    # Initially no state
    assert_nil MASTER::DB.get_circuit_state("test-model")
    
    # Record failures
    3.times { MASTER::DB.record_circuit_failure("test-model") }
    
    # Should be open after 3 failures
    assert_equal 'open', MASTER::DB.get_circuit_state("test-model")
    
    # Reset circuit
    MASTER::DB.reset_circuit("test-model")
    assert_nil MASTER::DB.get_circuit_state("test-model")
  end
end
