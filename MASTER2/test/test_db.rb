# frozen_string_literal: true

require_relative "test_helper"

class TestDB < Minitest::Test
  def setup
    setup_db
  end

  def test_schema_creation
    tables = MASTER::DB.connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
    table_names = tables.map { |row| row["name"] }
    
    assert_includes table_names, "axioms"
    assert_includes table_names, "council"
    assert_includes table_names, "config"
    assert_includes table_names, "costs"
    assert_includes table_names, "circuits"
  end

  def test_axioms_seeded
    axioms = MASTER::DB.axioms
    assert axioms.length > 0, "Axioms should be seeded"
    
    dry = axioms.find { |a| a["id"] == "DRY" }
    assert dry, "DRY axiom should exist"
    assert_equal "engineering", dry["category"]
    assert_equal "PROTECTED", dry["protection"]
  end

  def test_council_seeded
    members = MASTER::DB.council
    assert members.length > 0, "Should have council members"
    
    veto_members = MASTER::DB.council(veto_only: true)
    assert veto_members.length > 0, "Should have veto members"
  end

  def test_log_cost
    MASTER::DB.log_cost(model: "test-model", tokens_in: 100, tokens_out: 50, cost: 0.05)
    total = MASTER::DB.total_cost
    assert_equal 0.05, total
  end

  def test_circuit_breaker
    MASTER::DB.trip!("test-model")
    circuit = MASTER::DB.circuit("test-model")
    assert_equal 1, circuit["failures"]
    
    MASTER::DB.reset!("test-model")
    circuit = MASTER::DB.circuit("test-model")
    assert_equal 0, circuit["failures"]
  end

  def test_config_storage
    MASTER::DB.set_config("test_key", "test_value")
    value = MASTER::DB.config("test_key")
    assert_equal "test_value", value
  end
end
