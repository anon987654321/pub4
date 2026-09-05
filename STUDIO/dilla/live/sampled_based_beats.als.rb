# frozen_string_literal: true

# The loop played as an instrument, and the kit played as a record.
#
# "Make old things sound new, and new things sound old." Old to new: a slice of
# a 1970s bed is retriggered as chords the record never played -- asetrate is
# sampler pitching, speed and pitch together, which is what an MPC does and why
# chopped soul sounds like that. New to old: our own kit and the master go
# through the 1260 and the console, so nothing arrives clean.
#
# This is the set the crate plays in. Everything sounding is the record: the
# chords are slices of it, the bed under them is it at length, and only the kit
# and the crackle are ours.
require_relative "rack"

TOTAL = 96
SEED = Rack.seed!

bed, slug, sw = Rack.pick_bed
# 0.92-0.96: a semitone and a half down at the deep end, a third of one at the
# shallow. Never none.
DRAG = (0.92 + rand * 0.04).round(4)
g = Rack.grid(bed, DRAG)
bar = g[:bar]
step = g[:step]

# Voicings, not scale runs. Each step is a chord built from one slice: root,
# a colour tone and an extension, so the sample states harmony it never had.
# Downward only. Pitching a sample UP thins it and speeds it -- the chipmunk
# sound -- and nothing in this lineage does it. The same chords voiced BELOW the
# root instead: an octave down puts the colour tone under the fundamental, which
# is where a sampler lands when you play the pads left of centre. Every interval
# here is zero or negative, and the drag sits under all of it.
VOICINGS = {
  min7:  [0, -9, -2],    # root, b3 an octave down, b7 a tone below the root
  maj9:  [0, -8, -10],   # root, 3rd down an octave, 9th further under
  min9:  [0, -9, -10],
  sus4:  [0, -7, -2],
  min11: [0, -9, -7],
}.freeze
# Movement with rests in it. nil is a rest, and the rests are what make the
# rest of it read as playing.
# Roots move down too, or the phrase climbs out of the register the drag put it
# in. Nothing rises above the sample's own pitch.
PROGRESSIONS = [
  [[0, :min7], nil, [-5, :min9], [-3, :maj9], nil, [-2, :sus4], [0, :min7], nil],
  [[0, :min9], [-3, :min7], nil, [-7, :sus4], [-5, :maj9], nil, [-3, :min7], [0, :min11]],
  [[-7, :min7], nil, [-5, :min9], nil, [-3, :maj9], [0, :min7], nil, [-4, :sus4]],
  [[0, :min11], [0, :min11], nil, [-2, :maj9], [-3, :min7], nil, [-5, :min9], nil],
].freeze
prog = PROGRESSIONS.sample
slice_at = (rand * 2.2).round(3)
reverse = rand < 0.28 # a reversed chop, sometimes

inputs = []
graph = []
live = []

prog.each_with_index do |cell, i|
  next if cell.nil?

  semi, voicing = cell
  ratios = VOICINGS.fetch(voicing).map { |iv| [((2.0**((semi + iv) / 12.0)) * DRAG), DRAG].min.round(6) }
  longest = (step * ratios.max * 1.8).round(4)
  inputs << "-ss #{slice_at} -t #{longest} -i #{bed.shellescape}"
  idx = inputs.size - 1
  graph << "[#{idx}:a]asplit=3[c#{i}a][c#{i}b][c#{i}c]"
  %w[a b c].each_with_index do |tag, v|
    rev = (reverse && v.zero?) ? "areverse," : ""
    graph << "[c#{i}#{tag}]asetrate=44100*#{ratios[v]},aresample=44100,#{rev}" \
             "atrim=0:#{step},volume=#{v.zero? ? 1.0 : 0.62}," \
             "afade=t=in:st=0:d=0.005,afade=t=out:st=#{(step - 0.03).round(4)}:d=0.03[v#{i}#{tag}]"
  end
  graph << "[v#{i}a][v#{i}b][v#{i}c]amix=inputs=3:normalize=0[ch#{i}]"
  live << i
end

# Rests are silence of exactly one step, so the phrase keeps the grid.
prog.each_index do |i|
  next if live.include?(i)

  inputs << "-f lavfi -t #{step} -i anullsrc=r=44100:cl=stereo"
  graph << "[#{inputs.size - 1}:a]atrim=0:#{step}[ch#{i}]"
end
graph << "#{prog.each_index.map { |i| "[ch#{i}]" }.join}concat=n=#{prog.size}:v=0:a=1," \
         "#{Rack.sonitex(bits: 12, lo: 90, hi: 9200, drive: 1.3)}," \
         "#{Rack.vcs(depth: 0.5, smear: 1.4)}," \
         "chorus=0.6:0.9:55:0.4:0.25:2," \
         "flanger=delay=4:depth=3:regen=22:speed=0.4," \
         "aecho=0.8:0.85:57|113:0.28|0.16," \
         "extrastereo=m=1.6[phrase]"

kit = Rack.drunk_kit(inputs.size, inputs, graph,
                     beat: g[:beat], bar: bar, step: step, sxt: g[:sxt], total: TOTAL)
hits = kit[:hits]
crackle_i = kit[:crackle_i]

inputs << "-stream_loop -1 -i #{bed.shellescape}"
bed_i = inputs.size - 1
graph << "[#{bed_i}:a]asetrate=44100*#{DRAG},aresample=44100," \
         "atrim=0:#{(bar * g[:bars_in_loop]).round(4)}," \
         "volume=0.42,lowpass=f=5200,aecho=0.8:0.7:60:0.3," \
         "#{Rack.sonitex(bits: 13, lo: 60, hi: 7200, drive: 1.1)}," \
         "#{Rack.vcs(depth: 0.55, smear: 1.1)}[under]"

graph << "[phrase][under][kit]amix=inputs=3:weights=0.30 0.14 3.4:" \
         "normalize=0:duration=longest," \
         "#{Rack.vcs(depth: 0.38, smear: 1.7)}," \
         "#{Rack.sonitex(bits: 12, lo: 40, hi: 13000, drive: 1.12)}," \
         "atrim=0:#{bar},asetpts=N/SR/TB[barmix]"

# Arrangement, not a loop on repeat: the phrase steps back for eight bars in the
# middle so the kit and the record carry it, then returns. A beat that never
# changes is a beat nobody listens to twice.
drop_from = (bar * 16).round(3)
drop_to = (bar * 24).round(3)
graph << "[barmix]aloop=loop=-1:size=#{(bar * 44100).round},atrim=0:#{TOTAL}," \
         "volume='if(between(t,#{drop_from},#{drop_to}),0.55,1.0)':eval=frame," \
         "vibrato=f=1.7:d=0.14," \
         "acompressor=threshold=0.4:ratio=3.2:attack=9:release=210[body]"
graph << "[#{crackle_i}:a]highpass=f=2200,volume=0.9," \
         "#{Rack.vcs(depth: 0.6, smear: 0.9)}[crackle]"
graph << "[body][crackle]amix=inputs=2:weights=1 0.34:normalize=0:duration=first," \
         "#{Rack.vcs(depth: 0.34, smear: 2.4)}," \
         "#{Rack.sonitex(bits: 10, lo: 46, hi: 11500, drive: 1.1)}," \
         "#{Rack.vcs(depth: 0.26, smear: 3.6)}," \
         "aecho=0.85:0.7:83|151|229:0.20|0.12|0.06," \
         "tremolo=f=#{(2.0 / bar).round(3)}:d=0.10," \
         "treble=g=3:f=6500,bass=g=4:f=95," \
         "dynaudnorm=f=200:g=9:p=0.94:m=18," \
         "volume=2.4," \
         "alimiter=limit=0.98:level=disabled," \
         "aformat=sample_rates=44100:channel_layouts=stereo[out]"

Rack.journal!(
  at: Time.now.utc.iso8601, seed: SEED, set: "sampled_based_beats", bed: slug, sample_worth: sw,
  bpm: g[:bpm], drag: DRAG, bars_in_loop: g[:bars_in_loop], progression: prog,
  chop_at: slice_at, reversed: reverse, bar_s: bar,
  weights: { phrase: 0.30, under: 0.14, kit: 3.4 },
  drums: { kick_ms: hits[:kick], snare_ms: hits[:snare], ghost_ms: hits[:ghost], hat_ms: hits[:hat] },
  sonitex: [13, 12, 12, 11, 10], vcs: 6, rig: "live/sampled_based_beats.als.rb"
)

Rack.play!(inputs, graph,
           "▶ sampled  #{slug}  sw=#{format('%.2f', sw.to_f)}  #{g[:bpm]}bpm " \
           "(#{g[:bars_in_loop]}bar loop, drag #{DRAG})  " \
           "#{prog.map { |c| c ? "#{c[0]}#{c[1]}" : '.' }.join(' ')}" \
           "#{reverse ? '  REV' : ''}  chop@#{slice_at}s")
