# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require_relative "../lib/fix/transaction"
require_relative "../lib/fix/run_journal"
require_relative "../lib/fix/fix_loop"

# Process-boundary regression for /fix's durable lifecycle, not a full
# repository-wide repair trial: the writer is killed after real journal and
# transaction state record a partial mutation; restart executes FixLoop's
# startup recovery and reconciles the abandoned Kernel run receipt.
class TestFixInterruptionRestart < Minitest::Test
  def test_losing_run_journal_does_not_lose_mission_checkpoint_or_transaction_recovery
    Dir.mktmpdir("fix-journal-loss-restart") do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER"))
      sample = File.join(root, "sample.rb")
      marker = File.join(root, "crash-ready.json")
      File.write(sample, "before\n")

      child = <<~'RUBY'
        require "json"
        require "master"
        require "fix/transaction"
        require "fix/run_journal"
        require "fix/mission"
        require "fix/checkpoint"

        root, marker = ARGV
        sample = File.join(root, "sample.rb")
        checkpoint = lambda do |id:, root:, files:|
          Master::Fix::Checkpoint.new(
            root:, dir: File.join(root, ".master", "checkpoints")
          ).create(label: "mission-#{id}", files:)
        end
        mission = Master::Fix::Mission.new(root:, checkpoint:).start!(
          goal: "fix MASTER after restart", scope: File.join(root, "MASTER"), origin: "manual"
        )
        mission.checkpoint!(files: ["sample.rb"])
        kernel = Master::Fix::Kernel.new(root:, actor: "journal-loss-probe")
        coordinator_run_id = kernel.begin_coordinated_run(
          target: File.join(root, "MASTER"), max_passes: 2,
          budget_seconds: 60, requested: true
        )
        journal = Master::Fix::RunJournal.new(root:)
        run = journal.start_or_resume(
          target: File.join(root, "MASTER"), files: [sample], max_passes: 2, budget_seconds: 60
        )
        transaction = Master::Fix::Transaction.new(root:, paths: ["sample.rb"], id: "journal-loss-probe")
        transaction.begin!
        File.write(sample, "partial mutation\n")
        transaction.observe!
        journal.pass_start(run.fetch("id"), 1, transaction_id: "journal-loss-probe")
        File.write(marker, JSON.generate(
          "run_id" => run.fetch("id"), "coordinator_run_id" => coordinator_run_id,
          "mission_id" => mission.id, "pid" => Process.pid
        ))
        sleep 60
      RUBY

      pid = Process.spawn(
        RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", child, root, marker,
        out: File::NULL, err: File::NULL, chdir: Master::ROOT
      )
      begin
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
        sleep 0.02 until File.file?(marker) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        assert File.file?(marker), "writer did not reach its journal/mission/checkpoint checkpoint"
        marker_record = JSON.parse(File.read(marker))
        Process.kill("KILL", pid)
        _waited_pid, child_status = Process.wait2(pid)
        refute child_status.success?, "the writer must die before terminalization"
      ensure
        begin
          Process.kill("KILL", pid)
          Process.wait(pid)
        rescue Errno::ESRCH, Errno::ECHILD
          nil
        end
      end

      journal_path = File.join(root, ".master", "fix_runs.json")
      assert File.file?(journal_path), "the fixture must have persisted the journal before deletion"
      File.delete(journal_path)

      restart = <<~'RUBY'
        require "json"
        require "master"
        require "fix/transaction"
        require "fix/run_journal"
        require "fix/mission"
        require "fix/checkpoint"
        require "fix/fix_loop"

        root, old_coordinator_id = ARGV
        kernel = Master::Fix::Kernel.new(root:, actor: "journal-loss-probe")
        kernel.send(:reconcile_coordinated_runs!)
        coordinator = kernel.verify_log!.find do |row|
          row["kind"] == "coordinator_terminal" && row["run_id"] == old_coordinator_id
        end
        loop = Master::Fix::FixLoop.allocate
        loop.instance_variable_set(:@root, root)
        loop.instance_variable_set(:@transaction_root, root)
        loop.instance_variable_set(:@bus, nil)
        loop.send(:recover_stranded_transactions!)

        journal = Master::Fix::RunJournal.new(root:)
        run = journal.start_or_resume(
          target: File.join(root, "MASTER"),
          files: [File.join(root, "sample.rb")], max_passes: 2, budget_seconds: 60
        )
        mission = JSON.parse(File.read(File.join(root, ".master", "mission.json")))
        checkpoint = mission.fetch("checkpoint")
        checkpoint_file = File.join(
          root, ".master", "checkpoints", checkpoint.fetch("id"), "sample.rb"
        )
        puts JSON.generate(
          "run_id" => run.fetch("id"), "resumed" => run.fetch("resumed"),
          "sample" => File.read(File.join(root, "sample.rb")),
          "mission_id" => mission.fetch("id"), "mission_goal" => mission.fetch("goal"),
          "mission_scope" => mission.fetch("scope"), "mission_state" => mission.fetch("state"),
          "checkpoint_exists" => File.file?(checkpoint_file),
          "checkpoint_sample" => File.file?(checkpoint_file) ? File.read(checkpoint_file) : nil,
          "transaction_persisted" => Master::Fix::Transaction::Recovery.persisted?(
            root:, id: "journal-loss-probe"
          ),
          "coordinator_state" => coordinator && coordinator.dig("payload", "state"),
          "coordinator_recovered" => coordinator && coordinator.dig("payload", "recovered")
        )
      RUBY
      output, restart_status = Open3.capture2e(
        RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", restart, root,
        marker_record.fetch("coordinator_run_id"), chdir: Master::ROOT
      )
      assert restart_status.success?, "journal-loss restart failed: #{output}"
      receipt = JSON.parse(output.lines.last)

      refute receipt.fetch("resumed"), "without the deleted journal, a fresh run must not pretend to resume"
      refute_equal marker_record.fetch("run_id"), receipt.fetch("run_id")
      assert_equal marker_record.fetch("mission_id"), receipt.fetch("mission_id")
      assert_equal "fix MASTER after restart", receipt.fetch("mission_goal")
      assert_equal "MASTER", receipt.fetch("mission_scope")
      assert_includes %w[running waiting], receipt.fetch("mission_state")
      assert receipt.fetch("checkpoint_exists"), "the objective checkpoint must outlive run-journal deletion"
      assert_equal "before\n", receipt.fetch("checkpoint_sample")
      assert_equal "before\n", receipt.fetch("sample"), "transaction recovery must restore bytes without the run journal"
      refute receipt.fetch("transaction_persisted")
      assert_equal "unknown_outcome", receipt.fetch("coordinator_state")
      assert_equal true, receipt.fetch("coordinator_recovered")
    end
  end

  def test_killed_fix_pass_rolls_back_and_resumes_from_durable_state
    Dir.mktmpdir("fix-interruption-restart") do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER"))
      sample = File.join(root, "sample.rb")
      marker = File.join(root, "crash-ready.json")
      File.write(sample, "before\n")

      child = <<~'RUBY'
        require "json"
        require "master"
        require "fix/transaction"
        require "fix/run_journal"

        root, marker = ARGV
        sample = File.join(root, "sample.rb")
        kernel = Master::Fix::Kernel.new(root:, actor: "restart-probe")
        coordinator_run_id = kernel.begin_coordinated_run(
          target: File.join(root, "MASTER"), max_passes: 2,
          budget_seconds: 60, requested: false
        )
        journal = Master::Fix::RunJournal.new(root:)
        run = journal.start_or_resume(
          target: File.join(root, "MASTER"),
          files: [sample],
          max_passes: 2,
          budget_seconds: 60
        )
        transaction = Master::Fix::Transaction.new(
          root:, paths: ["sample.rb"], id: "restart-probe"
        )
        transaction.begin!
        File.write(sample, "partial mutation\n")
        transaction.observe!
        journal.pass_start(run.fetch("id"), 1, transaction_id: "restart-probe")
        File.write(marker, JSON.generate(
          "run_id" => run.fetch("id"), "coordinator_run_id" => coordinator_run_id,
          "pid" => Process.pid
        ))
        sleep 60
      RUBY

      pid = Process.spawn(
        RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", child, root, marker,
        out: File::NULL, err: File::NULL, chdir: Master::ROOT
      )
      begin
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
        sleep 0.02 until File.file?(marker) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        assert File.file?(marker), "child did not reach the durable in-pass checkpoint"
        marker_record = JSON.parse(File.read(marker))
        Process.kill("KILL", pid)
        _waited_pid, child_status = Process.wait2(pid)
        refute child_status.success?, "the writer must be interrupted, not allowed to finalize"
      ensure
        begin
          Process.kill("KILL", pid)
          Process.wait(pid)
        rescue Errno::ESRCH, Errno::ECHILD
          nil
        end
      end

      restart = <<~'RUBY'
        require "json"
        require "master"
        require "fix/transaction"
        require "fix/run_journal"
        require "fix/fix_loop"

        root = ARGV.fetch(0)
        kernel = Master::Fix::Kernel.new(root:, actor: "restart-probe")
        kernel.send(:reconcile_coordinated_runs!)
        coordinator_events = kernel.verify_log!
        coordinator = coordinator_events.find do |row|
          row["kind"] == "coordinator_terminal" &&
            row["run_id"] == ARGV.fetch(1)
        end

        loop = Master::Fix::FixLoop.allocate
        loop.instance_variable_set(:@root, root)
        loop.instance_variable_set(:@transaction_root, root)
        loop.instance_variable_set(:@bus, nil)

        # This is the same recovery sweep run_unlocked invokes before it opens
        # or resumes a journaled /fix pass.
        loop.send(:recover_stranded_transactions!)
        journal = Master::Fix::RunJournal.new(root:)
        loop.instance_variable_set(:@run_journal, journal)
        sample = File.join(root, "sample.rb")
        run = journal.start_or_resume(
          target: File.join(root, "MASTER"),
          files: [sample],
          max_passes: 2,
          budget_seconds: 60
        )
        start_pass = journal.next_pass(run)
        recovered = loop.send(
          :resume_active_transaction, journal:, run_id: run.fetch("id"), start_pass:
        )
        raise recovered.message if recovered.err?

        puts JSON.generate(
          "run_id" => run.fetch("id"),
          "resumed" => run.fetch("resumed"),
          "coordinator_run_id" => coordinator && coordinator.fetch("run_id"),
          "coordinator_state" => coordinator && coordinator.dig("payload", "state"),
          "coordinator_recovered" => coordinator && coordinator.dig("payload", "recovered"),
          "start_pass" => start_pass,
          "recovery_start" => recovered.value!,
          "content" => File.read(sample),
          "transaction_persisted" => Master::Fix::Transaction::Recovery.persisted?(
            root:, id: "restart-probe"
          )
        )
      RUBY
      output, restart_status = Open3.capture2e(
        RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", restart, root,
        marker_record.fetch("coordinator_run_id"), chdir: Master::ROOT
      )
      assert restart_status.success?, "restart process failed: #{output}"
      receipt = JSON.parse(output.lines.last)

      assert_equal marker_record.fetch("run_id"), receipt.fetch("run_id")
      assert_equal marker_record.fetch("coordinator_run_id"), receipt.fetch("coordinator_run_id")
      assert_equal "unknown_outcome", receipt.fetch("coordinator_state")
      assert_equal true, receipt.fetch("coordinator_recovered")
      assert receipt.fetch("resumed"), "the prior durable /fix run should resume"
      assert_equal 1, receipt.fetch("start_pass")
      assert_equal 1, receipt.fetch("recovery_start")
      assert_equal "before\n", receipt.fetch("content"), "partial writes must roll back after process death"
      refute receipt.fetch("transaction_persisted"), "recovery must settle and remove the stranded transaction"
    end
  end
end
