# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require_relative "../lib/fix/kernel"
require_relative "../lib/fix/kernel/repair_adapter"

class TestFixKernel < Minitest::Test
  K = Master::Fix::Kernel

  def with_workspace(access: "read_write")
    Dir.mktmpdir("pub4-kernel") do |root|
      File.write(File.join(root, ".pub4"), <<~YAML)
        schema: 1
        tree: #{File.basename(root).downcase}
        allows:
          master: #{access}
        adapters: []
      YAML
      yield root
    end
  end

  def law(name: "replace_bad_text", sacred: false, automatic: true, replacement: "good")
    K::Law.new(
      name:,
      sacred:,
      automatic:,
      check: ->(observation) { observation.file("sample.txt")&.content != replacement },
      repair: ->(_observation) { { "sample.txt" => replacement } }
    )
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

  def test_auto_repair_is_verified_and_the_log_is_hash_chained
    with_workspace do |root|
      File.write(File.join(root, "sample.txt"), "bad\n")
      kernel = K.new(root:)
      outcome = kernel.fix(root, laws: [law(replacement: "good\n")])

      assert_equal :converged, outcome.state
      assert_equal "good\n", File.read(File.join(root, "sample.txt"))
      events = kernel.verify_log!
      assert_equal %w[run_started observation repair observation verification observation terminal],
                   events.map { |event| event.fetch("kind") }
      repair = events.find { |event| event.fetch("kind") == "repair" }
      assert_equal Digest::SHA256.hexdigest("bad\n"), repair.dig("payload", "changes", 0, "before_hash")
      assert_equal Digest::SHA256.hexdigest("good\n"), repair.dig("payload", "changes", 0, "after_hash")
      assert_match(/^--- a\/sample.txt/, repair.dig("payload", "diff"))
    end
  end

  def test_sacred_law_escalates_without_writing
    with_workspace do |root|
      File.write(File.join(root, "sample.txt"), "bad\n")
      kernel = K.new(root:)
      outcome = kernel.fix(root, laws: [law(sacred: true)])

      assert_equal :escalated, outcome.state
      assert_equal "bad\n", File.read(File.join(root, "sample.txt"))
      assert_includes kernel.verify_log!.map { |event| event.fetch("kind") }, "escalation"
    end
  end

  def test_manifest_read_permission_cannot_be_used_for_writes
    with_workspace(access: "read") do |root|
      File.write(File.join(root, "sample.txt"), "bad\n")
      kernel = K.new(root:)
      outcome = kernel.fix(root, laws: [law(replacement: "good\n")])

      assert_equal :escalated, outcome.state
      assert_equal "bad\n", File.read(File.join(root, "sample.txt"))
      assert_includes kernel.verify_log!.map { |event| event.fetch("kind") }, "boundary_denied"
    end
  end

  def test_replay_returns_the_complete_run_for_a_sequence
    with_workspace do |root|
      File.write(File.join(root, "sample.txt"), "good\n")
      kernel = K.new(root:)
      outcome = kernel.fix(root, laws: [])
      event = kernel.verify_log!.find { |row| row["kind"] == "terminal" }

      replay = K.replay_events(root:, seq: event.fetch("seq"))
      assert_equal outcome.run_id, replay.fetch("run_id")
      assert_equal "converged", replay.fetch("events").last.dig("payload", "state")
    end
  end

  def test_append_reuses_the_verified_head_without_rescanning_history
    with_workspace do |root|
      kernel = K.new(root:)
      kernel.observe(root)

      K.stub(:read_log_io, ->(_file) { flunk("append rescanned the complete ledger") }) do
        kernel.observe(root)
      end

      assert_equal 2, kernel.verify_log!.length
    end
  end

  def test_append_validates_records_added_by_another_kernel_instance
    with_workspace do |root|
      first = K.new(root:)
      second = K.new(root:)

      first.observe(root)
      second.observe(root)
      first.observe(root)

      events = first.verify_log!
      assert_equal [1, 2, 3], events.map { |event| event.fetch("seq") }
    end
  end

  def test_append_refuses_a_truncated_ledger
    with_workspace do |root|
      kernel = K.new(root:)
      kernel.observe(root)
      File.write(kernel.log_path, "")

      assert_raises(K::LedgerCorruption) { kernel.observe(root) }
    end
  end

  def test_full_verification_refuses_an_incomplete_final_record
    with_workspace do |root|
      kernel = K.new(root:)
      kernel.observe(root)
      contents = File.binread(kernel.log_path)
      File.binwrite(kernel.log_path, contents.delete_suffix("\n"))

      assert_raises(K::LedgerCorruption) { kernel.verify_log! }
    end
  end

  def test_modified_hash_chain_is_refused
    with_workspace do |root|
      File.write(File.join(root, "sample.txt"), "good\n")
      kernel = K.new(root:)
      kernel.observe(root)
      path = kernel.log_path
      content = File.read(path)
      File.write(path, content.sub('"kind":"observation"', '"kind":"changed"'))

      assert_raises(K::LedgerCorruption) { kernel.verify_log! }
    end
  end
end
