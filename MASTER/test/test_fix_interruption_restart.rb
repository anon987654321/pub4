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
      File.write(File.join(root, ".pub4"), <<~YAML)
        schema: 1
        tree: restart
        allows:
          master: read_write
        adapters: []
      YAML
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
        mission_handle = Master::Fix::Mission.new(root:).start_or_resume!(
          goal: "fix MASTER after restart", scope: File.join(root, "MASTER"), origin: "manual"
        )
        mission = mission_handle.record
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

  def test_public_fix_run_rolls_back_and_resumes_after_process_death
    Dir.mktmpdir("fix-public-run-restart") do |root|
      sample = File.join(root, "sample.rb")
      marker = File.join(root, "crash-ready.json")
      File.write(sample, "before\n")
      FileUtils.mkdir_p(File.join(root, "data"))
      File.write(
        File.join(root, "data", "soul.yml"),
        "absolute:\n  sacred_paths:\n    - data/soul.yml\n"
      )
      git_status = system(
        "git", "-C", root, "init", "-q", "--initial-branch=main",
        out: File::NULL, err: File::NULL
      )
      assert git_status, "the process fixture must be a real Git checkout"
      File.write(File.join(root, ".pub4"), <<~YAML)
        schema: 1
        tree: #{File.basename(root).downcase}
        allows:
          master: read_write
        adapters: []
      YAML
      File.write(File.join(root, ".git", "info", "exclude"), ".master/\nruntime/\n")

      support = <<~'RUBY'
        require "json"
        require "master"
        require "operator/check_chain"
        require "fix/transaction"
        require "fix/run_journal"
        require "fix/mission"
        require "fix/checkpoint"
        require "fix/fix_loop"
        require "fix/repair_loop"

        Operator::CheckChain.define_singleton_method(:baseline) { |**| {} }

        class RestartProbeScanner
          def scan(path, laws: nil)
            findings = if ENV["MASTER_FIX_CRASH_PROBE"] == "1" && File.basename(path) == "sample.rb"
              [{ law: "LONG_LINE", line: 1, message: "controlled interrupted repair", severity: :warning }]
            else
              []
            end
            Master::Result.ok(findings)
          end
        end

        class RestartProbeAgent
          Breaker = Struct.new(:ignored) do
            def open_models = []
            def open?(_model_id) = false
          end

          def circuit_breaker = Breaker.new(nil)
          def model = "stub-model"
          def ask(_prompt) = "unused by the controlled transaction barrier"
        end

        class RestartProbeGit
          def changed_paths = []
          def commit(_message, paths:) = nil
        end

        def build_restart_probe_loop(root)
          law = Struct.new(:id, :severity).new("LONG_LINE", :warning)
          Master::Fix::FixLoop.new(
            laws: [law], agent: RestartProbeAgent.new, scanner: RestartProbeScanner.new,
            root:, bus: nil, git: RestartProbeGit.new
          )
        end

        def quiet_outcome_guidance(loop)
          loop.define_singleton_method(:outcome_guidance) do |target:, incremental:|
            { incremental: false, prediction: nil }
          end
          loop
        end
      RUBY

      writer = support + <<~'RUBY'
        root, marker = ARGV
        ENV["MASTER_FIX_CRASH_PROBE"] = "1"
        loop = quiet_outcome_guidance(build_restart_probe_loop(root))

        checkpoint = lambda do |id:, root:, files:|
          Master::Fix::Checkpoint.new(
            root:, dir: File.join(root, ".master", "checkpoints")
          ).create(label: "mission-#{id}", files:)
        end
        mission = Master::Fix::Mission.new(root:, checkpoint:).start!(
          goal: "fix #{root}", scope: root, origin: "supervisor"
        )
        mission.checkpoint!(files: ["sample.rb"])

        # Keep the production pass runner, real transaction, repair factory and
        # public FixLoop#run. Only the deterministic repair's final write is a
        # barrier, so SIGKILL lands after the active transaction and changed bytes
        # are both durable but before pass delivery/terminalization.
        Master::Fix::Kernel::RepairAdapter.define_method(:fix_batch) do |violations, *args, **options|
          violation = Array(violations).first or raise "crash probe reached repair without a finding"
          path = File.expand_path(violation[:file].to_s, root)
          File.write(path, "partial mutation\n")

          journal = loop.instance_variable_get(:@run_journal)
          run_record = journal.history.last
          active_pass = journal.active_pass(run_record)
          transaction_id = active_pass.fetch("transaction_id")
          kernel = loop.instance_variable_get(:@kernel)
          File.write(marker, JSON.generate(
            "run_id" => run_record.fetch("id"),
            "coordinator_run_id" => kernel.instance_variable_get(:@current_run_id),
            "mission_id" => mission.id,
            "transaction_id" => transaction_id,
            "pid" => Process.pid,
            "transaction_persisted" => Master::Fix::Transaction::Recovery.persisted?(
              root:, id: transaction_id
            )
          ))
          sleep 60
        end

        loop.run(
          root, max_passes: 2, budget_seconds: 60,
          incremental: false, requested: false
        )
      RUBY

      pid = Process.spawn(
        RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", writer, root, marker,
        out: File::NULL, err: File::NULL, chdir: Master::ROOT
      )
      begin
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
        sleep 0.03 until File.file?(marker) || Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        assert File.file?(marker), "public FixLoop#run did not reach its controlled pass boundary"
        marker_record = JSON.parse(File.read(marker))
        assert_equal true, marker_record.fetch("transaction_persisted"),
                     "the writer must die after its transaction manifest is durable"
        Process.kill("KILL", pid)
        _waited_pid, child_status = Process.wait2(pid)
        refute child_status.success?, "the writer must die before FixLoop terminalization"
      ensure
        begin
          Process.kill("KILL", pid)
          Process.wait(pid)
        rescue Errno::ESRCH, Errno::ECHILD
          nil
        end
      end

      restart = support + <<~'RUBY'
        root, old_run_id, old_coordinator_id, old_transaction_id = ARGV
        loop = quiet_outcome_guidance(build_restart_probe_loop(root))
        result = loop.run(
          root, max_passes: 2, budget_seconds: 60,
          incremental: false, requested: false
        )

        journal = loop.instance_variable_get(:@run_journal)
        run = journal.history(limit: Master::Fix::RunJournal::MAX_RUNS).find do |row|
          row["id"] == old_run_id
        end
        mission = Master::Fix::Mission.current(root:)
        kernel_events = loop.kernel.verify_log!
        coordinator = kernel_events.find do |row|
          row["kind"] == "coordinator_terminal" && row["run_id"] == old_coordinator_id
        end

        puts JSON.generate(
          "run_id" => run && run.fetch("id"),
          "run_state" => run && run.fetch("state"),
          "resume_count" => run && run.fetch("resume_count", 0),
          "sample" => File.read(File.join(root, "sample.rb")),
          "mission_id" => mission.fetch("id"),
          "mission_goal" => mission.fetch("goal"),
          "mission_scope" => mission.fetch("scope"),
          "checkpoint_id" => mission.dig("checkpoint", "id"),
          "checkpoint_sample" => File.read(
            File.join(root, ".master", "checkpoints", mission.dig("checkpoint", "id"), "sample.rb")
          ),
          "transaction_persisted" => Master::Fix::Transaction::Recovery.persisted?(
            root:, id: old_transaction_id
          ),
          "coordinator_state" => coordinator && coordinator.dig("payload", "state"),
          "coordinator_recovered" => coordinator && coordinator.dig("payload", "recovered"),
          "result_category" => result.respond_to?(:category) ? result.category.to_s : nil
        )
      RUBY
      output, restart_status = Open3.capture2e(
        RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", restart, root,
        marker_record.fetch("run_id"), marker_record.fetch("coordinator_run_id"),
        marker_record.fetch("transaction_id"), chdir: Master::ROOT
      )
      assert restart_status.success?, "public FixLoop restart failed: #{output}"
      receipt = JSON.parse(output.lines.last)

      assert_equal marker_record.fetch("run_id"), receipt.fetch("run_id")
      assert_operator receipt.fetch("resume_count"), :>=, 1,
                      "the durable run must be resumed, not silently replaced"
      assert_equal "before\n", receipt.fetch("sample"), "startup recovery must roll back the dead pass"
      assert_equal marker_record.fetch("mission_id"), receipt.fetch("mission_id")
      assert_equal "fix #{root}", receipt.fetch("mission_goal")
      assert_equal ".", receipt.fetch("mission_scope")
      assert_equal "before\n", receipt.fetch("checkpoint_sample"),
                   "the independent Mission checkpoint must survive process death"
      refute receipt.fetch("transaction_persisted")
      assert_equal "unknown_outcome", receipt.fetch("coordinator_state")
      assert_equal true, receipt.fetch("coordinator_recovered")
    end
  end

end
