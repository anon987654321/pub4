# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/operator/check_runner"

# A running step reports as it goes: each failure when minitest names it, a count of tests run,
# and a stall when the log stops growing.
class TestCheckStepWatch < Minitest::Test
  PACE = Operator::CheckRunner::StepWatch::Pace.new(every: 0.05, report: 0.1, stall: 0.3)

  def watched(lines, pace: PACE)
    said = []
    Dir.mktmpdir do |dir|
      log = File.join(dir, "step.log")
      File.write(log, "")

      Master::Trace::Dmesg.stub(:status, ->(*args, **) { said << args.last }) do
        watch = Operator::CheckRunner::StepWatch.new(log, unit: "check_ci3", pace:)
        File.write(log, lines.join("\n") + "\n")
        sleep 0.6
        watch.stop
      end
    end
    said
  end

  def test_a_failure_is_named_when_minitest_prints_it
    said = watched([".F.", "", "  1) Failure:", "TestX#test_y [test/x.rb:1]:", "Expected true"])

    assert_includes said, "failed TestX#test_y"
  end

  def test_the_tests_run_so_far_are_counted
    said = watched(["..F.E"])

    assert(said.any? { |line| line.start_with?("5 tests run, 1 failed, 1 errored") }, said.inspect)
  end

  def test_a_log_that_stops_growing_is_called_a_stall
    said = watched(["."])

    assert(said.any? { |line| line.include?("may be stuck") }, said.inspect)
  end
end
