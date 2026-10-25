# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "stringio"
require_relative "../lib/operator/parallel_tests"

class TestParallelTests < Minitest::Test
  Runner = Operator::ParallelTests

  def setup
    @previous_jobs = ENV["MASTER_TEST_JOBS"]
    @previous_timeout = ENV["MASTER_TEST_WORKER_TIMEOUT"]
    ENV["MASTER_TEST_JOBS"] = "2"
  end

  def teardown
    @previous_jobs.nil? ? ENV.delete("MASTER_TEST_JOBS") : ENV["MASTER_TEST_JOBS"] = @previous_jobs
    @previous_timeout.nil? ? ENV.delete("MASTER_TEST_WORKER_TIMEOUT") : ENV["MASTER_TEST_WORKER_TIMEOUT"] = @previous_timeout
  end

  def test_results_pass_through_and_a_failed_worker_fails_the_run
    out = StringIO.new
    passed = Runner.run(%w[ok bad], command: method(:fake_worker), out:)

    refute passed
    assert_includes out.string, "TestOk#test_one = 0.00 s = ."
    assert_includes out.string, "TestBad#test_two = 0.00 s = F"
    assert_includes out.string, "TestBad#test_two [x.rb:1]:"
  end

  def test_a_hung_worker_times_out_and_reports_its_log
    ENV["MASTER_TEST_WORKER_TIMEOUT"] = "0.2"
    out = StringIO.new
    command = lambda do |files|
      if files.include?("hang")
        [RbConfig.ruby, "-e", "sleep 30"]
      else
        [RbConfig.ruby, "-e", "puts 'Finished in 0.01s'; puts '1 runs, 1 assertions, 0 failures, 0 errors, 0 skips'; exit 0"]
      end
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    passed = Runner.run(%w[hang ok], command:, out:)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    refute passed
    assert_operator elapsed, :<, 8
    assert_includes out.string, "test-worker-timeout0:"
    assert_includes out.string, "TIMEOUT"
  end

  def test_successful_exit_without_minitest_summary_is_incomplete
    out = StringIO.new
    command = lambda do |_files|
      [RbConfig.ruby, "-e", "STDERR.puts 'test-start0: Example#test_exits_early'; exit 0"]
    end

    refute Runner.run(%w[early-exit], command:, out:)
    assert_includes out.string, "INCOMPLETE"
    assert_includes out.string, "test-start0: Example#test_exits_early"
    assert_includes out.string, "test-worker-incomplete0: missing final Minitest summary"
  end

  def test_files_are_dealt_largest_first_onto_the_lightest_worker
    buckets = Dir.mktmpdir { |dir| Runner.deal(sized_files(dir), 2).map { |bucket| bucket.map { File.basename(_1) } } }
    assert_equal [%w[a d], %w[b c]], buckets
  end

  def sized_files(dir)
    { "a" => 900, "b" => 500, "c" => 400, "d" => 100 }.map do |name, size|
      File.join(dir, name).tap { |path| File.write(path, "x" * size) }
    end
  end

  def fake_worker(files)
    bad = files.first == "bad"
    test = bad ? "TestBad#test_two" : "TestOk#test_one"
    failure = bad ? "puts \"  1) Failure:\", \"#{test} [x.rb:1]:\"" : ""
    script = [
      "puts \"#{test} = 0.00 s = #{bad ? "F" : "."}\"", "puts \"Finished in 0.1s\"", failure,
      "puts \"1 runs, 1 assertions, 0 failures, 0 errors, 0 skips\"", "exit(#{!bad})"
    ].join("\n")
    [RbConfig.ruby, "-e", script]
  end
end
