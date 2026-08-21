#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs RAILS/test/*_test.rb, one process per file.
#
# The suite was run exactly one way before this: `check-full` did
#
#   Dir["RAILS/test/**/*_test.rb"].sort.each { |f| require File.expand_path(f) }
#
# which loads sixty-nine top-level Minitest files into a single process. It
# works today, and the two reasons it works are luck:
#
#   Constants. Nearly every file declares ROOT, and several declare APPS, GATES,
#   LINT and SKIP at class scope. They happen not to collide because they happen
#   to be nested inside differently-named test classes. The first one that is
#   not gets `already initialized constant` on a good day and another file's
#   value on a bad one -- and the failure surfaces as an assertion about the
#   wrong tree, not as a load error.
#
#   Termination. One `exit` or one `abort` anywhere in sixty-nine files ends the
#   run, and Minitest reports on whatever had already been collected. Several of
#   these files shell out to gates that call `exit` on their own failure paths.
#
# There is also nothing local: `check-full` is the release gate, so the only way
# to run the contract suite was to run the deploy chain, which shells out to the
# integrity gate and the Rails gates and takes minutes. That is why files in this
# directory have been found red on main -- not because nobody ran them, but
# because running them cost a deploy check.
#
#   ruby RAILS/test/run_all.rb              # all of them
#   ruby RAILS/test/run_all.rb scale        # only files matching /scale/
#
# Exit status is the number of failing files, capped at 255.

require "open3"
require "rbconfig"
require "timeout"

module Pub4
  class ContractSuite
    TEST_DIR = __dir__
    RAILS_ROOT = File.expand_path("..", __dir__)

    # Per file. These read source and assert; a second is generous. The bound is
    # high because four of them shell out to the gate runner, which is slow and
    # is a separate problem from this one.
    TIMEOUT = Integer(ENV.fetch("CONTRACT_TIMEOUT", "300"))

    Outcome = Struct.new(:file, :status, :runs, :assertions, :failures, :output)

    def initialize(filter: nil, io: $stdout)
      @filter = filter
      @io = io
    end

    def files
      # Recursive: test/gates/ holds nine more, and check-full has always
      # globbed **/*_test.rb. A narrower glob here would run 401 of the 496 and
      # print a green line about it.
      all = Dir.glob(File.join(TEST_DIR, "**", "*_test.rb")).sort
      @filter ? all.select { |path| path.include?(@filter) } : all
    end

    def run
      list = files
      if list.empty?
        @io.puts("contracts: no test files#{@filter ? " matching #{@filter.inspect}" : ""}")
        return 1
      end

      outcomes = list.map { |path| report(execute(path)) }
      summarise(outcomes)
      outcomes.count { |outcome| outcome.status != :pass }.clamp(0, 255)
    end

    private

    def rel(path) = path.sub("#{RAILS_ROOT}/", "")

    # MT_NO_PLUGINS so a globally installed Minitest plugin cannot change what
    # this observes; -I so a file can require_relative its subject the way the
    # app tests do.
    def execute(path)
      env = { "MT_NO_PLUGINS" => "1" }
      out = nil
      status = nil
      Open3.popen2e(env, RbConfig.ruby, "-I#{TEST_DIR}", path, chdir: RAILS_ROOT, pgroup: true) do |stdin, io, thread|
        stdin.close
        begin
          Timeout.timeout(TIMEOUT) do
            out = io.read
            status = thread.value
          end
        rescue Timeout::Error
          kill_group(thread.pid)
          status = nil
        end
      end
      build(path, out, status)
    end

    def build(path, out, status)
      tally = out.to_s[/^(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors/]
      runs, assertions, failures, errors = $1.to_i, $2.to_i, $3.to_i, $4.to_i if tally

      state = if status.nil? then :timeout
              elsif status.success? then :pass
              else :fail
              end
      Outcome.new(rel(path), state, runs.to_i, assertions.to_i, failures.to_i + errors.to_i, out.to_s)
    end

    MARK = { pass: "ok  ", fail: "FAIL", timeout: "HUNG" }.freeze

    def report(outcome)
      @io.puts(format("contracts: %s %-56s %4d runs, %5d assertions",
                      MARK.fetch(outcome.status), outcome.file.sub("test/", ""), outcome.runs, outcome.assertions))
      @io.puts(indent(detail(outcome))) unless outcome.status == :pass
      outcome
    end

    # The failure lines and nothing else. A runner that reprints four hundred
    # lines of backtrace per red file is a runner people stop reading, and the
    # whole reason these tests went unread is that running them was expensive.
    def detail(outcome)
      return "exceeded #{TIMEOUT}s and was killed" if outcome.status == :timeout

      lines = outcome.output.lines
      starts = lines.each_index.select { |i| lines[i].match?(/^\s*\d+\)\s+(Failure|Error):/) }
      return outcome.output.lines.last(4).join.strip if starts.empty?

      starts.first(4).flat_map { |i| lines[i, 4] }.join.rstrip
    end

    def indent(text) = text.to_s.lines.map { |line| "        #{line}" }.join

    def summarise(outcomes)
      red = outcomes.reject { |o| o.status == :pass }
      totals = outcomes.sum(&:runs)
      @io.puts("contracts: #{outcomes.size} file(s), #{totals} runs, #{red.size} red")
      return if red.empty?

      @io.puts("contracts: #{red.map { |o| o.file.sub("test/", "") }.join(', ')}")
    end

    def kill_group(pid)
      Process.kill("-KILL", Process.getpgid(pid))
    rescue StandardError
      begin
        Process.kill("KILL", pid)
      rescue Errno::ESRCH # scan: intentional — already gone is the goal state
        nil
      end
    end
  end
end

exit(Pub4::ContractSuite.new(filter: ARGV.first).run) if __FILE__ == $PROGRAM_NAME
