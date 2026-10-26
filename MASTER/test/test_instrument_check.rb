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

  def test_verification_result_normalizes_pass_blocked_and_disabled
    healthy = scripted(disk: nil, git: nil).verification_result
    blocked = scripted(disk: "private disk diagnostic", git: nil).verification_result
    disabled = scripted(disk: "should not execute").verification_result(
      env: { "MASTER_FIX_INSTRUMENT_CHECK" => "0" }
    )

    assert_equal :pass, healthy.status
    assert_predicate healthy, :conclusive?
    assert_equal 2, healthy.checked_count
    assert_equal Digest::SHA256.hexdigest(Dir.pwd), healthy.scope_digest

    assert_equal :blocked, blocked.status
    assert_equal 2, blocked.checked_count
    assert_equal 1, blocked.failure_count
    refute_predicate blocked, :conclusive?
    refute_includes blocked.to_h.inspect, "private disk diagnostic"

    assert_equal :not_applicable, disabled.status
    assert_equal 0, disabled.checked_count
    assert_equal 1, disabled.unchecked_count
    refute_predicate disabled, :conclusive?
  end

  def test_blocked_preflight_event_contains_no_free_form_failure_text
    events = []
    bus = Object.new
    bus.define_singleton_method(:publish) { |event, **payload| events << [event, payload] }
    check = Scripted.new(answers: { disk: "private/customer/workspace has no disk budget" }, bus:)

    error = assert_raises(Check::Unavailable) { check.verify! }
    assert_includes error.message, "private/customer/workspace"
    event, payload = events.fetch(0)
    assert_equal "fix_loop:instruments_unavailable", event
    assert_equal :blocked, payload.dig(:verification, :status)
    assert_equal 1, payload.fetch(:failure_count)
    assert_match(/\\A[0-9a-f]{64}\\z/, payload.fetch(:failure_digest))
    refute_includes payload.inspect, "private/customer/workspace"
    refute_includes payload.inspect, "no disk budget"
  end

  def test_the_real_instruments_work_on_this_checkout
    probes = %i[disk git patch_tool ruby_child cache_dir]

    assert_empty Check.new(root: Master::REPO_ROOT, probes:).failures
  end
end
