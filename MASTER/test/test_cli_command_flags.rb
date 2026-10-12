# frozen_string_literal: true

require_relative "test_helper"

# bin/cli is a script, so the two argv helpers are evaluated from its source
# rather than booting the runtime.
class TestCliCommandFlags < Minitest::Test
  SOURCE = File.read(File.expand_path("../bin/cli", __dir__))
  HELPERS = SOURCE[/^COMMAND_FLAG.*?(?=^# Help is answered)/m]

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

  def test_fix_flags_do_not_raise_an_option_error
    out, err = capture_io { @host.send(:initial_message_from_argv, ["/fix", "MASTER", "--max-files=3"]) }

    refute_match(/option error/, err + out)
  end

  def test_other_unknown_flags_are_still_dropped
    assert_equal "/fix RAILS --autofix=off", @host.send(:initial_message_from_argv, ["/fix", "RAILS", "--bogus", "--autofix=off"])
  end
end
