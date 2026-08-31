# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/rule_dsl"
require "review/scan/infra_helpers"
require "cli/through_pipeline"

# `bin/gate` calls /scan its lexical tier, and its own header says what that
# means: "deterministic detectors, no model". The runtime disagreed with it in
# two places at once, and the stage had never reached a verdict.
#
# Measured on this tree, `lib/io`, 46 files, through `bin/cli`:
#
#   as shipped                     5 files in 395s, killed by the 1200s timeout
#   agent withheld from the rules  390s complete, ¢115 / 77k tokens
#   council also suppressed        12s complete, no model cost
#
# The first number is AdversarialRule, which sends a per-file prompt. The second
# is the council: of that 390s, the two scan phases were 32s and crit0 was
# 354.8s — 91% of a "scan" was a critique nobody asked for, and `bin/gate` runs
# /critique separately anyway as the tier that owns it.
#
# MASTER_SCAN_DETERMINISTIC=1 turns both off and nothing else. It is opt-in, so
# an ordinary /scan is unchanged; these tests hold both halves and the default.
class TestScanDeterministicMode < Minitest::Test
  ENV_KEY = "MASTER_SCAN_DETERMINISTIC"

  def setup
    @saved = ENV[ENV_KEY]
    ENV.delete(ENV_KEY)
  end

  def teardown
    @saved.nil? ? ENV.delete(ENV_KEY) : ENV[ENV_KEY] = @saved
  end

  # A stand-in for the real agent: the model-backed rules only ask whether one
  # is present, so anything non-nil exercises the branch.
  def fake_agent = Object.new

  # default_critique? reads only the environment, so the collaborators can be
  # nil — constructing a real scanner and fix loop here would test them, not it.
  def pipeline
    Master::CLI::ThroughPipeline.new(scanner: nil, fix_loop: nil, root: Master::ROOT)
  end

  def agent_backed(scanner)
    scanner.rules.select { |rule| rule.respond_to?(:set_agent) }
  end

  def with_agent(rules)
    rules.reject { |rule| rule.instance_variable_get(:@agent).nil? }
  end

  # --- the scanner half ----------------------------------------------------

  def test_the_model_backed_rules_get_the_agent_by_default
    scanner = Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT, agent: fake_agent)

    refute_empty agent_backed(scanner), "no rule takes an agent — this file's premise is stale"
    refute_empty with_agent(agent_backed(scanner)),
                 "the agent never reached the rules, so the switch below would prove nothing"
  end

  def test_deterministic_mode_withholds_the_agent
    ENV[ENV_KEY] = "1"
    scanner = Master::Review::Scan::InfraHelpers.build_scanner(root: Master::ROOT, agent: fake_agent)

    assert_empty with_agent(agent_backed(scanner)),
                 "a rule still holds an agent, so it will still send a prompt per file"
  end

  # The rules switch themselves off through the guard they already carry, rather
  # than through a second mechanism. If that guard goes, this switch is inert
  # and nothing else would say so.
  def test_an_agentless_adversarial_rule_finds_nothing
    rule = Master::Review::Scan::Rules::AdversarialRule.new(agent: nil)

    assert_empty rule.check("def a(x)\n  x\nend\n", path: "lib/thing.rb")
  end

  # --- the council half ----------------------------------------------------

  def test_the_through_pipeline_critiques_by_default
    assert pipeline.send(:default_critique?),
           "critique stopped defaulting on — /scan would silently lose the council"
  end

  def test_deterministic_mode_suppresses_the_council
    ENV[ENV_KEY] = "1"

    refute pipeline.send(:default_critique?),
           "a deterministic scan would still run a 354.8s deliberation"
  end

  # --- the switch is exact -------------------------------------------------

  def test_only_the_exact_value_switches_it
    ["0", "", "true", "yes"].each do |value|
      ENV[ENV_KEY] = value

      assert pipeline.send(:default_critique?),
             "#{value.inspect} switched off the council; only \"1\" may"
    end
  end

  # bin/gate is the caller this exists for. If the wiring is dropped there, the
  # switch works and the stage still never finishes.
  def test_the_gate_asks_for_it
    gate = File.read(File.join(Master::ROOT, "bin", "gate"))

    assert_match(/"MASTER_SCAN_DETERMINISTIC"\s*=>\s*"1"/, gate,
                 "bin/gate no longer requests a deterministic lexical stage")
  end
end
