#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs RAILS/test/*_test.rb, one process per file.
#
# The suite was run exactly one way before this: `check-full` did
#
#   Dir["RAILS/test/**/*_test.rb"].sort.each { |f| require File.expand_path(f) }
#
# which loads every contract test into a single process. There are 131 contract
# files today. It works, but the two reasons it works are accidental:
#
#   Constants. Nearly every file declares ROOT, and several declare APPS, CHECKS,
#   LINT and SKIP at class scope. They happen not to collide because they happen
#   to be nested inside differently-named test classes. The first one that is
#   not gets `already initialized constant` on a good day and another file's
#   value on a bad one -- and the failure surfaces as an assertion about the
#   wrong tree, not as a load error.
#
#   Termination. One `exit` or one `abort` anywhere in sixty-nine files ends the
#   run, and Minitest reports on whatever had already been collected. Several of
#   these files shell out to checks that call `exit` on their own failure paths.
#
# There is also nothing local: `check-full` is the release check, so the only way
# to run the contract suite was to run the deploy chain, which shells out to the
# integrity check and the Rails checks and takes minutes. That is why files in this
# directory have been found red on main -- not because nobody ran them, but
# because running them cost a deploy check.
#
#   ruby RAILS/test/run_all.rb              # all of them
#   ruby RAILS/test/run_all.rb scale        # only files matching /scale/
#
# Exit status is the number of failing files, capped at 255.

require "digest"
require "rbconfig"
require_relative "../__shared/lib/shared/subprocess"

module Operator
  class ContractSuite
    TEST_DIR = __dir__
    RAILS_ROOT = File.expand_path("..", __dir__)

    # Per file. These read source and assert; a second is generous. The bound is
    # high because four of them shell out to the check runner, which is slow and
    # is a separate problem from this one.
    TIMEOUT = Integer(ENV.fetch("CONTRACT_TIMEOUT", "300"))
    REPLAY = Integer(ENV.fetch("CONTRACT_REPLAY", "0")).clamp(0, 5)

    Outcome = Struct.new(:file, :status, :runs, :assertions, :failures, :output)

    def initialize(filter: nil, io: $stdout)
      @filter = filter
      @io = io
    end

    def files
      # Recursive: test/checks/ is part of the contract suite. This currently
      # selects all 131 files; a narrower glob would make a green result dishonest.
      # Written from the repository root so MASTER/tools/repo/runs.rb reads the glob
      # and counts every file it selects as run.
      all = Dir.glob(File.join(RAILS_ROOT, "..", "RAILS/test/**/*_test.rb")).map { |path| File.expand_path(path) }.sort
      @filter ? all.select { |path| path.include?(@filter) } : all
    end

    def run
      list = files
      if list.empty?
        @io.puts("contracts: no test files#{@filter ? " matching #{@filter.inspect}" : ""}")
        return 1
      end

      outcomes = list.map do |path|
        outcome = execute(path, seed: replay_seed(path, 0))
        if outcome.status == :pass && REPLAY.positive?
          REPLAY.times do |index|
            replay = execute(path, seed: replay_seed(path, index + 1))
            next if replay.status == :pass

            outcome = Outcome.new(
              rel(path),
              :flake,
              outcome.runs,
              outcome.assertions,
              outcome.failures + replay.failures,
              "initial run passed, replay #{index + 1} did not:\n#{replay.output}"
            )
            break
          end
        end
        report(outcome)
      end
      summarise(outcomes)
      outcomes.count { |outcome| outcome.status != :pass }.clamp(0, 255)
    end

    private

    def rel(path) = path.sub("#{RAILS_ROOT}/", "")

    # MT_NO_PLUGINS so a globally installed Minitest plugin cannot change what
    # this observes; -I so a file can require_relative its subject the way the
    # app tests do.
    def replay_seed(path, index)
      Digest::SHA256.hexdigest("#{rel(path)}:#{index}").then { |hex| hex[0, 8].to_i(16) }
    end

    def execute(path, seed: nil)
      env = { "MT_NO_PLUGINS" => "1" }
      command = [RbConfig.ruby, "-I#{TEST_DIR}", path]
      command.concat(["--seed", seed.to_s]) if seed
      out, status = begin
        Shared::Subprocess.capture2e(*command, timeout: TIMEOUT, env:, chdir: RAILS_ROOT)
      rescue Shared::Subprocess::TimeoutError => error
        [error.message, nil]
      end
      build(path, out, status)
    end

    def build(path, out, status)
      summary = out.to_s.lines.filter_map do |line|
        line.match(/\A(\d+) runs, (\d+) assertions, (\d+) failures, (\d+) errors(?:, (\d+) skips)?\s*\z/)
      end.last
      runs, assertions, failures, errors = summary ? summary.captures.first(4).map(&:to_i) : [ 0, 0, 0, 0 ]

      invalid_summary = if summary.nil?
                          "missing valid Minitest summary"
                        elsif runs.zero?
                          "Minitest reported zero runs"
                        elsif failures.positive? || errors.positive?
                          "Minitest reported #{failures} failures and #{errors} errors"
                        end
      output = if invalid_summary
                 "contract runner rejected result: #{invalid_summary}\n#{out}"
               else
                 out.to_s
               end

      state = if status.nil? then :timeout
              elsif !status.success? || invalid_summary then :fail
              else :pass
              end
      Outcome.new(rel(path), state, runs, assertions, failures + errors, output)
    end
    MARK = { pass: "ok  ", fail: "FAIL", timeout: "HUNG", flake: "FLAKE" }.freeze

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

  end
end

exit(Operator::ContractSuite.new(filter: ARGV.first).run) if __FILE__ == $PROGRAM_NAME
