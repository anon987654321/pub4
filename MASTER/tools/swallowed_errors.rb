# frozen_string_literal: true

# The diagnostic hunt Ground::Swallow was built for, finally run by something.
#
# Swallow classifies every swallowed error as :load_bearing or :cosmetic, writes
# it to .master/swallowed_errors.jsonl, and publishes it on the bus. Its own
# header says why the severity exists: "so the next diagnostic hunt can filter
# for :load_bearing instead of reading every line."
#
# No hunt ever ran. `Swallow.recent` — the reader written for exactly this — had
# zero callers across lib, bin, tools, test and spec; every other reference in
# the tree is a `.log` call. The classification was being made carefully and
# thrown into a file nobody opened.
#
# Measured on 2026-08-25 the first time anything asked: 5,037 load-bearing
# entries, of which 4,663 are CommentDriftRule failing with "claude-cli: No such
# file or directory - claude". A rule MASTER marks load-bearing had failed four
# and a half thousand times while every scan it belonged to reported clean.
#
# This runs against LOCAL runtime state, not the repo, so it is an operator
# check rather than a CI ratchet — the log is per-machine and gitignored. That
# is also why it reports rather than ratchets: the right number depends on how
# much has been run since the file was last cleared.
#
#   ruby MASTER/tools/swallowed_errors.rb
#   ruby MASTER/tools/swallowed_errors.rb --json
#
# Wired as `rake lint:swallowed`.

require "json"

module Pub4
  module SwallowedErrors
    MASTER = File.expand_path("..", __dir__)

    # Contexts that are deliberate emissions from the tests that prove Swallow
    # works. Counting them would make the check fail hardest right after someone
    # runs the suite that keeps it honest.
    FIXTURE = /\Atest_swallow\.|\ATestScanRuleFalsePositives|\ATest\w+::/

    module_function

    def entries
      $LOAD_PATH.unshift(File.join(MASTER, "lib")) unless $LOAD_PATH.include?(File.join(MASTER, "lib"))
      require "master"
      Master::Ground::Swallow.recent(limit: 1_000_000, severity: :load_bearing)
    rescue StandardError => e
      warn "swallowed_errors: cannot read the log (#{e.class}: #{e.message})"
      []
    end

    def real(all = entries)
      all.reject { |row| row["context"].to_s.match?(FIXTURE) }
    end

    def by_context(rows = real)
      rows.group_by { |row| row["context"].to_s }
          .transform_values { |group| { count: group.size, last: group.last } }
          .sort_by { |_, v| -v[:count] }
    end

    def run(json: false)
      rows = real
      grouped = by_context(rows)

      if json
        puts JSON.generate(total: rows.size,
                           contexts: grouped.map { |ctx, v| { context: ctx, count: v[:count] } })
        return rows.empty?
      end

      if rows.empty?
        puts "swallowed: no load-bearing errors in .master/swallowed_errors.jsonl"
        return true
      end

      puts "swallowed: #{rows.size} LOAD-BEARING error(s) swallowed, across #{grouped.size} context(s)"
      puts "  these were classified load-bearing by the code that swallowed them —"
      puts "  the caller decided this mattered, and then nothing looked."
      grouped.first(10).each do |ctx, v|
        puts format("  %6d  %-46s %s", v[:count], ctx, v[:last]["error_message"].to_s[0, 60])
      end
      puts "  … #{grouped.size - 10} more context(s)" if grouped.size > 10
      false
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ok = Pub4::SwallowedErrors.run(json: ARGV.include?("--json"))
  exit(ok ? 0 : 1)
end
