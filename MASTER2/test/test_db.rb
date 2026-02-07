# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestDB < Minitest::Test
  def setup
    MASTER::DB.setup(path: ":memory:")
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
    members = MASTER::DB.council_members
    assert_equal 12, members.length, "Should have 12 council members"
    
    veto_members = MASTER::DB.council_members(veto_only: true)
    assert_equal 3, veto_members.length, "Should have 3 veto members"
    
    security = members.find { |m| m["slug"] == "security" }
    assert security, "Security persona should exist"
    assert_equal 1, security["veto"]
    assert_equal 0.30, security["weight"]
  end

  def test_axioms_by_category
    eng_axioms = MASTER::DB.axioms(category: "engineering")
    assert eng_axioms.all? { |a| a["category"] == "engineering" }
  end

  def test_axioms_by_protection
    protected_axioms = MASTER::DB.axioms(protection: "PROTECTED")
    assert protected_axioms.all? { |a| a["protection"] == "PROTECTED" }
    
    absolute_axioms = MASTER::DB.axioms(protection: "ABSOLUTE")
    assert absolute_axioms.all? { |a| a["protection"] == "ABSOLUTE" }
  end

  def test_track_cost
    MASTER::DB.track_cost(model: "test-model", tokens_in: 100, tokens_out: 50, cost: 0.05)
    total = MASTER::DB.total_cost
    assert_equal 0.05, total
  end

  def test_circuit_breaker
    MASTER::DB.circuit_failure!("test-model")
    circuit = MASTER::DB.circuit("test-model")
    assert_equal 1, circuit["failures"]
    
    MASTER::DB.circuit_success!("test-model")
    circuit = MASTER::DB.circuit("test-model")
    assert_equal 0, circuit["failures"]
  end

  def test_config_storage
    MASTER::DB.connection.execute(
      "INSERT INTO config (key, value) VALUES (?, ?)",
      ["test_key", "test_value"]
    )
    value = MASTER::DB.config_value("test_key")
    assert_equal "test_value", value
  end
end
