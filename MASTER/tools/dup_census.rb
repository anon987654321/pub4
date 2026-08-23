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
      files = `git -C #{ROOT} ls-files -z`.split("\0").reject { |f| f.start_with?("STUDIO/") }
      by = Hash.new { |h, k| h[k] = [] }
      files.each do |f|
        path = File.join(ROOT, f)
        next unless File.file?(path) && File.size(path) >= MIN_SIZE
        by[[Digest::SHA256.file(path).hexdigest, File.size(path)]] << f
      end
      by.select { |_, v| v.size > 1 }
    end

    def ceiling
      File.exist?(CEILING) ? YAML.safe_load_file(CEILING).fetch("duplicate_sets", 0) : 0
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
      if ratchet && d.size < ceiling
        File.write(CEILING, { "duplicate_sets" => d.size }.to_yaml)
        puts "dup_census: recorded #{d.size} as the new low"
        return 0
      end
      return 0 unless d.size > ceiling

      d.sort_by { |(_, s), v| -s * (v.size - 1) }.first(10).each do |(_, size), v|
        puts "  #{size / 1024}KB x#{v.size}: #{v.join(' | ')[0, 150]}"
      end
      puts "dup_census: a tracked file now exists twice — collapse it or price the ceiling"
      1
    end
  end
end

exit Pub4::DupCensus.run(ratchet: ARGV.include?("--ratchet"), list: ARGV.include?("--list")) if $PROGRAM_NAME == __FILE__
