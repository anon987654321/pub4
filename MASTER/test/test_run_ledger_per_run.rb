# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# A long MASTER session runs /fix many times in one process: a file rejected twice in one run
# must be tried again by the next, while a --max-files override set for the run survives.
class TestRunLedgerPerRun < Minitest::Test
  Ledger = Master::Fix::RunLedger

  def teardown = Ledger.reset!

  def test_a_new_run_forgets_the_last_runs_rejections_and_keeps_its_file_cap
    2.times { Ledger.reject(:new_violations, file: "lib/a.rb") }
    assert Ledger.file_done?("lib/a.rb")
    Ledger.max_files = 5

    Dir.mktmpdir { |root| Master::Fix::RunBudget.begin_run(root:, max_passes: 1) }

    refute Ledger.file_done?("lib/a.rb")
    assert_equal 5, Ledger.max_files
  ensure
    Master::Fix::RunBudget.finish_run
  end
end
