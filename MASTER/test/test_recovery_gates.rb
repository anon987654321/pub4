# frozen_string_literal: true

# Required proof gates before folding FixLoop / RepairLoop / RunJournal into
# Fix::Kernel. See MASTER/docs/fix_coordinator_map.md.
#
# These are intentionally explicit pending tests, not proof that recovery works.
# A merge is blocked until each skip is wired to the production path, made red
# by a planted defect, then green after the repair.

require "test_helper"

module Master
  module Fix
    class RecoveryGatesTest < Minitest::Test
      def test_1_staging_and_rollback_restores_byte_identical_state
        skip "wire an aborted Fix::Transaction to a scratch-tree byte snapshot"
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
