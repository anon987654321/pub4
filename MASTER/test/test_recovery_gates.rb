# frozen_string_literal: true

# Required proof gates before folding FixLoop / RepairLoop / RunJournal into
# Fix::Kernel. See MASTER/docs/fix_coordinator_map.md.
#
# These are intentionally explicit pending tests, not proof that recovery works.
# A merge is blocked until each skip is wired to the production path, made red
# by a planted defect, then green after the repair.

require "test_helper"
require "tmpdir"
require "open3"
require "rbconfig"
require "json"
require_relative "../lib/fix/transaction"
require_relative "../lib/fix/mission"
require_relative "../lib/fix/checkpoint"

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
          Process.wait(writer.pid)
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
            Process.wait(writer.pid) rescue nil
          end
          [stdin, stdout, stderr].compact.each { |io| io.close unless io.closed? }
        end
      end

      def test_3_journal_deletion_is_reconstructible_from_git_and_checkpoint
        skip "delete .master/fix_runs.json and its lock during a pass; reconstruct from Git and Checkpoint"
      end

      def test_4_file_budget_exhaustion_trips_collapse_guard
        skip "wire RepairLoop / RunLedger file budget to the collapse_guard terminal state"
      end

      def test_5_ledger_records_per_file_reason_when_nothing_is_fixed
        skip "wire Fix::RunLedger and assert one authoritative per-file refusal/budget/verification reason"
      end

      def test_6_cli_paths_emit_identical_receipts_before_and_after_fold
        skip "compare durable receipts for bin/master and every production /fix CLI adapter before any fold"
      end
    end
  end
end
