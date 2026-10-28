# frozen_string_literal: true

# Required proof gates before folding FixLoop / RepairLoop / RunJournal into
# Fix::Kernel. See MASTER/docs/fix_coordinator_map.md.
#
# Each gate must exercise production code with planted failure conditions. A
# gate is not closed merely because its test is authored: run it on pinned Ruby,
# observe the regression, and retain the passing evidence before any fold.

require "test_helper"
require "tmpdir"
require "open3"
require "rbconfig"
require "json"
require_relative "../lib/fix/transaction"
require_relative "../lib/fix/mission"
require_relative "../lib/fix/checkpoint"
require_relative "../lib/fix/run_journal"
require_relative "../lib/fix/repair_loop"
require_relative "../lib/fix/fix_loop"
require_relative "../lib/cli/command_registry"

module Master
  module Fix
    class RecoveryGatesTest < Minitest::Test
      def test_1_staging_and_rollback_restores_byte_identical_state
        Dir.mktmpdir("fix-recovery-gate-bytes") do |root|
          binary_path = File.join(root, "binary.dat")
          created_path = File.join(root, "created-during-pass.txt")
          original_bytes = [0x00, 0xFF, 0x80, 0x41, 0x0A].pack("C*")
          original_mode = 0o750
          File.binwrite(binary_path, original_bytes)
          File.chmod(original_mode, binary_path)
          original_stat = File.stat(binary_path)

          transaction = Master::Fix::Transaction.new(
            root:,
            paths: [binary_path, created_path],
            id: "recovery-gate-byte-restore"
          )
          transaction.begin!

          File.binwrite(binary_path, "overwritten text that is not valid binary parity")
          File.chmod(0o600, binary_path)
          File.write(created_path, "created by the aborted pass\n")
          transaction.observe!

          result = transaction.rollback!

          assert result.ok?, -> { result.message.to_s }
          assert_equal original_bytes, File.binread(binary_path)
          assert_equal original_mode, File.stat(binary_path).mode & 0o777
          assert_equal original_stat.uid, File.stat(binary_path).uid
          assert_equal original_stat.gid, File.stat(binary_path).gid
          refute File.exist?(created_path), "rollback must delete a file created by the aborted pass"
          refute transaction.active?
        end
      end

      def test_2_mission_survives_process_kill_and_reports_remaining_work
        Dir.mktmpdir("fix-recovery-gate-mission") do |root|
          scope = File.join(root, "MASTER")
          FileUtils.mkdir_p(scope)
          File.write(File.join(root, "sample.rb"), "checkpoint survives process death\n")
          goal = "resume after a killed /fix worker"

          checkpoint_writer = lambda do |id:, root:, files:|
            Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints"))
                                 .create(label: "mission-#{id}", files:)
          end
          child = <<~'RUBY'
            require "master"
            require "json"
            require "fix/mission"
            require "fix/checkpoint"

            root, scope, goal = ARGV
            checkpoint_writer = lambda do |id:, root:, files:|
              Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints"))
                                   .create(label: "mission-#{id}", files:)
            end
            mission = Master::Fix::Mission.new(root:, checkpoint: checkpoint_writer).start!(
              goal:, scope:, origin: "manual"
            )
            mission.checkpoint!(files: ["sample.rb"])
            puts JSON.generate(
              "id" => mission.id,
              "checkpoint_id" => mission.record.dig("checkpoint", "id"),
              "pid" => Process.pid
            )
            STDOUT.flush
            sleep 60
          RUBY

          stdin, stdout, stderr, writer = Open3.popen3(
            RbConfig.ruby, "-I", File.join(Master::ROOT, "lib"), "-e", child,
            root, scope, goal, chdir: Master::ROOT
          )
          stdin.close
          ready = IO.select([stdout], nil, nil, 10)
          refute_nil ready, "mission child did not publish its durable checkpoint receipt"
          receipt_line = stdout.gets
          refute_nil receipt_line, -> { stderr.read }
          child_receipt = JSON.parse(receipt_line)
          assert_equal writer.pid, child_receipt.fetch("pid")
          Process.kill("KILL", writer.pid)
          writer.value
          writer = nil

          resumed = Master::Fix::Mission.new(root:, checkpoint: checkpoint_writer).start_or_resume!(
            goal:, scope:, origin: "manual"
          )
          saved = Master::Fix::Mission.current(root:)

          assert_equal child_receipt.fetch("id"), resumed.id, "restart must resume the original objective"
          assert_equal "running", resumed.record.fetch("state")
          assert_operator resumed.record.fetch("attempt_count"), :>=, 2
          assert_equal child_receipt.fetch("checkpoint_id"), saved.dig("checkpoint", "id")
          assert_equal "checkpoint survives process death\n",
                       File.read(File.join(root, ".master", "checkpoints", child_receipt.fetch("checkpoint_id"), "sample.rb"))
        ensure
          if writer
            Process.kill("KILL", writer.pid) rescue nil
            writer.value rescue nil
          end
          [stdin, stdout, stderr].compact.each { |io| io.close unless io.closed? }
        end
      end

      def test_3_source_recovery_survives_journal_deletion_using_git_and_checkpoint
        Dir.mktmpdir("fix-recovery-gate-journal-loss") do |root|
          FileUtils.mkdir_p(File.join(root, "MASTER"))
          tracked_path = File.join(root, "tracked.rb")
          untracked_path = File.join(root, "untracked.rb")
          tracked_bytes = "tracked baseline from Git\n".b
          checkpoint_bytes = "untracked baseline from Checkpoint\n".b

          git = lambda do |*args|
            output, status = Open3.capture2e("git", *args, chdir: root)
            assert status.success?, "git #{args.join(' ')} failed: #{output}"
            output
          end
          git.call("init", "--quiet")
          File.binwrite(tracked_path, tracked_bytes)
          git.call("add", "--", "tracked.rb")
          git.call("-c", "user.name=Recovery Gate", "-c", "user.email=recovery-gate@example.invalid",
                   "commit", "--quiet", "-m", "recovery baseline")
          File.binwrite(untracked_path, checkpoint_bytes)

          checkpoint_store = Master::Fix::Checkpoint.new(root:, dir: File.join(root, ".master", "checkpoints"))
          checkpoint = checkpoint_store.create(label: "journal-loss", files: ["untracked.rb"])
          journal = Master::Fix::RunJournal.new(root:)
          original_run = journal.start_or_resume(
            target: File.join(root, "MASTER"),
            files: [tracked_path, untracked_path],
            max_passes: 2,
            budget_seconds: 60
          )

          File.binwrite(tracked_path, "modified tracked source\n")
          File.binwrite(untracked_path, "modified untracked source\n")
          journal_path = File.join(root, ".master", "fix_runs.json")
          lock_path = File.join(root, ".master", "fix_runs.lock")
          File.delete(journal_path)
          File.delete(lock_path)

          # The lifecycle journal is run metadata, not the only copy of source
          # state: Git restores tracked files; the independent Checkpoint restores
          # pre-pass files Git cannot recover (including new/untracked paths).
          git.call("checkout", "--", "tracked.rb")
          checkpoint_store.restore(checkpoint.fetch("id"))

          assert_equal tracked_bytes, File.binread(tracked_path)
          assert_equal checkpoint_bytes, File.binread(untracked_path)

          # With the metadata deliberately missing, a fresh journal must create a
          # new run, not fabricate a successful resume or reuse the forgotten ID.
          replacement = Master::Fix::RunJournal.new(root:).start_or_resume(
            target: File.join(root, "MASTER"),
            files: [tracked_path, untracked_path],
            max_passes: 2,
            budget_seconds: 60
          )
          refute_equal original_run.fetch("id"), replacement.fetch("id")
          refute replacement.fetch("resumed")
          assert_equal "active", replacement.fetch("state")
        end
      end

      def test_4_budget_exhaustion_is_recorded_and_collapse_guard_refuses_mutation
        previous_path = ENV["MASTER_FIX_REFUSALS_PATH"]
        Dir.mktmpdir("fix-recovery-gate-budget-collapse") do |root|
          refusal_path = File.join(root, "fix_refusals.jsonl")
          ENV["MASTER_FIX_REFUSALS_PATH"] = refusal_path
          Refusals.begin_run!
          RunLedger.reset!

          path = File.join(root, "sample.rb")
          original = (1..18).map { |line| "def example_#{line}; value = #{line}; end\n" }.join
          File.binwrite(path, original)
          adapter = Master::Fix::RepairLoop.allocate
          law = Struct.new(:id).new("RECOVERY_GATE")
          adapter.instance_variable_set(:@law, law)
          adapter.instance_variable_set(:@root, root)
          adapter.instance_variable_set(:@bus, nil)
          adapter.instance_variable_set(:@visual_custody, nil)

          timed_out = RunLedger.stub(:file_budget_s, 0.005) do
            adapter.send(:start_file_budget)
            adapter.send(:within_file_budget, { file: path }) do
              sleep 0.03
              "would have been a proposal"
            end
          end

          assert_nil timed_out
          assert adapter.instance_variable_get(:@file_timed_out)
          assert_equal path, RunLedger.timeouts.fetch(0).fetch(0)
          assert_in_delta 0.005, RunLedger.timeouts.fetch(0).fetch(1), 0.0001
          assert_includes RunLedger.summary_lines.join("\n"), "file budget spent on 1 file(s): sample.rb"

          violation = { file: path, law: law.id, line: 8, severity: :warning }
          capture_io do
            refute adapter.send(:apply, path, "UNCHANGED", violation)
          end

          assert_equal original, File.binread(path), "the collapse guard must refuse before a source rewrite"
          assert_equal 1, RunLedger.reasons.fetch("collapsed_content")
          refusal = JSON.parse(File.readlines(refusal_path).last)
          assert_equal "collapse", refusal.fetch("gate")
          assert_equal "RECOVERY_GATE", refusal.fetch("law")
          assert_match(/proposal is the refusal word/, refusal.fetch("reason"))
        ensure
          ENV["MASTER_FIX_REFUSALS_PATH"] = previous_path
          Refusals.begin_run!
          RunLedger.reset!
        end
      end

      def test_5_zero_repair_result_carries_one_authoritative_per_file_refusal
        previous_path = ENV["MASTER_FIX_REFUSALS_PATH"]
        previous_retry = ENV["MASTER_FIX_RETRY"]
        Dir.mktmpdir("fix-recovery-gate-zero-repair") do |root|
          refusal_path = File.join(root, "fix_refusals.jsonl")
          ENV["MASTER_FIX_REFUSALS_PATH"] = refusal_path
          ENV["MASTER_FIX_RETRY"] = "0"
          Refusals.begin_run!
          RunLedger.reset!

          path = File.join(root, "sample.rb")
          original = (1..18).map { |line| "def example_#{line}; value = #{line}; end\n" }.join
          File.binwrite(path, original)
          adapter = Master::Fix::RepairLoop.allocate
          law = Struct.new(:id).new("RECOVERY_GATE")
          adapter.instance_variable_set(:@law, law)
          adapter.instance_variable_set(:@agent, Object.new)
          adapter.instance_variable_set(:@scanner, Object.new)
          adapter.instance_variable_set(:@root, root)
          adapter.instance_variable_set(:@bus, nil)
          adapter.instance_variable_set(:@learnings, nil)
          adapter.instance_variable_set(:@committer, nil)
          adapter.instance_variable_set(:@visual_custody, nil)

          adapter.define_singleton_method(:needs_a_person?) { |_violation| false }
          adapter.define_singleton_method(:autofix_allowed?) { |_violation| true }
          adapter.define_singleton_method(:fingerprint_matches?) { |_violation| true }
          adapter.define_singleton_method(:note_unverified_fix) { |_violation| nil }
          adapter.define_singleton_method(:request_fix) { |_violation| "UNCHANGED" }
          adapter.define_singleton_method(:reflexion_verify) { |_violation, source| source }
          adapter.define_singleton_method(:consensus_approves?) { |_violation, _source| true }

          violation = { file: path, law: law.id, line: 8, severity: :warning }
          result = RunBudget.stub(:law_limit_exceeded?, false) do
            RunBudget.stub(:run_spend, [0.0, 0]) do
              RunBudget.stub(:note_law_cost, nil) do
                ToolBreaker.stub(:state_of, {}) do
                  ToolBreaker.stub(:refuse?, false) do
                    ToolBreaker.stub(:record, nil) do
                      BestOfN.stub(:active?, false) do
                        capture_io do
                          adapter.run_once([path], external_violations: [violation])
                        end
                      end
                    end
                  end
                end
              end
            end
          end

          assert_equal 0, result.fetch(:fixed)
          assert_equal :stuck, result.fetch(:status), "no accepted repair must not be reported as fixed or clean"
          assert_equal({ rejected: 1 }, result.fetch(:breakdown))
          assert_equal 1, RunLedger.reasons.fetch("collapsed_content")
          assert_equal 1, RunLedger.rejects_for(path)
          assert_equal original, File.binread(path)
          refusal = JSON.parse(File.readlines(refusal_path).last)
          assert_equal "collapse", refusal.fetch("gate")
          assert_equal "sample.rb", refusal.fetch("file")
          assert_equal "RECOVERY_GATE", refusal.fetch("law")
          assert_match(/proposal is the refusal word/, refusal.fetch("reason"))
        ensure
          ENV["MASTER_FIX_REFUSALS_PATH"] = previous_path
          ENV["MASTER_FIX_RETRY"] = previous_retry
          Refusals.begin_run!
          RunLedger.reset!
        end
      end

      def build_receipt_fixture(root)
        FileUtils.mkdir_p(File.join(root, "MASTER"))
        Dir.mkdir(File.join(root, ".git"))
        kernel = Master::Fix::Kernel.new(root: File.join(root, "MASTER"), actor: "receipt-parity")
        loop = Master::Fix::FixLoop.allocate
        loop.instance_variable_set(:@kernel, kernel)
        loop.instance_variable_set(:@run_journal, kernel.lifecycle_journal)
        loop.instance_variable_set(:@bus, nil)
        loop.define_singleton_method(:run_unlocked) do |target, max_passes:, budget_seconds:, incremental:, requested:|
          journal = @run_journal.start_or_resume(
            target:, files: [], max_passes:, budget_seconds:
          )
          @kernel.bind_fix_run(
            adapter: self, run_id: journal.fetch("id"), target:,
            max_passes:, budget_seconds:, requested:
          )
          @kernel.record_repair_outcome(
            law: "RECOVERY_GATE", status: :fixed, fixed: 1, breakdown: { applied: 1 }
          )
          @last_terminal_state = :done
          Master::Result.ok("DONE: receipt parity fixture")
        end
        loop.define_singleton_method(:publish_pending!) { true }
        [kernel, loop]
      end

      def receipt_signature(kernel)
        events = kernel.verify_log!
        start = events.find { |row| row.fetch("kind") == "coordinator_started" }
        refute_nil start, "no durable coordinator start receipt"
        run_id = start.fetch("run_id")
        repair = events.find { |row| row.fetch("kind") == "repair_pass" && row.fetch("run_id") == run_id }
        terminal = events.find do |row|
          row.fetch("kind") == "coordinator_terminal" && row.fetch("run_id") == run_id
        end
        refute_nil repair, "no durable repair receipt linked to the coordinator run"
        refute_nil terminal, "no durable coordinator terminal receipt"
        assert_equal run_id, repair.fetch("run_id")
        assert_equal run_id, terminal.fetch("run_id")
        [
          [
            start.fetch("kind"), start.dig("payload", "target"),
            start.dig("payload", "requested"), start.dig("payload", "max_passes"),
            start.dig("payload", "budget_seconds")
          ],
          [
            repair.fetch("kind"), repair.dig("payload", "law"),
            repair.dig("payload", "status"), repair.dig("payload", "fixed"),
            repair.dig("payload", "breakdown")
          ],
          [
            terminal.fetch("kind"), terminal.dig("payload", "state"),
            terminal.dig("payload", "result")
          ]
        ]
      end

      def test_6_public_fix_and_command_registry_adapter_emit_the_same_receipt_contract
        Dir.mktmpdir("fix-recovery-gate-receipt-direct") do |direct_root|
          direct_kernel, direct_loop = build_receipt_fixture(direct_root)
          direct_result = direct_loop.run(
            File.join(direct_root, "MASTER"), max_passes: 2, budget_seconds: 60,
            incremental: false, requested: true
          )
          assert direct_result.ok?, direct_result.message
          direct_signature = receipt_signature(direct_kernel)

          Dir.mktmpdir("fix-recovery-gate-receipt-cli") do |cli_root|
            cli_kernel, cli_loop = build_receipt_fixture(cli_root)
            trace = Struct.new(:failures, :summary) do
              def clean? = true
            end.new([], "controlled trace clean")
            # The public CommandRegistry /fix pre/post boundary and Kernel receipts are real;
            # only Pipeline::Pass is replaced by a bounded fixture so no model or tree repair runs.
            run_pass = lambda do |dependencies, **options|
              resolved_target = File.expand_path(options.fetch(:target), cli_root)
              result = dependencies.fetch(:fix_loop).run(
                resolved_target, max_passes: 2, budget_seconds: 60,
                incremental: false, requested: true
              )
              raise "controlled Kernel run failed: #{result.message}" unless result.ok?

              "review0: complete, controlled receipt fixture"
            end

            output = nil
            Master::Fix::RunBudget.stub(
              :with_shared_run, ->(**_options, &operation) { operation.call }
            ) do
              Master::Fix::WorkLane.stub(:refusal, ->(_target) { nil }) do
                Master::Fix::WorkLane.stub(:summary, "controlled work lane") do
                  Master::CLI::CommandRegistry.stub(:first_read, ->(**_options) { {} }) do
                    Master::CLI::CommandRegistry.stub(:execution_trace_scopes, ->(_target) { ["MASTER"] }) do
                      Master::CLI::CommandRegistry.stub(:steady_trace, ->(**_options) { trace }) do
                        Master::CLI::CommandRegistry.stub(:structural_review, ->(**_options) { nil }) do
                          Master::CLI::CommandRegistry.stub(:resume_from_residual, ->(_target) { nil }) do
                            Master::CLI::CommandRegistry.stub(:run_pass, run_pass) do
                              Operator::CheckChain.stub(:clear_verified_fix_snapshots!, -> {}) do
                                Operator::CheckChain.stub(:baseline_scope_key, ->(_target) { "MASTER" }) do
                                  Operator::CheckChain.stub(:baseline, ->(**_options) { { "lexical" => [], "source" => [] } }) do
                                    Operator::CheckChain.stub(:verify_fix, ->(**_options) { [0, []] }) do
                                      Operator::CheckChain.stub(:persist_verified_baselines!, ->(_targets) {}) do
                                        output = Master::CLI::CommandRegistry.dispatch_fix(
                                          scanner: Object.new, fix_loop: cli_loop, deliberation: nil,
                                          root: cli_root, bus: nil, ctx: { args: "--apply MASTER" }, swarm: nil
                                        )
                                      end
                                    end
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                  end
                end
              end
            end

            assert_match(/review0: complete/, output.to_s)
            cli_signature = receipt_signature(cli_kernel)
            assert_equal direct_signature, cli_signature,
                         "the public /fix command adapter must preserve the Kernel receipt contract"
          end
        end
      end
    end
  end
end
