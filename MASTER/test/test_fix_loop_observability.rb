# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/fix_loop"

class TestFixLoopObservability < Minitest::Test
  EventBus = Struct.new(:events) do
    def publish(name, payload = {})
      events << [name.to_s, payload]
    end
  end

  Collector = Struct.new(:candidate_count, :skipped, :files) do
    def collect(_target) = files
    def skip_reasons = {}
    def excluded_path_reasons = {}
  end

  Discipline = Struct.new(:error) do
    def begin_run(_files)
      raise error
    end
  end

  Journal = Struct.new(:id) do
    def start_or_resume(**) = { "id" => id }
  end

  PassRunner = Class.new do
    def reset_gaps! = nil
    def research_brief=(_brief); end
    def assessment_adapters(**) = []
    def cleanup_visual_runtime = nil
  end

  Plan = Struct.new(:to_h)

  # Unrequested: a requested run first builds the dependency graph and the research brief, which
  # this test does not exercise. The journal, the plan and the budget open before begin_run, so
  # they are doubles; the claim is only which phase a begin_run failure is reported under.
  def test_begin_run_crash_is_distinct_from_corpus_findings
    bus = EventBus.new([])
    error = FloatDomainError.new("Infinity can't be coerced into Integer")

    loop = Master::Fix::FixLoop.allocate
    loop.instance_variable_set(:@bus, bus)
    loop.instance_variable_set(:@file_collector, Collector.new(1, 0, [File.join(Master::ROOT, "data", "laws.yml")]))
    loop.instance_variable_set(:@convergence_discipline, Discipline.new(error))
    loop.instance_variable_set(:@run_journal, Journal.new("run-observability"))
    loop.instance_variable_set(:@pass_runner, PassRunner.new)
    # An empty transaction root: run start recovers stranded passes before preflight.
    loop.instance_variable_set(:@transaction_root, Dir.mktmpdir("fix-observability-"))
    loop.define_singleton_method(:mission_for) { |**| nil }
    loop.define_singleton_method(:exhausted_budget) { |**| nil }
    loop.define_singleton_method(:bind_fix_plan!) { |*| nil }
    loop.define_singleton_method(:repair_seconds_left) { |_| 30 }
    loop.define_singleton_method(:finish_run) { |result, *, **| result }

    output, = capture_io do
      Master::Fix::RunBudget.stub(:begin_run, nil) do
        Master::Fix::FixPlan.stub(:capture, Plan.new({})) do
          @result = loop.send(
            :run_unlocked,
            Master::ROOT,
            max_passes: 1,
            budget_seconds: 30,
            incremental: false,
            requested: false,
          )
        end
      end
    end

    crash = bus.events.find { |name, _| name == "fix_loop:crash" }
    refute_nil crash, "the begin_run failure must publish fix_loop:crash"

    assert_equal "fix_loop:crash", crash.fetch(0)
    assert_equal "FloatDomainError", crash.fetch(1).fetch(:error_class)
    assert_equal "begin_run", crash.fetch(1).fetch(:phase)
    assert_equal :crash, @result.category
    assert_match(/crash FloatDomainError @ begin_run/, output)
    refute_match(/corpus .*FloatDomainError/i, output)
  end
  def test_unlocked_run_always_attempts_final_cleanup_on_cancellation
    loop = Master::Fix::FixLoop.allocate
    cleanup_calls = []
    loop.define_singleton_method(:cancellation_requested?) { true }
    loop.define_singleton_method(:cancellation_terminal) do
      Master::Result.err("CANCELLED: test stop", category: :cancelled)
    end
    loop.define_singleton_method(:cleanup_run_resources) do |target:, run_id:|
      cleanup_calls << [target, run_id]
    end

    result = loop.send(
      :run_unlocked,
      "requested-target",
      max_passes: 1,
      budget_seconds: 30,
      incremental: false,
      requested: false,
    )

    assert result.err?
    assert_equal [["requested-target", nil]], cleanup_calls
  end

end
