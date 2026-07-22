#!/usr/bin/env ruby
# frozen_string_literal: true

# ASCII step-grid visualizer for the pocket drum layer (lib/groove_engine.rb).
# Exists because reasoning about [0, 6, 10, 13]-style step arrays in isolation
# repeatedly missed problems (rigid repetition, dead phrase pools, no
# render-to-render variation) that are obvious at a glance on a real grid.
#
# Usage: ruby bin/drum_grid.rb [n_bars] [render_seed]
#   POCKET_SET=dusty ruby bin/drum_grid.rb 16
#   DRUM_GRID_AB=1 ruby bin/drum_grid.rb 8      -- A/B: KICK_LATE/SNARE_EARLY on vs off
#   DRUM_GRID_SELFTEST=1 ruby bin/drum_grid.rb  -- just run the tick-authenticity self-test

require_relative "../dilla"

BPM = (ENV["BPM"] || 90).to_f
BEAT_P = 60.0 / BPM

def row(steps, marker, width: 16)
  Array.new(width, ".").tap { |cells| Array(steps).each { |s| cells[s] = marker if s < width } }.join
end

# --- Self-test: every role_timing_offset multiplier must be a whole tick ---
# (the exact regression class fixed tonight -- fractional-tick offsets are
# values no real 96-PPQ MPC3000 nudge could ever produce). Run standalone
# with DRUM_GRID_SELFTEST=1, or automatically at the end of a normal run.
def tick_authenticity_selftest
  tick_ms = (BEAT_P / 96.0) * 1000.0
  failures = []
  %i[snare clap kick_anchor kick_sync hat hat_up ghost].each do |role|
    offset_ms = DillaGroove.role_timing_offset(role, BEAT_P, 0, 1) * 1000.0
    next if offset_ms.zero?
    ticks = offset_ms / tick_ms
    failures << "#{role}: #{ticks.round(3)} ticks (not whole)" if (ticks - ticks.round).abs > 0.01
  end
  if failures.empty?
    puts "tick self-test: OK -- all role_timing_offset multipliers are whole ticks"
  else
    puts "tick self-test: FAIL"
    failures.each { |f| puts "  #{f}" }
  end
  failures.empty?
end

if ENV["DRUM_GRID_SELFTEST"] == "1"
  exit(tick_authenticity_selftest ? 0 : 1)
end

n_bars = (ARGV[0] || 16).to_i
seed = (ARGV[1] || rand(1_000_000)).to_i
ENV["DILLA_RENDER_SEED"] = seed.to_s

# Cycle sections so grid preview reflects section-aware rush / hat-drop.
GRID_SECTIONS = %i[intro main development breakdown climax hook].freeze

def section_for_bar(bar)
  GRID_SECTIONS[bar % GRID_SECTIONS.length]
end

def print_grid(n_bars, label: nil)
  puts "=== #{label} ===" if label
  (0...n_bars).each do |bar|
    section = section_for_bar(bar)
    kicks  = DillaGroove.pocket_kicks(bar)
    snares = DillaGroove.pocket_snares_hard(bar, section:)
    ghosts = DillaGroove.pocket_snares_ghost(bar)
    hats   = DillaGroove.pocket_hats(bar).reject { |s| DillaGroove.hat_should_drop?(bar, s, section:) }
    open_h = DillaGroove.pocket_open_hat?(bar) ? [14] : []

    kick_off = DillaGroove.role_timing_offset(:kick_sync, BEAT_P, bar, kicks.first || 0) * 1000.0
    snare_off = DillaGroove.role_timing_offset(:snare, BEAT_P, bar, snares.first || 0) * 1000.0
    hat_off = DillaGroove.role_timing_offset(:hat_down, BEAT_P, bar, hats.first || 0) * 1000.0

    bar_label = format("%3d", bar)
    puts "#{bar_label} K: #{row(kicks, 'K')}  (#{kick_off.round(1)}ms)  [#{section}]"
    puts "    S: #{row(snares, 'S')}#{ghosts.any? ? "  ghost:#{ghosts}" : ''}  (#{snare_off.round(1)}ms)"
    puts "    g: #{row(ghosts, 'g')}"
    puts "    H: #{row(hats, 'x')}#{open_h.any? ? '  +open' : ''}  (#{hat_off.round(1)}ms)"
    puts
  end
end

def repetition_report(n_bars)
  {
    kicks: (0...n_bars).map { |b| DillaGroove.pocket_kicks(b) },
    snares: (0...n_bars).map { |b| DillaGroove.pocket_snares_hard(b, section: section_for_bar(b)) },
    hats: (0...n_bars).map { |b| DillaGroove.pocket_hats(b) },
    ghosts: (0...n_bars).map { |b| DillaGroove.pocket_snares_ghost(b) },
  }.each do |name, seq|
    repeats = seq.each_cons(2).count { |a, b| a == b }
    puts "#{name}: #{seq.uniq.length}/#{n_bars} distinct shapes, #{repeats} consecutive-bar repeats"
  end
end

def drift_graph(n_bars)
  puts "phrase drift (ms), one row per role, sparkline across bars:"
  chars = " .:-=+*#%@"
  %i[kick snare hat ghost].each do |role|
    vals = (0...n_bars).map { |b| DillaGroove.phrase_drift_sec(b, role:) * 1000.0 }
    max = vals.map(&:abs).max
    max = 1.0 if max.nil? || max.zero?
    spark = vals.map { |v| chars[(((v / max) + 1.0) / 2.0 * (chars.length - 1)).round.clamp(0, chars.length - 1)] }.join
    puts format("  %-6s %s  (range %.1f..%.1fms)", role, spark, vals.min.round(1), vals.max.round(1))
  end
end

if ENV["DRUM_GRID_AB"] == "1"
  puts "render_seed=#{seed} bpm=#{BPM} -- A/B: role_timing_offset ON vs OFF"
  puts "-" * 40
  print_grid(n_bars, label: "A: KICK_LATE/SNARE_EARLY/HATS_LATE ON (default)")
  ENV["KICK_LATE"] = "0"
  ENV["SNARE_EARLY"] = "0"
  ENV["HATS_LATE"] = "0"
  print_grid(n_bars, label: "B: KICK_LATE/SNARE_EARLY/HATS_LATE OFF")
else
  puts "render_seed=#{seed} bpm=#{BPM} pocket_set=#{DillaGroove.pocket_set} dusty=#{DillaGroove.dusty_pocket?}"
  puts "steps:      0123456789012345"
  puts "-" * 40
  print_grid(n_bars)
  repetition_report(n_bars)
  puts
  drift_graph(n_bars)
  puts
  tick_authenticity_selftest
end
