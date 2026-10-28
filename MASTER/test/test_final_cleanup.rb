# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/final_cleanup"

class TestFinalCleanup < Minitest::Test
  EventBus = Struct.new(:events) do
    def publish(name, **payload) = events << [name, payload]
  end

  Committer = Struct.new(:lease_guard)

  class PassRunner
    attr_reader :calls

    def initialize(fail_runtime: false)
      @fail_runtime = fail_runtime
      @calls = []
    end

    def cleanup_visual_runtime
      @calls << :runtime
      raise IOError, "runtime shutdown failed" if @fail_runtime
    end

    def cleanup_visual_artifacts = @calls << :artifacts
  end

  class Journal
    MAX_RUNS = 3

    attr_reader :calls

    def initialize
      @calls = []
    end

    def history(limit:) = [{ "id" => "run-current" }].first(limit)
    def prune_assessment_reports!(keep_ids:) = @calls << [:assessment, keep_ids]
    def prune_architecture_reports! = @calls << :architecture
  end

  class KernelReceipt
    attr_reader :events

    def initialize(fail: false)
      @fail = fail
      @events = []
    end

    def append_event(kind, payload, run_id:)
      raise IOError, "ledger unavailable" if @fail

      @events << [kind, payload, run_id]
    end
  end

  def build_stage(fail_runtime: false, fail_receipt: false)
    @bus = EventBus.new([])
    @committer = Committer.new(:active_guard)
    @runner = PassRunner.new(fail_runtime:)
    @journal = Journal.new
    @kernel = KernelReceipt.new(fail: fail_receipt)
    Master::Fix::FinalCleanup.new(
      root: Dir.pwd, bus: @bus, kernel: @kernel, committer: @committer,
      pass_runner: @runner, run_journal: @journal
    )
  end

  def test_runs_all_run_owned_cleanup_and_records_a_durable_receipt
    receipt = build_stage.run(target: Dir.pwd, run_id: "run-current", terminal_state: :done)

    assert_equal "clean", receipt.fetch(:status)
    assert_nil @committer.lease_guard
    assert_equal %i[runtime artifacts], @runner.calls
    assert_includes @journal.calls, [:assessment, ["run-current"]]
    assert_includes @journal.calls, :architecture
    assert_equal "cleanup_completed", @kernel.events.fetch(0).fetch(0)
    assert_equal "fix_loop:cleanup", @bus.events.fetch(0).fetch(0)
  end

  def test_failure_is_reported_but_later_cleanup_steps_still_run
    receipt = build_stage(fail_runtime: true).run(
      target: Dir.pwd, run_id: "run-current", terminal_state: :done
    )

    assert_equal "warning", receipt.fetch(:status)
    assert_nil @committer.lease_guard
    assert_equal %i[runtime artifacts], @runner.calls
    assert_equal "visual_runtime", receipt.fetch(:warnings).fetch(0).fetch(:step)
    assert_equal "cleanup_warning", @kernel.events.fetch(0).fetch(0)
  end

  def test_durable_receipt_failure_is_not_reported_as_clean
    receipt = build_stage(fail_receipt: true).run(
      target: Dir.pwd, run_id: "run-current", terminal_state: :blocked
    )

    assert_equal "warning", receipt.fetch(:status)
    assert_equal "cleanup_receipt", receipt.fetch(:warnings).fetch(0).fetch(:step)
    assert_equal "fix_loop:cleanup", @bus.events.fetch(0).fetch(0)
  end
end
