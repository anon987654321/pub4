# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "stringio"
require "json"
require_relative "../lib/operator/parallel_tests"

class TestParallelTests < Minitest::Test
  Runner = Operator::ParallelTests

  def setup
    @previous_jobs = ENV["MASTER_TEST_JOBS"]
    @previous_timeout = ENV["MASTER_TEST_WORKER_TIMEOUT"]
    @previous_progress = ENV["MASTER_TEST_PROGRESS_EVERY"]
    ENV["MASTER_TEST_JOBS"] = "2"
    ENV["MASTER_TEST_PROGRESS_EVERY"] = "1"
  end

  def teardown
    @previous_jobs.nil? ? ENV.delete("MASTER_TEST_JOBS") : ENV["MASTER_TEST_JOBS"] = @previous_jobs
    @previous_timeout.nil? ? ENV.delete("MASTER_TEST_WORKER_TIMEOUT") : ENV["MASTER_TEST_WORKER_TIMEOUT"] = @previous_timeout
    @previous_progress.nil? ? ENV.delete("MASTER_TEST_PROGRESS_EVERY") : ENV["MASTER_TEST_PROGRESS_EVERY"] = @previous_progress
  end

  # A second suite refused while the first holds the lock: both share fixed log names.
  def test_a_second_suite_refuses_while_one_runs
    FileUtils.mkdir_p(Runner::LOG_DIR)
    File.open(File.join(Runner::LOG_DIR, "suite.lock"), File::RDWR | File::CREAT) do |held|
      held.flock(File::LOCK_EX)
      out = StringIO.new
      started = false

      refute Runner.run(%w[ok], command: ->(_files) { started = true }, out:)
      refute started
      assert_match(/another suite holds/, out.string)
    end
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
        [RbConfig.ruby, "-e", "STDERR.puts 'test-start0: HungSuite#test_stuck'; STDERR.flush; sleep 30"]
      else
        [RbConfig.ruby, "-e", "puts 'test-start0: TestOk#test_one'; puts 'TestOk#test_one = 0.00 s = .'; puts 'Finished in 0.01s'; puts '1 runs, 1 assertions, 0 failures, 0 errors, 0 skips'; exit 0"]
      end
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    passed = Runner.run(%w[hang ok], command:, out:)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    refute passed
    assert_operator elapsed, :<, 8
    assert_includes out.string, "test-worker-timeout0:"
    assert_includes out.string, "last_test=HungSuite#test_stuck"
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
    assert_includes out.string, "test-worker-last0: Example#test_exits_early"
  end

  def test_progress_and_suite_report_name_incomplete_workers
    out = StringIO.new
    command = lambda do |files|
      if files.include?("early")
        [RbConfig.ruby, "-e", "STDERR.puts 'test-start0: Early#test_gone'; exit 0"]
      else
        [RbConfig.ruby, "-e", "puts 'test-start0: Ok#test_one'; puts 'Ok#test_one = 0.00 s = .'; puts 'Finished in 0.01s'; puts '1 runs, 1 assertions, 0 failures, 0 errors, 0 skips'; exit 0"]
      end
    end

    refute Runner.run(%w[early ok], command:, out:)
    assert_includes out.string, "test-progress0: completed_results=1"
    assert_includes out.string, "test-suite-report0:"
    assert_includes out.string, "test-suite-incomplete-workers0:"
    assert_includes out.string, "test-worker-last0: Early#test_gone"

    report_path = File.join(Runner::LOG_DIR, "suite-report.json")
    assert File.file?(report_path), "expected #{report_path}"
    payload = JSON.parse(File.read(report_path))
    assert_equal 1, payload["schema"]
    assert_equal 1, payload["completed_results_relayed"]
    incomplete = payload["workers"].select { |worker| worker["outcome"] == "incomplete" }
    refute_empty incomplete
    assert_equal "Early#test_gone", incomplete.first["last_started_test"]
  end

  def test_exit_zero_with_failure_summary_still_fails_the_run
    out = StringIO.new
    command = lambda do |_files|
      [RbConfig.ruby, "-e", "puts 'test-start0: Example#test_false_green'; puts 'Example#test_false_green = 0.00 s = F'; puts 'Finished in 0.01s'; puts '1 runs, 1 assertions, 1 failures, 0 errors, 0 skips'; exit 0"]
    end

    refute Runner.run(%w[false-green], command:, out:)
    payload = JSON.parse(File.read(File.join(Runner::LOG_DIR, "suite-report.json")))
    assert_equal "failed", payload.fetch("workers").first.fetch("outcome")
    assert payload.fetch("workers").first.fetch("known_red")
  end

  def test_one_job_rake_test_still_uses_the_supervised_runner
    rakefile = File.read(File.expand_path("../Rakefile", __dir__))

    assert_includes rakefile, "Operator::ParallelTests.run(MASTER_TEST_FILES.to_a, command:)"
    refute_includes rakefile, 'next Rake::Task[:"test:serial"].invoke if Operator::ParallelTests.jobs == 1'
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
      "puts \"test-start0: #{test}\"",
      "puts \"#{test} = 0.00 s = #{bad ? "F" : "."}\"", "puts \"Finished in 0.1s\"", failure,
      "puts \"1 runs, 1 assertions, 0 failures, 0 errors, 0 skips\"", "exit(#{!bad})"
    ].join("\n")
    [RbConfig.ruby, "-e", script]
  end
end
