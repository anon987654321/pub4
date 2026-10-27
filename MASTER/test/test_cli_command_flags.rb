# frozen_string_literal: true

require_relative "test_helper"

# bin/master is a script, so the two argv helpers are evaluated from its source
# rather than booting the runtime.
class TestCliCommandFlags < Minitest::Test
  SOURCE = File.read(File.expand_path("../bin/master", __dir__))
  HELPERS = SOURCE[/^COMMAND_FLAG.*?(?=^# Flags are read before the runtime boots)/m]

  def setup
    host = Object.new
    host.extend(Module.new { def self.status(*, **) = nil })
    host.instance_eval("require 'optparse'; module Master; module Trace; module Dmesg; def self.status(*, **) = nil; end; end; end\n#{HELPERS}", __FILE__, 1)
    @host = host
  end

  def test_fix_flags_survive_into_the_message
    argv = ["/fix", "RAILS", "--max-files=25", "--autofix=on"]

    assert_equal "/fix RAILS --max-files=25 --autofix=on", @host.send(:initial_message_from_argv, argv)
  end

  def test_no_critique_survives_into_the_message_without_an_option_error
    argv = ["/fix", "MASTER", "--no-critique"]
    message = nil
    out, err = capture_io { message = @host.method(:initial_message_from_argv).call(argv) }

    assert_equal "/fix MASTER --no-critique", message

    refute_match(/option error/, err + out)
  end

  def test_blockers_survives_into_the_message
    assert_equal "/fix RAILS --blockers", @host.initial_message_from_argv(["/fix", "RAILS", "--blockers"])
  end

  def test_dry_run_is_never_dropped
    argv = ["/fix", "MASTER", "--dry-run", "--no-autofix", "--only=critique"]

    message = @host.method(:initial_message_from_argv).call(argv)

    assert_equal "/fix MASTER --dry-run --no-autofix --only=critique", message
  end

  def test_fix_flags_do_not_raise_an_option_error
    out, err = capture_io { @host.send(:initial_message_from_argv, ["/fix", "MASTER", "--max-files=3"]) }

    refute_match(/option error/, err + out)
  end

  # --model forces one model on every lane, as bin/cli's flag did before bin/master
  # absorbed it; the message the flag wraps is unchanged.
  def test_model_flag_forces_master_model
    previous = ENV.fetch("MASTER_MODEL", nil)
    ENV.delete("MASTER_MODEL")

    assert_equal "/status", @host.send(:initial_message_from_argv, ["--model", "x-ai/grok-4", "/status"])
    assert_equal "x-ai/grok-4", ENV.fetch("MASTER_MODEL")
  ensure
    previous.nil? ? ENV.delete("MASTER_MODEL") : ENV["MASTER_MODEL"] = previous
  end

  def test_other_unknown_flags_are_still_dropped
    assert_equal "/fix RAILS --autofix=off", @host.send(:initial_message_from_argv, ["/fix", "RAILS", "--bogus", "--autofix=off"])
  end
end
