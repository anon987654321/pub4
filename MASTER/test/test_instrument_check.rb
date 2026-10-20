# frozen_string_literal: true

require_relative "test_helper"
require "fix/instrument_check"

# /fix must stop with the name of a broken instrument, not run on and report a result it could not measure.
class TestInstrumentCheck < Minitest::Test
  Check = Master::Fix::InstrumentCheck

  # A check whose probes answer as told: a String is a failure reason, nil is health, a class is raised.
  class Scripted < Check
    def initialize(answers:, **)
      super(root: Dir.pwd, probes: answers.keys, **)
      answers.each do |name, answer|
        define_singleton_method(:"probe_#{name}") do
          raise answer if answer.is_a?(Class)

          answer
        end
      end
    end
  end

  def setup
    @previous = ENV.delete("MASTER_FIX_INSTRUMENT_CHECK")
  end

  def teardown
    ENV["MASTER_FIX_INSTRUMENT_CHECK"] = @previous if @previous
  end

  def scripted(answers) = Scripted.new(answers:)

  def test_a_healthy_set_of_instruments_passes
    assert scripted(disk: nil, git: nil).verify!
  end

  def test_every_broken_instrument_is_named_in_one_error
    broken = scripted(disk: "free space could not be read", patch_tool: "gone", git: nil)
    error = assert_raises(Check::Unavailable) { broken.verify! }

    assert_includes error.message, "disk: free space could not be read"
    assert_includes error.message, "patch_tool: gone"
    refute_includes error.message, "git"
  end

  def test_a_probe_that_raises_is_a_failure_not_a_crash
    failures = scripted(disk: ArgumentError).failures

    assert_equal 1, failures.size
    assert_match(/\Adisk: probe raised ArgumentError/, failures.first)
  end

  def test_the_opt_out_skips_the_check
    previous = ENV["MASTER_FIX_INSTRUMENT_CHECK"]
    ENV["MASTER_FIX_INSTRUMENT_CHECK"] = "0"

    assert scripted(disk: "broken").verify!
  ensure
    previous.nil? ? ENV.delete("MASTER_FIX_INSTRUMENT_CHECK") : ENV["MASTER_FIX_INSTRUMENT_CHECK"] = previous
  end

  def test_the_real_instruments_work_on_this_checkout
    probes = %i[disk git patch_tool ruby_child cache_dir]

    assert_empty Check.new(root: Master::REPO_ROOT, probes:).failures
  end
end
