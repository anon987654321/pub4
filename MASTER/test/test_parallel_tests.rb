# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "stringio"
require_relative "../lib/operator/parallel_tests"

# The suite split across processes still reports each test as it lands and each worker's
# failures whole, and fails when any worker fails.
class TestParallelTests < Minitest::Test
  Runner = Operator::ParallelTests

  def test_results_pass_through_and_a_failed_worker_fails_the_run
    out = StringIO.new
    passed = Runner.run(%w[ok bad], command: method(:fake_worker), out:)

    refute passed
    assert_includes out.string, "TestOk#test_one = 0.00 s = ."
    assert_includes out.string, "TestBad#test_two = 0.00 s = F"
    assert_includes out.string, "TestBad#test_two [x.rb:1]:"
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

  # A worker that prints one verbose result and a report, and fails when given "bad".
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
