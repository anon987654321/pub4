# frozen_string_literal: true

require_relative "test_helper"
require 'tmpdir'

class TestDB < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    MASTER::DB.setup(path: @tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir && Dir.exist?(@tmpdir)
  end

  def test_axioms_seeded
    axioms = MASTER::DB.axioms
    assert axioms.length > 0, "Axioms should be seeded"
    
    dry = axioms.find { |a| a["name"] == "DRY" || a[:name] == "DRY" }
    assert dry, "DRY axiom should exist"
  end

  def test_council_seeded
    members = MASTER::DB.council
    assert members.length > 0, "Should have council members"
  end

  def test_log_cost
    MASTER::DB.log_cost(model: "test-model", tokens_in: 100, tokens_out: 50, cost: 0.05)
    total = MASTER::DB.total_cost
    assert total >= 0.05, "Total cost should include logged cost"
  end

  def test_circuit_breaker
    MASTER::DB.trip!("test-model")
    circuit = MASTER::DB.circuit("test-model")
    assert circuit, "Circuit should exist after trip"
    assert_equal "open", circuit["state"] || circuit[:state]
    
    MASTER::DB.reset!("test-model")
    circuit = MASTER::DB.circuit("test-model")
    assert_equal "closed", circuit["state"] || circuit[:state]
  end

  def test_session_storage
    MASTER::DB.save_session(id: "test-session", data: { history: ["hello"] })
    loaded = MASTER::DB.load_session("test-session")
    assert loaded, "Session should be loadable"
  end
end
