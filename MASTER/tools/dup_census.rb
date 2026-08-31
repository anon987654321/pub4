# frozen_string_literal: true

# Exact-duplicate census over every tracked file. The lightgallery defect —
# one file vendored twice, diverging silently, amber shipping 404 icons for
# months — is a CLASS, and the 2026-08-22 sitting found 65 sets of it worth
# 546KB. This counts what remains after the provable collapses so the next
# shadow copy is a +1 against a ceiling, not a quiet arrival.
#
#   ruby MASTER/tools/dup_census.rb            # list sets over the ceiling
#   ruby MASTER/tools/dup_census.rb --ratchet  # record a new low
#
# Known-legitimate duplicates are EXPECTED and stay counted rather than
# excluded: per-app 422/500.html (ShowExceptions reads the app public path),
# aliased-route layout snapshots (identical JSON is a fact about the routes).
# The ceiling prices them; the census does not pretend they are unique.

require "digest"
require "yaml"

module Pub4
  module DupCensus
    ROOT = File.expand_path("../..", __dir__)
    CEILING = File.join(ROOT, "MASTER", "data", "dup_census.yml")
    MIN_SIZE = 200 # tiny stubs legitimately repeat

    module_function

    def sets
      files = check_corpus!(`git -C #{ROOT} ls-files -z`.split("\0"))
              .reject { |f| f.start_with?("STUDIO/") }
      by = Hash.new { |h, k| h[k] = [] }
      files.each do |f|
        path = File.join(ROOT, f)
        next unless File.file?(path) && File.size(path) >= MIN_SIZE
        by[[Digest::SHA256.file(path).hexdigest, File.size(path)]] << f
      end
      by.select { |_, v| v.size > 1 }
    end

    # Same reason as the ceiling itself: a census that reads nothing finds no
    # duplicates and passes. `git ls-files` coming back empty -- a wrong root, a
    # git that failed -- looks exactly like a clean tree from here, which is how
    # STUDIO gate spent a worktree reporting on a corpus of zero files.
    def check_corpus!(files)
      return files if files.size >= 500

      abort("dup_census: git ls-files returned #{files.size} paths -- the corpus " \
            "collapsed, so a report of zero duplicates measured nothing")
    end

    def recorded
      File.exist?(CEILING) ? (YAML.safe_load_file(CEILING) || {}) : {}
    end

    def ceiling = recorded.fetch("duplicate_sets", 0)

    # The members behind the count. Without them "over by two" names no pair,
    # and the next reader re-derives the whole list against an older commit by
    # hand — the gap data_reach and self_findings both closed on 2026-08-31.
    # One line per set, its paths sorted and joined, so two runs of an
    # unchanged tree produce the same list.
    def recorded_members = Array(recorded["members"])

    def members(sets) = sets.values.map { |paths| paths.sort.join(" | ") }.sort

    def report_delta(current)
      if recorded_members.empty?
        puts "dup_census: no members recorded — attribution unavailable; run --ratchet to seed it"
        return
      end

      (current - recorded_members).each { |set| puts "  + #{set}" }
      (recorded_members - current).each { |set| puts "  - #{set}" }
    end

# The prose above `duplicate_sets:` records what each past collapse cost
# somebody — thirty lines of it, including the warning that this tool reads
# content from disk in a shared checkout. A bare to_yaml dump ate all of it
# the first time this wrote members. Preserved, not regenerated.
def rewritten_ceiling(count, member_list)
  existing = File.exist?(CEILING) ? File.read(CEILING) : "---\n"
  prose = existing.sub(/^duplicate_sets: .*\n(?:members:\n(?:- .*\n)*)?\z/, "")
  "#{prose}duplicate_sets: #{count}\nmembers:\n#{member_list.map { |m| "- #{m}\n" }.join}"
end

    def run(ratchet: false, list: false)
      d = sets
      puts "dup_census: #{d.size} duplicate set(s), " \
           "#{d.sum { |(_, size), v| size * (v.size - 1) } / 1024}KB shadowed (ceiling #{ceiling})"
      # A count nobody can act on is a ratchet, not a finding. --list prints
      # what was counted, largest shadow first, and changes no number.
      if list
        d.sort_by { |(_, size), v| -size * (v.size - 1) }.each do |(_, size), v|
          puts "  #{size / 1024}KB x#{v.size}: #{v.join(' | ')}"
        end
        return 0
      end
      # <=, not <, so a census sitting exactly at its ceiling can record its
      # members without having to fall first. A census already over cannot:
      # a baseline containing the overage would report it as known.
      if ratchet && d.size <= ceiling
        previous = ceiling
        File.write(CEILING, rewritten_ceiling(d.size, members(d)))
        puts "dup_census: #{d.size < previous ? "recorded #{d.size} as the new low" : "re-recorded #{d.size}"}, with its members"
        return 0
      end
      return 0 unless d.size > ceiling

      report_delta(members(d))
      d.sort_by { |(_, s), v| -s * (v.size - 1) }.first(10).each do |(_, size), v|
        puts "  #{size / 1024}KB x#{v.size}: #{v.join(' | ')[0, 150]}"
      end
      puts "dup_census: a tracked file now exists twice — collapse it or price the ceiling"
      1
    end
  end
end

exit Pub4::DupCensus.run(ratchet: ARGV.include?("--ratchet"), list: ARGV.include?("--list")) if $PROGRAM_NAME == __FILE__
