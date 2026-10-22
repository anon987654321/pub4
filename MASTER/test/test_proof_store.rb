# frozen_string_literal: true

require "tmpdir"
require_relative "test_helper"

# A proof baseline measured once is kept on disk under its tree's content, so the next /fix on
# the same tree does not run the whole suite again before its first edit.
class TestProofStore < Minitest::Test
  Proof = Master::CLI::Pipeline::Proof
  RED = ["proof suite MASTER: FAIL", "  1) Failure:", "TestX#test_y [test/x.rb:1]:", "Expected true",
         "9 runs, 9 assertions, 1 failures, 0 errors, 0 skips"].freeze

  # A pass whose proof runner is a counter.
  class CountingPass < Master::CLI::Pipeline::Pass
    attr_reader :runs

    def initialize
      @failed_stages = []
      @causes = {}
      @runs = 0
    end

    def proof_runner(_abs) = ["MASTER", -> { @runs += 1; [false, RED] }]
    def origin_main = "a" * 40
    def baseline_for(abs) = proof_baseline(abs)
  end

  def setup
    @saved = %w[MASTER_IN_PROOF MASTER_PROOF_STORE MASTER_PROOF_STORE_DIR].to_h { |key| [key, ENV.delete(key)] }
    @dir = Dir.mktmpdir
    ENV["MASTER_PROOF_STORE_DIR"] = @dir
    Proof.forget_all
  end

  def teardown
    @saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    FileUtils.remove_entry(@dir)
    Proof.forget_all
  end

  def test_a_second_run_on_the_same_tree_reuses_the_stored_baseline
    CountingPass.new.baseline_for(Master::ROOT)
    Proof.forget_all
    second = CountingPass.new

    reading = second.baseline_for(Master::ROOT)

    assert_equal 0, second.runs, "the suite ran again on unchanged content"
    assert_includes reading.failing, "TestX#test_y"
  end

  def test_the_store_can_be_turned_off
    ENV["MASTER_PROOF_STORE"] = "0"
    CountingPass.new.baseline_for(Master::ROOT)
    Proof.forget_all
    second = CountingPass.new

    second.baseline_for(Master::ROOT)

    assert_equal 1, second.runs
  end
end
