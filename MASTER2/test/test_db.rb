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
    assert_includes table_names, "models"
  end

  def test_axioms_seeded
    axioms = MASTER::DB.axioms
    assert axioms.length > 0, "Axioms should be seeded"
    
    # Check specific axioms
    dry = axioms.find { |a| a["id"] == "DRY" }
    assert dry, "DRY axiom should exist"
    assert_equal "engineering", dry["category"]
    assert_equal "PROTECTED", dry["protection"]
  end

  def test_council_seeded
    members = MASTER::DB.council
    assert_equal 12, members.length, "Should have 12 council members"
    
    # Check veto members
    veto_members = MASTER::DB.council(veto_only: true)
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

  def test_log_cost
    MASTER::DB.log_cost(model: "test-model", tokens_in: 100, tokens_out: 50, cost: 0.05)
    total = MASTER::DB.total_cost
    assert_equal 0.05, total
  end

  def test_circuit_breaker
    # Record failure
    MASTER::DB.trip!("test-model")
    circuit = MASTER::DB.circuit("test-model")
    assert_equal 1, circuit["failures"]
    
    # Record success (should reset)
    MASTER::DB.reset!("test-model")
    circuit = MASTER::DB.circuit("test-model")
    assert_equal 0, circuit["failures"]
  end

  def test_config_storage
    MASTER::DB.connection.execute("INSERT INTO config (key, value) VALUES (?, ?)", ["test_key", "test_value"])
    value = MASTER::DB.config("test_key")
    assert_equal "test_value", value
  end

  def test_openbsd_patterns_table_created
    tables = MASTER::DB.connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
    table_names = tables.map { |row| row["name"] }
    assert_includes table_names, "openbsd_patterns"
  end

  def test_openbsd_patterns_seeded
    patterns = MASTER::DB.openbsd_patterns
    assert patterns.length > 0, "OpenBSD patterns should be seeded"
    
    # Check forbidden commands exist
    forbidden = patterns.select { |p| p["category"] == "forbidden" }
    assert forbidden.length > 0, "Should have forbidden commands"
    
    systemctl = forbidden.find { |p| p["command"] == "systemctl" }
    assert systemctl, "Should have systemctl forbidden command"
    assert_equal "rcctl", systemctl["replacement"]
  end

  def test_openbsd_patterns_service_management
    patterns = MASTER::DB.openbsd_patterns(category: "service_management")
    assert patterns.length > 0, "Should have service management patterns"
    
    enable = patterns.find { |p| p["key"] == "enable" }
    assert enable, "Should have enable pattern"
    assert_equal "rcctl enable ${service}", enable["value"]
  end

  def test_openbsd_patterns_config_paths
    patterns = MASTER::DB.openbsd_patterns(category: "config_paths")
    assert patterns.length > 0, "Should have config paths"
    
    pf = patterns.find { |p| p["key"] == "pf" }
    assert pf, "Should have pf config path"
    assert_equal "/etc/pf.conf", pf["value"]
  end

  def test_openbsd_patterns_package_management
    patterns = MASTER::DB.openbsd_patterns(category: "package_management")
    assert patterns.length > 0, "Should have package management patterns"
    
    install = patterns.find { |p| p["key"] == "install" }
    assert install, "Should have install pattern"
    assert_equal "pkg_add ${package}", install["value"]
  end

  def test_openbsd_patterns_security
    patterns = MASTER::DB.openbsd_patterns(category: "security")
    assert patterns.length > 0, "Should have security patterns"
    
    pledge = patterns.find { |p| p["key"] == "pledge" }
    assert pledge, "Should have pledge security pattern"
    assert_match /pledge\(2\)/, pledge["value"]
  end
end
