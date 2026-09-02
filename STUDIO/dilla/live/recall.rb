#!/usr/bin/env ruby
# frozen_string_literal: true

# Play a pass again, and keep the ones worth keeping.
#
# This is the half that makes these sets rather than a generator. A set opens
# the same way every time; that is most of what a set is, and until a pass could
# be named and reopened these were three scripts that made something different
# every ninety-six seconds and then forgot it.
#
# Every pass writes a line to project/liveset.jsonl carrying its seed and its
# bed, and those two reopen it: the seed replays every choice the PRNG made, and
# the bed is pinned separately because pick_bed reads the journal for recency
# and the journal grows, so a seed alone lands somewhere else tomorrow.
#
#   live/recall.rb                    the last twenty passes
#   live/recall.rb 41205993           play that one again
#   live/recall.rb 41205993 --keep    render it to renders/live_<seed>/
#   live/recall.rb --keep             keep the pass that just played
#
# A kept take writes its wav beside a .json that names everything about it. The
# wav is gitignored, as every render here is; the json is not, so the take
# survives this machine even when the audio does not, and the seed rebuilds it.
require "fileutils"
require "rbconfig"
require "json"

D = File.expand_path("..", __dir__)
JOURNAL = File.join(D, "project", "liveset.jsonl")
RENDERS = File.join(D, "renders")

def passes
  return [] unless File.file?(JOURNAL)

  File.readlines(JOURNAL).filter_map do |line|
    row = JSON.parse(line) rescue next
    row if row["seed"] && row["set"]
  end
end

def show(rows)
  if rows.empty?
    puts "no seeded passes yet -- play a set and it will name itself"
    return
  end
  rows.last(20).each do |r|
    puts format("  %-10s %-20s %-28s %6s bpm  %s", r["seed"], r["set"],
                r["bed"] || r["progression_name"] || "-", r["bpm"], r["at"])
  end
  puts "\n  live/recall.rb <seed>          play it again"
  puts "  live/recall.rb <seed> --keep   render it to renders/"
end

keep = ARGV.delete("--keep")
seed = ARGV.shift

rows = passes
if seed.nil? && !keep
  show(rows)
  exit 0
end

# --keep with no seed means the one just played, which is the way it is actually
# wanted: something goes past, it was good, and reaching for the number is one
# step too many at that moment.
row = seed ? rows.reverse.find { |r| r["seed"].to_s == seed.to_s } : rows.last
abort(seed ? "no pass with seed #{seed}" : "nothing in the journal yet") unless row

env = { "LIVE_SEED" => row["seed"].to_s }
env["LIVE_BED"] = row["bed"].to_s if row["bed"]
# The kit is part of the take, not part of the environment. Replaying a
# sampled pass under whatever LIVE_KIT happens to be exported would come back
# with different drums and the same seed printed over them.
env["LIVE_KIT"] = row["kit"].to_s if row["kit"]
label = "#{row['set']} #{row['seed']}"

if keep
  dir = File.join(RENDERS, "live_#{row['seed']}")
  FileUtils.mkdir_p(dir)
  env["LIVE_RENDER_TO"] = File.join(dir, "#{row['set']}.wav")
  # The journal line is the sidecar. It already holds every decision the pass
  # made, so writing a second description of it would be a second source.
  File.write(File.join(dir, "take.json"), JSON.pretty_generate(row))
  warn "keeping #{label} -> #{dir}"
else
  warn "replaying #{label}"
end

exec(env, RbConfig.ruby, File.join(D, "live", "#{row['set']}.als.rb"))
