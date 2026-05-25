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

  def test_gate_safe_env_patch_is_still_backlog_if_missing
    source = File.read(GATE)
    refute_includes source, "MASTER_SAFE_MODE"
  end
end
