# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# A suite that reports 106 and runs 10 is an instrument reporting on itself.
#
# MASTER's `rake test` ran test_dilla.rb for months. Deleting that file dropped
# the aggregate by ten runs, not by its hundred and six — so ninety-six tests
# never executed, and the nine failures among them were invisible to every gate.
# Nothing detected it, because nothing compared a file's own run count to what
# it contributed to the suite.
#
# Slow by construction: it runs each file in its own process. Opt in with
# SUITE_AUDIT=1, or a full `rake test` would fork the whole suite per file.
class SuiteActuallyRunsTest < Minitest::Test
  RUN_COUNT = /(\d+) runs?, \d+ assertions/

  def setup
    skip "set SUITE_AUDIT=1 — one process per test file" unless ENV["SUITE_AUDIT"] == "1"
  end

  # Redirected to a file rather than captured through Open3: a forked test file
  # that closes its own streams raced capture2e's reader thread, and the audit
  # errored instead of reporting.
  def standalone_runs(path)
    log = File.join(Dir.tmpdir, "suite_audit_#{File.basename(path, '.rb')}.log")
    system(RbConfig.ruby, "-Itest", "-Ilib", path, out: log, err: log, chdir: Master::ROOT)
    File.read(log)[RUN_COUNT, 1]&.to_i
  ensure
    File.delete(log) if log && File.exist?(log)
  end

  # Each file costs a process, so serially this outran a half-hour timeout and
  # reported nothing. `system` waits outside the GVL, so threads spend the wait
  # concurrently; four keeps the box usable while it runs.
  def in_parallel(items, width: 4)
    items.each_slice((items.size / width.to_f).ceil)
         .map { |group| Thread.new { group.map { |item| yield(item) } } }
         .flat_map(&:value).compact
  end

  # Every file the Rakefile's FileList picks up, asked what it reports alone.
  # A file whose standalone count is zero is loaded and never executed; that is
  # the shape test_dilla had inside the aggregate.
  def test_no_test_file_reports_zero_runs_on_its_own
    files = Dir.glob(File.join(Master::ROOT, "test", "test_*.rb"))
                .reject { |f| File.basename(f) == File.basename(__FILE__) }
                .reject { |f| %w[test_browser.rb test_web_http.rb test_helper.rb].include?(File.basename(f)) }
    refute_empty files, "the glob that finds nothing is the failure this test exists to prevent"

    silent = in_parallel(files) { |f| standalone_runs(f).to_i.positive? ? nil : f }

    assert_empty silent.map { |f| File.basename(f) },
                 "these files contribute no runs when executed alone — they are loaded, not run"
  end
end
