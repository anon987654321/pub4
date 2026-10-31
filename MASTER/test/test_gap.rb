# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require_relative "../checks/support/check_result"

# A flat "inconclusive" says nothing about whether waiting helps, what checking
# costs, or whose call the answer is. Gap carries those three, and each has a
# reader: the dmesg clause, the check renderer, and /fix, which lists a
# :decision_for_operator finding and never attempts it.
class TestGap < Minitest::Test
  Rule = Struct.new(:id, :severity)
  CHECKS_DIR = File.expand_path("../checks", __dir__)

  def test_gap_validates_and_speaks_in_one_clause
    gap = Master::Gap::DEPLOY_HOST_ONLY

    assert_equal "gap: never resolves alone, checking costs a trip to the deploy host, a fact", gap.clause
    assert_equal "gap: resolves alone in 2m, checking costs seconds, a fact", Master::Gap.new(horizon: 90, cost_to_check: :seconds).clause
    assert Master::Gap::OPERATOR_DECISION.decision_for_operator?
    refute gap.decision_for_operator?
    assert_raises(ArgumentError) { Master::Gap.new(horizon: 0) }
    assert_raises(ArgumentError) { Master::Gap.new(cost_to_check: :free) }
    assert_raises(ArgumentError) { Master::Gap.new(decidability: :opinion) }
    assert_equal %i[horizon cost_to_check decidability], Master::Gap.members
    refute Master.const_defined?(:COSTS, false), "table constants must not leak into Master"
  end

  def test_result_err_carries_a_gap_and_dmesg_prints_the_clause
    err = Master::Result.err("no browser", category: :inconclusive, gap: Master::Gap::NO_BROWSER)

    assert_equal Master::Gap::NO_BROWSER, err.gap
    assert_nil Master::Result.err("plain", category: :inconclusive).gap
    out, = capture_io { Master::Trace::Dmesg.gap("test0", "cannot look", err.gap) }
    assert_includes out, "test0: cannot look, gap: never resolves alone, checking costs minutes, a fact"
    out, = capture_io { Master::Trace::Dmesg.gap("test0", "plain", nil) }
    assert_equal "test0: plain\n", out
  end

  def test_check_result_renders_the_gap_beside_its_reason_and_keeps_it_through_merge
    leaf = Deploy::CheckResult.new.inconclusive!("no stamps", gap: Master::Gap::DEPLOY_HOST_ONLY).inconclusive!("other")
    suite = Deploy::CheckResult.new.merge!(leaf, label: "leaf")

    _, err = capture_io { suite.render }
    assert_includes err, "[leaf] no stamps (gap: never resolves alone, checking costs a trip to the deploy host, a fact)"
    assert_includes err, "  - [leaf] other\n"
    assert_equal [Master::Gap::DEPLOY_HOST_ONLY], suite.gaps.values
  end

  def run_runner(script_row)
    Dir.mktmpdir("gap") do |dir|
      registry = File.join(dir, "checks.yml")
      File.write(registry, YAML.dump("probe" => { "script" => "fixtures/gap/inconclusive.rb" }.merge(script_row)))
      out, = Open3.capture2e({ "CHECKS_FILE" => registry, "CHECK_LEDGER" => File.join(dir, "l.jsonl") },
                             RbConfig.ruby, File.join(CHECKS_DIR, "runner.rb"), "probe")
      out
    end
  end

  def test_runner_prints_the_gap_a_script_check_declares
    declared = run_runner("gap" => { "horizon" => "operator", "cost_to_check" => "minutes", "decidability" => "fact" })
    assert_match(/probe inconclusive, gap: waits for the operator, checking costs minutes, a fact/, declared)

    assert_match(/probe inconclusive$/, run_runner({}))
  end

  def test_the_real_check_registry_declares_gaps_the_runner_can_build
    YAML.safe_load_file(File.join(CHECKS_DIR, "checks.yml")).each do |name, row|
      next unless row.is_a?(Hash) && row["gap"]

      spec = row["gap"].to_h { |key, value| [key.to_sym, value.is_a?(String) ? value.to_sym : value] }
      assert Master::Gap.new(**spec), "#{name} declares a gap Master::Gap rejects"
    end
  end

  # /fix: a finding whose repair is a rendered value is listed with its gap and
  # never reaches the model.
  class ExplodingAgent
    def method_missing(name, *) = raise("the model was asked (#{name}) about an operator-owned finding")

    def respond_to_missing?(*) = true
  end

  def test_fix_lists_operator_decisions_without_attempting_them
    bus = Class.new do
      attr_reader :events

      def publish(event, payload = {}) = (@events ||= []) << [event, payload]
    end.new
    loop = Master::Fix::RepairLoop.new(law: Rule.new("CONTRAST_TOKENS", :warning), agent: ExplodingAgent.new,
                                    scanner: Object.new, root: Master::ROOT, bus:)
    violation = { file: "/x/a.scss", law: "CONTRAST_TOKENS", message: "low", severity: :warning }

    out, = capture_io { assert_equal :needs_person, loop.send(:fix_batch, [violation]).then { loop.instance_variable_get(:@batch_breakdown).keys.first } }
    assert_includes out, "CONTRAST_TOKENS listed, not attempted"
    assert_includes out, "gap: waits for the operator, checking costs the operator, the operator's decision"
    event = bus.events.find { |name, _| name == "repair_loop:operator_gap" }
    assert_equal Master::Gap::OPERATOR_DECISION, event.last[:gap]

    pulse = Master::Fix::RunPulse.new(max_passes: 3, clock: -> { 0.0 }, load: -> { 0.0 })
    pulse.observe("repair_loop:operator_gap", event.last)
    pulse.observe("repair_loop:operator_gap", event.last)
    assert_includes pulse.pass_summary(1, tokens: 0), "fix0: pass 1 listed for the operator, not attempted = 2 (CONTRAST_TOKENS 2)"
  end

  def test_the_council_that_cannot_sit_says_why_and_whose_call_it_is
    council = Master::Review::Council::Deliberation.allocate
    out, = capture_io do
      err = council.send(:unconvened, "council: no provider", :validation, Master::Gap.new(horizon: :never, cost_to_check: :minutes))
      assert_equal :validation, err.category
      assert_equal :never, err.gap.horizon
      council.send(:unconvened, "council: no provider", :validation, err.gap)
    end
    assert_equal 1, out.scan("council0: cannot convene, gap: never resolves alone").size, "once, not once per file"

    spend = council.send(:spend_gap)
    assert_equal :operator, spend.cost_to_check
    assert_predicate spend.horizon, :positive?
  end

  def test_visual_custody_names_what_is_environment_and_what_is_the_operators_call
    custody = Master::Fix::VisualCustody.new(root: Master::ROOT, surfaces: [])

    assert_equal Master::Gap::NO_BROWSER, custody.send(:unavailable).gap
    assert_equal Master::Fix::VisualCustody::UNMEASURABLE, custody.send(:compare_payloads, [], "x").gap

    custody.define_singleton_method(:baseline_path) { |_surface| "/nonexistent/baseline.json" }
    surface = Struct.new(:id).new("brgen/home")
    missing = custody.send(:compare_payloads, [[surface, {}]], "after visual fix")
    assert_equal :inconclusive, missing.category
    assert_equal Master::Gap::OPERATOR_DECISION, missing.gap
  end

  # The runner loads both paths into one class, so a second body redefines every
  # method the first one set: a copy two commits behind turned
  # inconclusive!(reason, gap:) into an ArgumentError and ended the ladder at the
  # first check with no browser. OPENBSD's path therefore holds no body of its
  # own, only the require that reaches MASTER's.
  def test_openbsd_reads_the_check_kernel_rather_than_carrying_it
    reader = File.join(Master::ROOT, "..", "OPENBSD", "lib", "check_result.rb")
    code = File.readlines(reader).map(&:strip).reject { |line| line.empty? || line.start_with?("#") }

    assert_equal ['require_relative "../../MASTER/checks/support/check_result"'], code
    kernel = File.expand_path(File.join(File.dirname(reader), "../../MASTER/checks/support/check_result.rb"))
    assert_equal File.join(Master::ROOT, "checks", "support", "check_result.rb"), kernel
  end
end
