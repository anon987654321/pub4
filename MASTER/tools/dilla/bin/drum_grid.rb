#!/usr/bin/env ruby
# frozen_string_literal: true

# ASCII step-grid visualizer for the pocket drum layer (lib/groove_engine.rb).
# Exists because reasoning about [0, 6, 10, 13]-style step arrays in isolation
# repeatedly missed problems (rigid repetition, dead phrase pools, no
# render-to-render variation) that are obvious at a glance on a real grid.
#
# Usage: ruby bin/drum_grid.rb [n_bars] [render_seed]
#   POCKET_SET=dusty ruby bin/drum_grid.rb 16

require_relative "../dilla"

n_bars = (ARGV[0] || 16).to_i
seed = (ARGV[1] || rand(1_000_000)).to_i
ENV["DILLA_RENDER_SEED"] = seed.to_s

def row(steps, marker, width: 16)
  Array.new(width, ".").tap { |cells| Array(steps).each { |s| cells[s] = marker if s < width } }.join
end

puts "render_seed=#{seed} pocket_set=#{DillaGroove.pocket_set} dusty=#{DillaGroove.dusty_pocket?}"
puts "steps:      0123456789012345"
puts "-" * 40

n_bars.times do |bar|
  kicks  = DillaGroove.pocket_kicks(bar)
  snares = DillaGroove.pocket_snares_hard(bar)
  ghosts = DillaGroove.pocket_snares_ghost(bar)
  hats   = DillaGroove.pocket_hats(bar).reject { |s| DillaGroove.hat_should_drop?(bar, s) }
  open_h = DillaGroove.pocket_open_hat?(bar) ? [14] : []

  bar_label = format("%3d", bar)
  puts "#{bar_label} K: #{row(kicks, 'K')}"
  puts "    S: #{row(snares, 'S')}#{ghosts.any? ? "  ghost:#{ghosts}" : ''}"
  puts "    g: #{row(ghosts, 'g')}"
  puts "    H: #{row(hats, 'x')}#{open_h.any? ? '  +open' : ''}"
  puts
end

# Repetition check across the printed window -- the exact failure mode that
# kept slipping past isolated per-function testing.
kick_seq = (0...n_bars).map { |b| DillaGroove.pocket_kicks(b) }
puts "distinct kick shapes: #{kick_seq.uniq.length} / #{n_bars} bars"
puts "longest immediate repeat: #{kick_seq.each_cons(2).count { |a, b| a == b }} consecutive-bar repeats"
