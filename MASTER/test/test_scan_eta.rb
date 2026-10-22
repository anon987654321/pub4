# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/scan/progress_reporter"

# The scan ETA follows the recent rate, so a slow stretch after a fast one is estimated as slow.
class TestScanEta < Minitest::Test
  # The reporter's ETA alone.
  class Reporter
    include Master::Fix::Scan::ProgressReporter

    def initialize = @scan_progress = {}
    def eta(done, elapsed) = recent_eta(done:, total: 200, elapsed:)
  end

  def test_a_slow_stretch_after_a_fast_one_is_estimated_at_the_slow_rate
    reporter = Reporter.new
    (1..100).each { |done| reporter.eta(done, done * 0.1) }
    last = nil
    (101..160).each { |done| last = reporter.eta(done, 10 + ((done - 100) * 10)) }

    assert_equal 400, last, "40 files left at 10 seconds a file"
  end

  def test_no_estimate_before_a_second_file
    assert_nil Reporter.new.eta(1, 5.0)
  end
end
