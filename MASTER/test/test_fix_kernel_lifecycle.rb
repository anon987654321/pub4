# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "socket"
require "rbconfig"
require "timeout"
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
      assert_equal 1, repair.dig("payload", "breakdown", "applied")
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

  def test_execution_lock_serializes_independent_processes
    child_pid = nil

    with_workspace do |root|
      kernel = K.new(root:)
      ready = File.join(root, "child-ready")
      entered = File.join(root, "child-entered")
      child = <<~'RUBY'
        require "master"
        require "fix/kernel"

        root, ready, entered = ARGV
        File.write(ready, "ready\n")
        kernel = Master::Fix::Kernel.new(root:)
        kernel.execution_mutex.synchronize { File.write(entered, "entered\n") }
      RUBY

      begin
        kernel.execution_mutex.synchronize do
          child_pid = Process.spawn(
            RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", child,
            root, ready, entered, chdir: Master::ROOT, out: File::NULL, err: File::NULL
          )

          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
          sleep 0.01 until File.file?(ready) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          assert File.file?(ready), "child did not reach the lock boundary"
          sleep 0.1
          refute File.exist?(entered), "a second process entered /fix while the workspace lock was held"
        end

        _waited_pid, status = Timeout.timeout(5) { Process.wait2(child_pid) }
        child_pid = nil
        assert status.success?, "child failed to acquire the released execution lock"
        assert_equal "entered\n", File.read(entered)
      ensure
        if child_pid
          begin
            Process.kill("KILL", child_pid)
            Process.wait(child_pid)
          rescue Errno::ESRCH, Errno::ECHILD
            nil
          end
        end
      end
    end
  end

  def test_independent_kernel_instances_share_the_process_execution_lease
    with_workspace do |root|
      first = K.new(root:)
      second = K.new(root:)
      first_entered = Queue.new
      release_first = Queue.new
      second_attempting = Queue.new
      second_entered = Queue.new

      first_adapter = Object.new
      first_adapter.define_singleton_method(:last_terminal_state) { :done }
      first_adapter.define_singleton_method(:run_unlocked) do |_target, **_options|
        first_entered << :entered
        release_first.pop
        Master::Result.ok("DONE: first fixture")
      end

      second_adapter = Object.new
      second_adapter.define_singleton_method(:last_terminal_state) { :done }
      second_adapter.define_singleton_method(:run_unlocked) do |_target, **_options|
        second_entered << :entered
        Master::Result.ok("DONE: second fixture")
      end

      first_thread = Thread.new do
        first.run_fix_loop(
          first_adapter, target: root, max_passes: 2, budget_seconds: 60,
          incremental: false, requested: true
        )
      end
      second_thread = nil
      begin
        assert_equal :entered, Timeout.timeout(5) { first_entered.pop }
        second_thread = Thread.new do
          second_attempting << :attempting
          second.run_fix_loop(
            second_adapter, target: root, max_passes: 2, budget_seconds: 60,
            incremental: false, requested: true
          )
        end
        assert_equal :attempting, Timeout.timeout(5) { second_attempting.pop }
        assert_raises(Timeout::Error) { Timeout.timeout(0.15) { second_entered.pop } }
        release_first << :finish
        assert first_thread.value.ok?
        assert_equal :entered, Timeout.timeout(5) { second_entered.pop }
        assert second_thread.value.ok?
      ensure
        release_first << :finish if first_thread&.alive?
        [first_thread, second_thread].compact.each { |thread| thread.join(5) }
      end
    end
  end

  def test_kernel_repair_receipt_preserves_fixed_count_and_breakdown
    with_workspace do |root|
      kernel = K.new(root:)
      law = Struct.new(:id, :severity).new("TEST_REPAIR", :warning)
      repair = kernel.build_repair_loop(law:, agent: nil, scanner: Object.new, root:)
      repair.define_singleton_method(:scan_files) do |_files|
        [{ law: "TEST_REPAIR", file: "sample.rb" }]
      end
      repair.define_singleton_method(:fix_batch) do |_violations|
        @batch_breakdown = { applied: 2, rejected: 1 }
        2
      end
      repair.define_singleton_method(:pass_outcome) { |_fixed| :fixed }
      repair.define_singleton_method(:record_outcomes) { |_files, _status| nil }

      result = repair.run_once(["sample.rb"])
      event = kernel.verify_log!.find { |row| row["kind"] == "repair_pass" }

      assert_equal 2, result.fetch(:fixed)
      assert_equal :fixed, result.fetch(:status)
      assert_equal 2, event.dig("payload", "fixed")
      assert_equal({ "applied" => 2, "rejected" => 1 }, event.dig("payload", "breakdown"))
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
