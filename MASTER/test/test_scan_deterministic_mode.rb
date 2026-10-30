# frozen_string_literal: true

require_relative "test_helper"
require "review/scan/law_tree"
require "fix/scanner"
require "cli/pipeline/pass"

# `bin/check --ladder` calls /scan its lexical tier, and its own header says what that
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
# 354.8s — 91% of a "scan" was a critique nobody asked for, and `bin/check --ladder` runs
# /critique separately anyway as the tier that owns it.
#
# MASTER_SCAN_DETERMINISTIC=1 turns both off and nothing else. It is opt-in, so
# an ordinary /scan is unchanged; these tests hold both halves and the default.
class TestScanDeterministicMode < Minitest::Test
  ENV_KEY = "MASTER_SCAN_DETERMINISTIC"
  Clock = Master::Review::LLMDispatcher::PassClock
  Pass = Master::CLI::Pipeline::Pass

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

  # default_critique? is environment-controlled for normal passes and also
  # honours read-only apply=false, so the collaborators can be nil in these tests.
  def pipeline
    Master::CLI::Pipeline::Pass.new(scanner: nil, fix_loop: nil, root: Master::ROOT)
  end

  def agent_backed(scanner)
    scanner.laws.select { |rule| rule.respond_to?(:set_agent) }
  end

  def with_agent(rules)
    rules.reject { |rule| rule.instance_variable_get(:@agent).nil? }
  end

  # --- the scanner half ----------------------------------------------------

  def test_the_model_backed_rules_get_the_agent_by_default
    scanner = Master::Fix::Scanner.build(root: Master::ROOT, agent: fake_agent)

    refute_empty agent_backed(scanner), "no rule takes an agent — this file's premise is stale"
    refute_empty with_agent(agent_backed(scanner)),
                 "the agent never reached the rules, so the switch below would prove nothing"
  end

  def test_deterministic_mode_withholds_the_agent
    ENV[ENV_KEY] = "1"
    scanner = Master::Fix::Scanner.build(root: Master::ROOT, agent: fake_agent)

    assert_empty with_agent(agent_backed(scanner)),
                 "a rule still holds an agent, so it will still send a prompt per file"
  end

  # The rules switch themselves off through the guard they already carry, rather
  # than through a second mechanism. If that guard goes, this switch is inert
  # and nothing else would say so. Off is inconclusive, never clean.
  def test_an_agentless_adversarial_rule_asks_nothing_and_says_so
    rule = Master::Review::Scan::Laws::AdversarialLaw.new(agent: nil)

    error = assert_raises(RuntimeError) { rule.check("def a(x)\n  x\nend\n", path: "lib/thing.rb") }
    assert_match(/INCONCLUSIVE/, error.message)
  end

  # --- the council half ----------------------------------------------------

  def test_the_through_pipeline_leaves_the_council_to_be_asked_for
    refute Pass.critique_by_default?, "the council is opt-in: --critique or MASTER_FIX_COUNCIL=1"
  end

  def test_asking_for_the_council_turns_the_default_critique_on
    Clock.stub(:council_enabled?, true) { assert Pass.critique_by_default? }
  end

  def test_read_only_pass_suppresses_implicit_council
    refute Pass.critique_by_default?(apply: false)
  end

  def test_deterministic_mode_suppresses_a_requested_council
    ENV[ENV_KEY] = "1"

    Clock.stub(:council_enabled?, true) do
      refute Pass.critique_by_default?, "a deterministic scan would still run a 354.8s deliberation"
    end
  end

  # --- the switch is exact -------------------------------------------------

  def test_only_the_exact_value_switches_it
    ["0", "", "true", "yes"].each do |value|
      ENV[ENV_KEY] = value

      Clock.stub(:council_enabled?, true) do
        assert Pass.critique_by_default?, "#{value.inspect} switched off the council; only \"1\" may"
      end
    end
  end

  def test_only_the_exact_value_asks_for_the_council
    ["0", "", "true", "yes"].each do |value|
      refute Clock.council_enabled?(env: { "MASTER_FIX_COUNCIL" => value }), "#{value.inspect} asked for the council"
    end
    assert Clock.council_enabled?(env: { "MASTER_FIX_COUNCIL" => "1" })
  end

  # bin/check --ladder is the caller this exists for. If the wiring is dropped there, the
  # switch works and the stage still never finishes.
  def test_the_check_asks_for_it
    check = File.read(File.join(Master::ROOT, "lib", "operator", "check_ladder.rb"))

    assert_match(/"MASTER_SCAN_DETERMINISTIC"\s*=>\s*"1"/, check,
                 "bin/check --ladder no longer requests a deterministic lexical stage")
  end
end
