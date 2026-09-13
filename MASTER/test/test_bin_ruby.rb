# frozen_string_literal: true

require_relative "test_helper"
require "open3"

# bin/ruby picks ruby34, ruby3.4 or rbenv's ruby and execs the rest of the line.
# Whichever it picks, the line must run under it with its arguments intact.
class TestBinRuby < Minitest::Test
  BIN = File.expand_path("../bin/ruby", __dir__)

  def test_it_execs_a_ruby_with_the_arguments_intact
    out, err, status = unbundled { Open3.capture3(BIN, "-e", "print RUBY_VERSION, ' ', ARGV.join(',')", "--", "a b", "c") }

    assert status.success?, err
    assert_match(/\A\d+\.\d+\.\d+ a b,c\z/, out)
  end

  def test_a_failing_script_keeps_its_exit_status
    _, _, status = unbundled { Open3.capture3(BIN, "-e", "exit 7") }

    assert_equal 7, status.exitstatus
  end

  private

  # The suite runs under bundle exec; the Ruby bin/ruby picks may not share that
  # bundle, so the child gets a clean environment.
  def unbundled(&) = defined?(Bundler) ? Bundler.with_unbundled_env(&) : yield
end
