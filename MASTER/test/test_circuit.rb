# frozen_string_literal: true

require "minitest/autorun"
require "sqlite3"
require_relative "../lib/result"
require_relative "../lib/circuit"

class TestCircuit < Minitest::Test
  def setup
    @db_conn = SQLite3::Database.new(":memory:")
    @db_conn.results_as_hash = true
    @db_conn.execute_batch <<~SQL
      CREATE TABLE circuits (
        model TEXT PRIMARY KEY,
        failures INTEGER DEFAULT 0,
        last_failure TEXT,
        state TEXT DEFAULT 'closed'
      );
    SQL
    
    # Mock DB module
    @db_mock = Object.new
    def @db_mock.connection; @conn; end
    @db_mock.instance_variable_set(:@conn, @db_conn)
    
    @circuit = MASTER::Circuit.new(@db_mock)
  end

  def test_available_returns_true_when_no_circuit
    assert @circuit.available?("model-1")
  end

  def test_record_failure_increments_failures
    @circuit.record_failure("model-1")
    row = @db_conn.get_first_row("SELECT failures FROM circuits WHERE model = ?", "model-1")
    assert_equal 1, row["failures"]
  end

  def test_opens_circuit_after_threshold_failures
    3.times { @circuit.record_failure("model-1") }
    row = @db_conn.get_first_row("SELECT state FROM circuits WHERE model = ?", "model-1")
    assert_equal "open", row["state"]
  end

  def test_available_returns_false_when_circuit_open
    3.times { @circuit.record_failure("model-1") }
    refute @circuit.available?("model-1")
  end

  def test_record_success_resets_circuit
    @circuit.record_failure("model-1")
    @circuit.record_success("model-1")
    assert @circuit.available?("model-1")
    
    row = @db_conn.get_first_row("SELECT * FROM circuits WHERE model = ?", "model-1")
    assert_nil row
  end

  def test_reset_deletes_circuit_row
    @circuit.record_failure("model-1")
    @circuit.reset("model-1")
    
    row = @db_conn.get_first_row("SELECT * FROM circuits WHERE model = ?", "model-1")
    assert_nil row
  end
end
