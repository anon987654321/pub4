# frozen_string_literal: true

require "minitest/autorun"

class GateContractSpec < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  GATE = File.join(ROOT, "bin", "gate")

  # The command reaches bin/cli on stdin, and the gate does not wait forever for
  # an answer.
  #
  # This asserted the literal string "stdin_data", which was capture2e's keyword.
  # The gate moved to popen2e on 2026-08-12 for the timeout below — same
  # contract, same stdin, different spelling — and the spec failed on the
  # spelling. Asserting the two properties instead: something is written to the
  # child's stdin, and there is a wall clock on the wait. A stage that hangs is
  # the one failure INCONCLUSIVE cannot catch, because every pattern in that
  # list is something a stage says on its way out.
  def test_gate_runs_master_cli
    source = File.read(GATE)
    assert_includes source, '"bin/cli"'
    assert_match(/stdin_data|stdin\.puts/, source,
                 "bin/gate must feed the command to bin/cli on stdin")
    assert_includes source, "STAGE_TIMEOUT",
                    "bin/gate must bound how long it waits for a stage; a stage that never " \
                    "returns produces no output for INCONCLUSIVE to match on"
  end

# One boot per tier per tree, because one boot does the whole tier.
#
# The lexical pass was `/scan`, `/fix`, `/scan` — three runtime boots for a
# pipeline that already scans, fixes and re-scans inside one. /scan is
# /through --only scan, and that stage's sections are the aesthetic pass, the
# deep pass, the fix, and the re-scan that proves it; running the word three
# times ran that sequence three times. The semantic pass was `/critique` then
# `/review`, and both words name the critique stage, so the tier that costs
# the most ran twice.
#
# Asserted on the shape rather than the literal line, since the flag spellings
# move: what must hold is that no tier repeats a stage.
def test_each_tier_boots_the_runtime_once_per_tree
  source = File.read(GATE)
  lexical = source[/lexical = SCAN_ONLY \? (.*?) : (.*?)$/, 2].to_s
  semantic = source[/^  semantic = (.*?)$/, 1].to_s

  assert_equal 1, lexical.scan(%r{/\w+}).size,
               "the lexical tier boots bin/cli once: /scan already fixes and re-scans"
  assert_equal 1, semantic.scan(%r{/\w+}).size,
               "/critique and /review name one stage; running both runs the council twice"
end

  def test_gate_is_expected_to_keep_repo_clean
    source = File.read(GATE)
    assert_includes source, 'assert_clean("MASTER")'
    assert_includes source, 'assert_clean("RAILS", "OPENBSD", "STUDIO", "MASTER")'
  end

  # The gate must cover every sibling tree CLAUDE.md names, not a subset.
  #
  # It carried RAILS and OPENBSD and reported the repo clean on that basis. STUDIO
  # — dilla, lora, postpro, repligen — was never scanned, fixed or reviewed, so
  # "gate clean" was a claim about three quarters of the repo. Asserting the set
  # rather than one string, because the failure mode is a tree going missing from
  # the list and nothing noticing, which is what happened.
  def test_gate_targets_every_sibling_tree
    source = File.read(GATE)
    targets = source[/deploy: %w\[([^\]]*)\]/, 1].to_s.split

    %w[../RAILS ../OPENBSD ../STUDIO].each do |tree|
      assert_includes targets, tree,
                      "bin/gate does not scan #{tree}; a gate whose target list is shorter " \
                      "than the repo reports clean on the part it looked at"
    end
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
