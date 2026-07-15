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
    assert_includes source, 'assert_clean("MASTER")'
    assert_includes source, 'assert_clean("RAILS", "OPENBSD", "MASTER")'
  end

  # bin/gate's deploy pass must only reference directories that actually
  # exist — OPERATOR was folded into OPENBSD; a stale reference here means
  # the gate silently /scan|/fix a nonexistent path every run.
  def test_gate_deploy_paths_exist
    source = File.read(GATE)
    paths = source[/deploy: %w\[([^\]]+)\]/, 1].to_s.split
    assert_operator paths.size, :>=, 2, "expected COMMANDS[:deploy] path list to be non-trivial"
    paths.each do |relative|
      absolute = File.expand_path(relative, ROOT)
      assert File.directory?(absolute), "bin/gate references missing directory: #{relative}"
    end
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
