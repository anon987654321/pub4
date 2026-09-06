# frozen_string_literal: true

require_relative "test_helper"

# soul.yml declares seven hooks. Trace::Hooks is what fires them, and until
# 2026-09-06 nothing called `attach`, so every one was dead on a bus already
# carrying its trigger — scan:complete, rule_loop:fix_applied, llm:cost,
# phase:advanced and fix_loop:clean are all published by live code.
#
# Two directions throughout. A hook that fires on the wrong event is as wrong as
# one that never fires, and the cost hook has a threshold, which is where a rule
# is most likely to be off by one.
class TestTraceHooks < Minitest::Test
  # Minimal in-memory bus matching EventBus#subscribe / #publish, the shape
  # test_swallow_ledger uses for the ledger attached beside this one.
  class FakeBus
    attr_reader :published

    def initialize
      @subs = {}
      @published = []
    end

    def subscribe(pattern, &handler) = (@subs[pattern] ||= []) << handler

    def publish(event, payload = {})
      @published << [event, payload]
      (@subs[event] || []).each { |handler| handler.call(payload) }
    end
  end

  SOUL_HOOKS = [
    { "event" => "on_violation_found", "action" => "append_constitutional_violation",
      "params" => { "path" => ".constitutional_violations.jsonl" } },
    { "event" => "on_fix_applied", "action" => "publish", "params" => { "event" => "hooks:fix_applied" } },
    { "event" => "on_cost_threshold", "action" => "warn_cost_threshold", "params" => { "warn_at" => 0.5 } },
    { "event" => "on_convergence", "action" => "publish", "params" => { "event" => "hooks:convergence" } },
  ].freeze

  def setup
    @root = Dir.mktmpdir("trace_hooks_test")
    @bus = FakeBus.new
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && Dir.exist?(@root)
  end

  # attach registers an at_exit for on_session_end, which would fire once per
  # constructed instance for the whole test process. Subscribing by hand is what
  # every assertion below needs and none of them needs the exit hook.
  def hooks(budget_max: 0, config: SOUL_HOOKS)
    Master::Trace::Hooks.new(root: @root, event_bus: @bus, config:, budget_max:)
  end

  def attached(**opts)
    hooks(**opts).tap { |h| h.send(:subscribe_scan_complete) }
  end

  def events = @bus.published.map(&:first)

  def violations_file = File.join(@root, ".constitutional_violations.jsonl")

  # --- the declaration the constitution cares most about --------------------

  def test_a_scan_with_findings_appends_a_constitutional_violation
    attached
    @bus.publish("scan:complete", path: "lib/example.rb", count: 3, top_rules: { "NO_PUTS" => 3 })

    assert_path_exists violations_file
    record = JSON.parse(File.read(violations_file).lines.last)
    assert_equal "lib/example.rb", record["file"]
    assert_equal 3, record["count"]
    assert_equal({ "NO_PUTS" => 3 }, record["top_rules"])
  end

  # A clean scan is not a violation. The guard is `count.positive?`, and without
  # it every scan of a clean tree would append a row saying nothing happened.
  def test_a_clean_scan_appends_nothing
    attached
    @bus.publish("scan:complete", path: "lib/example.rb", count: 0)

    refute_path_exists violations_file
    refute_includes events, "hook:on_violation_found"
  end

  def test_each_scan_appends_rather_than_replaces
    attached
    2.times { @bus.publish("scan:complete", path: "lib/example.rb", count: 1) }

    assert_equal 2, File.readlines(violations_file).size
  end

  # --- the cost threshold ---------------------------------------------------

  def test_the_cost_hook_fires_once_at_half_the_budget_and_not_before
    subject = hooks(budget_max: 10.0)
    subject.send(:subscribe_cost)

    @bus.publish("llm:cost", cost: 4.9)
    refute_includes events, "hook:warning"

    @bus.publish("llm:cost", cost: 0.2)
    assert_includes events, "hook:warning"
  end

  # Once per session, not once per call above the line — a warning that repeats
  # on every token is a warning nobody reads.
  def test_the_cost_hook_does_not_fire_twice
    subject = hooks(budget_max: 10.0)
    subject.send(:subscribe_cost)
    3.times { @bus.publish("llm:cost", cost: 5.0) }

    assert_equal 1, events.count("hook:warning")
  end

  # No budget is not a budget of zero: with nothing to be half of, the threshold
  # cannot be crossed and the hook must stay quiet.
  def test_no_budget_means_no_cost_hook
    subject = hooks(budget_max: 0)
    subject.send(:subscribe_cost)
    @bus.publish("llm:cost", cost: 1_000.0)

    refute_includes events, "hook:warning"
  end

  # --- the publish actions --------------------------------------------------

  def test_a_publish_hook_republishes_under_the_name_soul_declares
    subject = hooks
    subject.send(:subscribe_fix_applied)
    subject.send(:subscribe_convergence)

    @bus.publish("rule_loop:fix_applied", rule: "NO_PUTS")
    @bus.publish("fix_loop:clean", passes: 2)

    assert_includes events, "hooks:fix_applied"
    assert_includes events, "hooks:convergence"
  end

  # An event soul.yml declares no hook for still announces itself on the bus,
  # and runs no action — that is what makes the block the thing in control.
  def test_an_undeclared_event_publishes_but_runs_no_action
    subject = hooks(config: [])
    subject.send(:subscribe_scan_complete)
    @bus.publish("scan:complete", path: "lib/example.rb", count: 2)

    assert_includes events, "hook:on_violation_found"
    refute_path_exists violations_file
  end

  # --- the wiring itself ----------------------------------------------------

  # The defect this file was written for: the class existed, the events
  # existed, the declarations existed, and nothing called attach. Booted for
  # real rather than grepped, because a test that reads boot_phases.rb for the
  # word "attach" passes against a method body of `raise`.
  def test_the_trace_boot_phase_attaches_hooks
    Dir.mktmpdir("trace_boot_test") do |root|
      config = Struct.new(:budget_max, :req_max).new(10.0, 100)
      booted = Master::Builder::TraceBoot.new(root:, config:).call
      booted[:bus].publish("scan:complete", path: "lib/example.rb", count: 2, top_rules: {})

      assert_path_exists File.join(root, ".constitutional_violations.jsonl"),
                         "TraceBoot stopped attaching Hooks — soul.yml's hooks fire through it and nothing else"
    end
  end

  # And the other half: every hook the constitution declares does something. A
  # declaration Hooks cannot route is a line of law with no effect, which is the
  # state this whole file records.
  def test_every_hook_soul_declares_produces_an_effect
    declared = Master.load_yaml(Master.data_path("soul.yml")).fetch("hooks")
    subject = hooks(config: declared, budget_max: 10.0)
    payload = { path: "lib/example.rb", count: 1, top_rules: {}, total_cost: 9.0, max_per_session: 10.0 }
    declared.each { |hook| subject.send(:publish_hook, hook["event"], payload) }

    declared.each do |hook|
      case hook["action"].to_s
      when "append_constitutional_violation"
        assert_path_exists violations_file, "#{hook["event"]} wrote no violation"
      when "publish"
        assert_includes events, hook.dig("params", "event").to_s, "#{hook["event"]} published nothing"
      when "warn_cost_threshold"
        assert_includes events, "hook:warning", "#{hook["event"]} warned about nothing"
      else
        flunk "soul.yml declares #{hook["action"]}, which Hooks#run_hook has no branch for"
      end
    end
  end
end
