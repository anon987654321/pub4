# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "digest"
require "stringio"
require "socket"
require "timeout"
require_relative "../lib/fix/kernel"
require_relative "../lib/fix/fix_loop"
require_relative "../lib/fix/repair_loop"
require_relative "../lib/fix/run_journal"

class TestFixKernel < Minitest::Test
  K = Master::Fix::Kernel

  # Writes a valid chain the way an appender must: seq, prev and the body hash.
  def write_log(root, rows)
    previous = K::GENESIS

    lines = rows.each_with_index.map do |(kind, run_id), index|
      body = { "seq" => index + 1, "at" => "2026-10-28T00:00:00Z", "run_id" => run_id,
               "kind" => kind, "payload" => {}, "prev" => previous }
      row = body.merge("hash" => Digest::SHA256.hexdigest(JSON.generate(body)))
      previous = row.fetch("hash")
      JSON.generate(row) + "\n"
    end

    path = File.join(root, K::LOG_RELATIVE_PATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, lines.join)
    path
  end

  def with_workspace
    Dir.mktmpdir("pub4-kernel") do |root|
      Dir.mkdir(File.join(root, ".git"))
      File.write(File.join(root, ".pub4"), <<~YAML)
        schema: 1
        tree: #{File.basename(root).downcase}
        allows:
          master: read_write
        adapters: []
      YAML
      yield root
    end
  end

  def test_replay_returns_the_complete_run_for_a_sequence
    with_workspace do |root|
      write_log(root, [%w[run_started a], %w[observation b], %w[terminal a]])

      replay = K.replay_events(root: File.join(root, "MASTER"), seq: 3)
      assert_equal "a", replay.fetch("run_id")
      assert_equal %w[run_started terminal], replay.fetch("events").map { |row| row.fetch("kind") }
      assert_nil K.replay_events(root:, seq: 9)
    end
  end

  def test_replay_cli_exit_codes
    with_workspace do |root|
      write_log(root, [%w[terminal a]])

      assert_equal 64, capture_cli(root, "x")
      assert_equal 1, capture_cli(root, "2")
      assert_equal 0, capture_cli(root, "1")
    end
  end

  def test_replay_cli_reports_a_corrupt_log
    with_workspace do |root|
      path = write_log(root, [%w[terminal a]])
      File.write(path, File.read(path).sub('"kind":"terminal"', '"kind":"changed"'))

      assert_equal 1, capture_cli(root, "1")
    end
  end

  def test_full_verification_refuses_an_incomplete_final_record
    with_workspace do |root|
      path = write_log(root, [%w[terminal a]])
      File.binwrite(path, File.binread(path).delete_suffix("\n"))

      assert_raises(K::LedgerCorruption) { K.read_log(path) }
    end
  end

  def test_sequence_gap_is_refused
    with_workspace do |root|
      path = write_log(root, [%w[observation a], %w[terminal a]])
      File.write(path, File.readlines(path).last)

      assert_raises(K::LedgerCorruption) { K.read_log(path) }
    end
  end

  def test_missing_log_reads_empty
    with_workspace do |root|
      assert_equal [], K.read_log(File.join(root, K::LOG_RELATIVE_PATH))
    end
  end


  def test_restart_terminalizes_a_kernel_run_whose_recorded_process_is_gone
    with_workspace do |root|
      kernel = K.new(root:)
      # This PID is outside the normal user-space range on supported hosts,
      # so the test never depends on process-id reuse timing.
      pid = 2_147_483_647

      kernel.send(
        :append_event,
        "coordinator_started",
        { actor: "test", host: Socket.gethostname, pid:, target: ".", max_passes: 2,
          budget_seconds: 60, requested: false },
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

  def test_restart_reconciliation_leaves_same_process_runs_unresolved
    with_workspace do |root|
      kernel = K.new(root:)
      kernel.send(
        :append_event,
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
      refute terminalized, "another Kernel instance in this process must not terminalize a live peer"
    end
  end

  def test_independent_kernel_instances_share_the_process_execution_lease
    with_workspace do |root|
      first = K.new(root:)
      second = K.new(root:)
      first_entered = Queue.new
      allow_first_to_finish = Queue.new
      second_attempting = Queue.new
      second_entered = Queue.new

      first_adapter = Object.new
      first_adapter.define_singleton_method(:last_terminal_state) { :done }
      first_adapter.define_singleton_method(:run_unlocked) do |_target, **_options|
        first_entered << :entered
        allow_first_to_finish.pop
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
        allow_first_to_finish << :finish
        assert first_thread.value.ok?
        assert_equal :entered, Timeout.timeout(5) { second_entered.pop }
        assert second_thread.value.ok?
      ensure
        allow_first_to_finish << :finish if first_thread&.alive?
        [first_thread, second_thread].compact.each { |thread| thread.join(5) }
      end
    end
  end

  def test_kernel_serializes_and_terminalizes_the_fix_loop_adapter
    with_workspace do |root|
      kernel = K.new(root:)
      adapter = Object.new
      adapter.define_singleton_method(:last_terminal_state) { :done }
      adapter.define_singleton_method(:run_unlocked) do |target, **options|
        @target = target
        @options = options
        kernel.record_repair_outcome(
          law: "TEST_REPAIR", status: :fixed, fixed: 1, breakdown: { applied: 1 }
        )
        Master::Result.ok("DONE: fixture")
      end

      result = kernel.run_fix_loop(
        adapter, target: root, max_passes: 2, budget_seconds: 60,
        incremental: false, requested: true,
      )

      assert result.ok?
      assert_equal root, adapter.instance_variable_get(:@target)
      assert_equal false, adapter.instance_variable_get(:@options).fetch(:incremental)
      events = kernel.verify_log!
      start = events.find { |row| row["kind"] == "coordinator_started" }
      terminal = events.find { |row| row["kind"] == "coordinator_terminal" }
      assert_equal start.fetch("run_id"), terminal.fetch("run_id")
      assert_equal "done", terminal.dig("payload", "state")
      assert_equal "ok", terminal.dig("payload", "result")
      repair = events.find { |row| row["kind"] == "repair_pass" }
      assert_equal start.fetch("run_id"), repair.fetch("run_id")
      assert_equal 1, repair.dig("payload", "fixed")
      assert_nil adapter.instance_variable_get(:@cancellation), "Kernel must restore the prior cancellation state"
    end
  end

  def test_uncertain_adapter_failure_gets_an_unknown_outcome_receipt
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

  def test_legacy_fix_constants_are_the_canonical_kernel_classes
    assert_same K::ConvergenceAdapter, Master::Fix::FixLoop
    assert_same K::LifecycleJournal, Master::Fix::RunJournal
    assert_same K::RepairAdapter, Master::Fix::RepairLoop

    # These constants would land on a separate legacy class if the adapter's
    # child files loaded before its canonical identity was established.
    assert_same K::RepairAdapter::FixVerification, Master::Fix::RepairLoop::FixVerification
  end

  def test_kernel_owns_one_durable_run_journal
    with_workspace do |root|
      kernel = K.new(root:)

      assert_instance_of Master::Fix::RunJournal, kernel.lifecycle_journal
      assert_same kernel.lifecycle_journal, kernel.run_journal

      run = kernel.lifecycle_journal.start_or_resume(
        target: root, files: [], max_passes: 2, budget_seconds: 60
      )
      assert File.file?(File.join(root, ".master", "fix_runs.json"))
      assert_equal run.fetch("id"), kernel.lifecycle_journal.history.last.fetch("id")
    end
  end

  def test_coordinated_fix_run_is_written_to_the_hash_chained_kernel_ledger
    with_workspace do |root|
      kernel = K.new(root:, actor: "fix-test")
      run_id = kernel.begin_coordinated_run(
        target: root, max_passes: 3, budget_seconds: 60, requested: true
      )
      kernel.finish_coordinated_run(
        run_id:, state: :done, outcome: Master::Result.ok("DONE: fixture")
      )

      events = kernel.verify_log!
      start = events.find { |event| event["kind"] == "coordinator_started" }
      terminal = events.find { |event| event["kind"] == "coordinator_terminal" }
      assert_equal run_id, start.fetch("run_id")
      assert_equal ".", start.dig("payload", "target")
      assert_equal 3, start.dig("payload", "max_passes")
      assert_equal "done", terminal.dig("payload", "state")
      assert_equal "ok", terminal.dig("payload", "result")
    end
  end

  def test_repair_scan_failure_is_preserved_as_an_error_outcome
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

  def test_kernel_factory_owns_repair_loop_and_records_its_outcome
    with_workspace do |root|
      kernel = K.new(root:)
      law = Struct.new(:id, :severity).new("TEST_REPAIR", :warning)
      loop = kernel.build_repair_loop(law:, agent: nil, scanner: Object.new, root:)

      assert_same kernel, loop.kernel
      result = loop.run_once([])
      assert_equal :clean, result.fetch(:status)
      event = kernel.verify_log!.find { |row| row["kind"] == "repair_pass" }
      assert_equal "TEST_REPAIR", event.dig("payload", "law")
      assert_equal "clean", event.dig("payload", "status")
    end
  end

  def test_kernel_repair_receipt_preserves_fixed_count_and_breakdown
    with_workspace do |root|
      kernel = K.new(root:)
      law = Struct.new(:id, :severity).new("TEST_REPAIR", :warning)
      loop = kernel.build_repair_loop(law:, agent: nil, scanner: Object.new, root:)
      loop.define_singleton_method(:scan_files) { |_files| [{ law: "TEST_REPAIR", file: "sample.rb" }] }
      loop.define_singleton_method(:fix_batch) do |_violations|
        @batch_breakdown = { applied: 2, rejected: 1 }
        2
      end
      loop.define_singleton_method(:pass_outcome) { |_fixed| :fixed }
      loop.define_singleton_method(:record_outcomes) { |_files, _status| nil }

      result = loop.run_once(["sample.rb"])
      event = kernel.verify_log!.find { |row| row["kind"] == "repair_pass" }

      assert_equal 2, result.fetch(:fixed)
      assert_equal :fixed, result.fetch(:status)
      assert_equal 2, event.dig("payload", "fixed")
      assert_equal({ "applied" => 2, "rejected" => 1 }, event.dig("payload", "breakdown"))
    end
  end

  private

  def capture_cli(root, seq)
    status = nil
    capture_io { status = K.replay_cli(root:, seq:) }
    status
  end
end
