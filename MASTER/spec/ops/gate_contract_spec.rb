# frozen_string_literal: true

require "minitest/autorun"

class GateContractSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  GATE = File.join(ROOT, "bin", "gate")

  def test_gate_runs_master_cli
    source = File.read(GATE)
    assert_includes source, '"bin/cli"'
    assert_includes source, "stdin_data"
  end

  def test_gate_is_expected_to_keep_repo_clean
    source = File.read(GATE)
    assert_includes source, "assert_clean(\"MASTER\")"
    assert_includes source, "assert_clean(\"DEPLOY\", \"MASTER\")"
  end

  def test_gate_forces_safe_env
    source = File.read(GATE)
    assert_includes source, "SAFE_ENV"
    assert_includes source, '"MASTER_SAFE_MODE" => "1"'
    assert_includes source, '"MASTER_AUTOFIX" => "0"'
    assert_includes source, '"MASTER_WATCH" => "0"'
    assert_includes source, '"MASTER_WATCHER" => "0"'
    assert_includes source, '"MASTER_HEARTBEAT" => "0"'
  end
end
