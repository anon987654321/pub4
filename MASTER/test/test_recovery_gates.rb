# frozen_string_literal: true

# Required proof gates before folding FixLoop / RepairLoop / RunJournal into
# Fix::Kernel. See MASTER/docs/fix_coordinator_map.md.
#
# These are merge gates, not proof that recovery works. Each real test must
# execute against the production recovery path and be run before a coordinator
# fold. Any remaining skip must be wired, made red by a planted defect, then green.

require "test_helper"
require "tmpdir"
require_relative "../lib/fix/transaction"

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
        skip "wire Fix::Mission lease and .master/mission.json to a child-process restart"
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
