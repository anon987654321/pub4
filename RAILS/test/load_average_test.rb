# frozen_string_literal: true

# The load guard has to work on the machine it guards.
#
# PruneGuestUsersJob's ceiling read /proc/loadavg, which OpenBSD does not have.
# It raised ENOENT into a bare rescue that returned false, so the guard answered
# "not busy" on every tick of vm23 — and it was written the day after that job
# ran unpaced and took the whole site down. Nothing failed. Nothing logged. The
# guard was decoration from its first commit.
#
# So this test does two things a code review would not. It runs the reader here,
# on whatever this is, and demands a real number — the same call the job makes,
# not a mock of it. And it greps the tree for the Linux-only path, because the
# defect was never the parsing; it was one platform's interface being used on
# another and nobody being able to see it.
#
# Bare minitest, no Rails: RAILS/test/*.rb run under plain ruby.

require "minitest/autorun"
require_relative "../shared/lib/pub4/load_average"

ROOT = File.expand_path("..", __dir__)

class LoadAverageTest < Minitest::Test
  def test_reads_a_real_load_average_on_this_machine
    one = Pub4::LoadAverage.one

    refute_nil one, "no load average on #{RUBY_PLATFORM} — the guard is blind here"
    assert_kind_of Float, one
    assert_operator one, :>=, 0.0
    # A 1-vCPU box under a stampede reached 10; 256 is not a load, it is a
    # parse that picked up a PID or a byte count.
    assert_operator one, :<, 256.0, "#{one} is not a plausible load average"
  end

  def test_five_minute_average_is_also_available
    assert_kind_of Float, Pub4::LoadAverage.five
  end

  def test_unknown_reads_as_nil_rather_than_zero
    # The whole point of the module. An idle box and an unreadable one are
    # different facts, and the old code returned 0.0 for both.
    assert_nil Pub4::LoadAverage.at(9)
  end

  # macOS prints "{ 7.94 4.61 3.67 }". Splitting on whitespace makes the first
  # field "{", so a positional parser returns nil on every developer machine
  # while looking correct on the server.
  def test_parses_the_brace_wrapped_bsd_format
    numbers = "{ 7.94 4.61 3.67 }".scan(/\d+(?:\.\d+)?/)

    assert_equal %w[7.94 4.61 3.67], numbers.first(3)
  end

  # Split so that this file is not its own first offender — the matcher covers
  # the test that runs it, which is the only way it covers everything.
  NEEDLE = "/proc/" + "loadavg"

  def test_nothing_outside_the_reader_asks_procfs_for_the_load
    offenders = ruby_sources.reject { |p| p.end_with?("lib/pub4/load_average.rb") }.flat_map do |path|
      code_lines(path).select { |_n, line| line.include?(NEEDLE) }
                      .map { |n, _line| "#{path.delete_prefix("#{ROOT}/")}:#{n}" }
    end

    assert_empty offenders, "#{NEEDLE} does not exist on OpenBSD — use Pub4::LoadAverage"
  end

  private

  # Comments are exempt, and that is not a loophole. The prune job carries a
  # paragraph naming /proc/loadavg as the thing that was wrong with it, which is
  # the most useful sentence in the file; a matcher that cannot tell an
  # explanation from a call would delete the explanation to stay green. This
  # test is looking for a read, so it looks at code.
  def code_lines(path)
    File.read(path, encoding: "UTF-8").lines.each_with_index.filter_map do |line, i|
      stripped = line.strip
      [i + 1, line] unless stripped.empty? || stripped.start_with?("#")
    end
  end

  def ruby_sources
    Dir.glob("#{ROOT}/{shared,brgen,amber,bsdports,gates,test}/**/*.rb")
       .reject { |p| p.include?("/vendor/") || p.include?("/node_modules/") }
  end
end
