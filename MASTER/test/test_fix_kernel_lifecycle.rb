# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "socket"
require_relative "../lib/fix/kernel"
require_relative "../lib/fix/run_journal"
require_relative "../lib/fix/kernel/repair_adapter"

class TestFixKernelLifecycle < Minitest::Test
  K = Master::Fix::Kernel

  def with_workspace
    Dir.mktmpdir("pub4-kernel-lifecycle") do |root|
      Dir.mkdir(File.join(root, ".git"))
      File.write(File.join(root, ".pub4"), <<~YAML)
        schema: 1
        tree: lifecycle
        allows:
          master: read_write
        adapters: []
      YAML
      yield root
    end
  end

  def test_kernel_serializes_and_terminalizes_a_fix_loop_adapter
    with_workspace do |root|
      kernel = K.new(root:, actor: "fix-test")
      adapter = Object.new
      adapter.define_singleton_method(:last_terminal_state) { :done }
      adapter.define_singleton_method(:run_unlocked) do |target, **options|
        @target = target
        @options = options
        kernel.bind_fix_run(
          adapter: self, run_id: "fixture-run", target:,
          max_passes: options.fetch(:max_passes),
          budget_seconds: options.fetch(:budget_seconds),
          requested: options.fetch(:requested)
        )
        kernel.record_repair_outcome(
          law: "TEST_REPAIR", status: :fixed, fixed: 1, breakdown: { applied: 1 }
        )
        Master::Result.ok("DONE: fixture")
      end

      result = kernel.run_fix_loop(
        adapter, target: root, max_passes: 2, budget_seconds: 60,
        incremental: false, requested: true
      )

      assert result.ok?
      assert_equal root, adapter.instance_variable_get(:@target)
      assert_equal false, adapter.instance_variable_get(:@options).fetch(:incremental)
      events = kernel.verify_log!
      start = events.find { |row| row["kind"] == "coordinator_started" }
      terminal = events.find { |row| row["kind"] == "coordinator_terminal" }
      repair = events.find { |row| row["kind"] == "repair_pass" }
      assert_equal start.fetch("run_id"), terminal.fetch("run_id")
      assert_equal start.fetch("run_id"), repair.fetch("run_id")
      assert_equal "done", terminal.dig("payload", "state")
      assert_equal "ok", terminal.dig("payload", "result")
      assert_equal 1, repair.dig("payload", "fixed")
      assert_nil adapter.instance_variable_get(:@cancellation)
      assert_nil kernel.instance_variable_get(:@current_run_id)
    end
  end

  def test_adapter_exception_records_unknown_outcome_and_cleans_run_context
    with_workspace do |root|
      kernel = K.new(root:)
      adapter = Object.new
      adapter.define_singleton_method(:last_terminal_state) { nil }
      adapter.define_singleton_method(:run_unlocked) do |*_args, **_options|
        raise IOError, "simulated loss after an unobserved effect"
      end

      error = assert_raises(IOError) do
        kernel.run_fix_loop(
          adapter, target: root, max_passes: 2, budget_seconds: 60,
          incremental: false, requested: true
        )
      end
      assert_match(/simulated loss/, error.message)
      events = kernel.verify_log!
      start = events.find { |row| row["kind"] == "coordinator_started" }
      terminal = events.find do |row|
        row["kind"] == "coordinator_terminal" && row["run_id"] == start.fetch("run_id")
      end
      assert_equal "unknown_outcome", terminal.dig("payload", "state")
      assert_equal "IOError", terminal.dig("payload", "error_class")
      assert_nil kernel.instance_variable_get(:@current_run_id)
    end
  end

  def test_restart_terminalizes_an_orphaned_run_from_a_dead_same_host_process
    with_workspace do |root|
      kernel = K.new(root:)
      dead_pid = 2_147_483_647
      kernel.append_event(
        "coordinator_started",
        { actor: "test", host: Socket.gethostname, pid: dead_pid, target: ".",
          max_passes: 2, budget_seconds: 60, requested: false },
        run_id: "orphaned-kernel-run"
      )

      kernel.begin_coordinated_run(
        target: root, max_passes: 2, budget_seconds: 60, requested: false
      )

      terminal = kernel.verify_log!.find do |row|
        row["kind"] == "coordinator_terminal" && row["run_id"] == "orphaned-kernel-run"
      end
      assert_equal "unknown_outcome", terminal.dig("payload", "state")
      assert_equal true, terminal.dig("payload", "recovered")
      assert_match(/ended without a terminal receipt/, terminal.dig("payload", "reason"))
    end
  end

  def test_restart_reconciliation_does_not_terminalize_a_live_same_process_run
    with_workspace do |root|
      kernel = K.new(root:)
      kernel.append_event(
        "coordinator_started",
        { actor: "test", host: Socket.gethostname, pid: Process.pid, target: ".",
          max_passes: 2, budget_seconds: 60, requested: false },
        run_id: "same-process-run"
      )

      kernel.begin_coordinated_run(
        target: root, max_passes: 2, budget_seconds: 60, requested: false
      )

      terminalized = kernel.verify_log!.any? do |row|
        row["kind"] == "coordinator_terminal" && row["run_id"] == "same-process-run"
      end
      refute terminalized, "same-process run ownership is ambiguous to a second Kernel instance"
    end
  end

  def test_legacy_constants_resolve_to_the_kernel_owned_classes
    require_relative "../lib/fix/fix_loop"
    require_relative "../lib/fix/repair_loop"

    assert_same K::ConvergenceAdapter, Master::Fix::FixLoop
    assert_same K::LifecycleJournal, Master::Fix::RunJournal
    assert_same K::RepairAdapter, Master::Fix::RepairLoop
    assert_same K::RepairAdapter::FixVerification, Master::Fix::RepairLoop::FixVerification
  end

  def test_kernel_owns_a_single_durable_journal_handle
    with_workspace do |root|
      kernel = K.new(root:)

      assert_instance_of K::LifecycleJournal, kernel.lifecycle_journal
      assert_same kernel.lifecycle_journal, kernel.run_journal
      run = kernel.lifecycle_journal.start_or_resume(
        target: root, files: [], max_passes: 2, budget_seconds: 60
      )
      assert File.file?(File.join(root, ".master", "fix_runs.json"))
      assert_equal run.fetch("id"), kernel.lifecycle_journal.history.last.fetch("id")
    end
  end

  def test_repair_scan_failure_is_recorded_as_an_error_outcome
    with_workspace do |root|
      kernel = K.new(root:)
      scanner = Object.new
      scanner.define_singleton_method(:scan) { |*_args, **_options| raise "synthetic scanner failure" }
      law = Struct.new(:id, :severity).new("TEST_SCAN_FAILURE", :warning)
      repair = kernel.build_repair_loop(law:, agent: nil, scanner:, root:)
      path = File.join(root, "sample.rb")
      File.write(path, "fixture\n")

      result = repair.run_once([path])
      assert_equal :error, result.fetch(:status)
      assert_match(/synthetic scanner failure/, result.fetch(:error))
      event = kernel.verify_log!.find do |row|
        row["kind"] == "repair_pass" && row.dig("payload", "law") == "TEST_SCAN_FAILURE"
      end
      assert_equal "error", event.dig("payload", "status")
      assert_equal 0, event.dig("payload", "fixed")
      assert_equal 1, event.dig("payload", "breakdown", "error")
    end
  end

  def test_clean_repair_pass_is_recorded_in_the_kernel_ledger
    with_workspace do |root|
      kernel = K.new(root:)
      law = Struct.new(:id, :severity).new("TEST_REPAIR", :warning)
      repair = kernel.build_repair_loop(law:, agent: nil, scanner: Object.new, root:)

      result = repair.run_once([])
      assert_equal :clean, result.fetch(:status)
      event = kernel.verify_log!.find { |row| row["kind"] == "repair_pass" }
      assert_equal "TEST_REPAIR", event.dig("payload", "law")
      assert_equal "clean", event.dig("payload", "status")
    end
  end
end
