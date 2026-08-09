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

  # The assertions above are string matches, and a string match is what let this
  # break: bin/gate listed MASTER_AUTOFIX=0 and its comment claimed /scan was
  # read-only under it, while MechanicalAutofix read MASTER_SCAN_AUTOFIX and
  # consulted MASTER_AUTOFIX nowhere. Every key was present and the tree was
  # still written to. So this one asks the consumer instead of the spelling.
  def test_gate_safe_env_actually_disables_scan_autofix
    require_relative "../../lib/review/scan/mechanical_autofix"

    env = safe_env_from_source
    assert_includes env.keys, "MASTER_SCAN_AUTOFIX",
                    "bin/gate's SAFE_ENV must name the variable /scan's autofix pass actually reads"
    refute Master::Review::Scan::MechanicalAutofix.enabled?(env: env),
           "bin/gate's SAFE_ENV does not disable MechanicalAutofix, so the full chain's first " \
           "/scan writes to the tree before /fix runs -- which is what the COMMANDS comment " \
           "promises it does not do"
  end

  # Parsed out of the source rather than required, because bin/gate runs the
  # whole chain at load time; there is nothing to require without running it.
  def safe_env_from_source
    body = File.read(GATE)[/SAFE_ENV = \{(.*?)\}\.freeze/m, 1].to_s
    body.scan(/"([A-Z_]+)"\s*=>\s*"([^"]*)"/).to_h
  end
end
