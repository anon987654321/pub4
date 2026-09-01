# The same crate, held instead of struck.
#
# A chop is a short thing by construction -- best_trim hunts a two-to-fourteen
# second repeat, and the beat sets play it in eighth-note stabs. Held for two
# bars at a time the same slice stops being a stab and becomes a pad, and what
# was a rhythm part turns into the room it was recorded in. Nothing is
# synthesised here: every sustained voice is the record, slowed, stacked under
# itself and given time.
#
# No kit. A pad set with drums in it is a beat with the drums turned down, and
# the point of this set is the absence -- it is what plays when the room should
# sound like something without anyone having to follow it.
require_relative "rack"

TOTAL = 180
# Deeper than the beat sets. Their 0.92-0.96 keeps a bed danceable; a pad is
# allowed to sit a whole tone under the record, and the slower it runs the more
# of the tail you hear, which is the material this set is made of.
DRAG = (0.86 + rand * 0.05).round(4)

bed, slug, sw = Rack.pick_bed
# Two bars per chord, so the grid wants a slower count than the beat sets ask
# for: 60-84 rather than 76-104.
g = Rack.grid(bed, DRAG, want: 70, range: 60..84)
bar = g[:bar]
hold = (bar * 2).round(4)

# Wider than the beat sets' voicings and further down. A stab reads as a chord
# from three close tones; a pad held for two bars needs the octave underneath it
# or the stack beats against itself. Every interval is zero or negative, as
# everywhere else here: nothing plays above the record's own pitch.
VOICINGS = {
  min9:  [0, -12, -9, -22],
  maj9:  [0, -12, -8, -22],
  sus4:  [0, -12, -7, -19],
  min11: [0, -12, -9, -17],
}.freeze
# Four chords, eight bars, and the arc lands back where it started. A pad
# progression that resolves somewhere else asks to be followed; this one does
# not ask anything.
PROGRESSIONS = [
  [[0, :min9], [-5, :maj9], [-3, :sus4], [0, :min11]],
  [[0, :sus4], [-2, :min9], [-7, :maj9], [-5, :min9]],
  [[-3, :maj9], [-5, :min11], [0, :min9], [-2, :sus4]],
].freeze
prog = PROGRESSIONS.sample
slice_at = (rand * 1.6).round(3)

inputs = []
graph = []

prog.each_with_index do |(semi, voicing), i|
  ratios = VOICINGS.fetch(voicing).map { |iv| [((2.0**((semi + iv) / 12.0)) * DRAG), DRAG].min.round(6) }
  ratios.each_with_index do |r, v|
    # asetrate divides the duration by the ratio, so the slice taken has to be
    # `hold * r` long to come back out as `hold`. Half a second of margin: a
    # slice that runs out mid-pad gates, and a gate is the one thing a pad
    # cannot survive.
    inputs << "-ss #{slice_at} -t #{(hold * r + 0.5).round(4)} -i #{bed.shellescape}"
    idx = inputs.size - 1
    # Long in, longer out, and they overlap between chords -- the fade tail of
    # one is still sounding when the next arrives, which is what makes four
    # separate slices read as one moving surface rather than four events.
    graph << "[#{idx}:a]asetrate=44100*#{r},aresample=44100,atrim=0:#{hold}," \
             "volume=#{v.zero? ? 0.9 : (0.62 - (v * 0.11)).round(2)}," \
             "afade=t=in:st=0:d=#{(hold * 0.35).round(3)}," \
             "afade=t=out:st=#{(hold * 0.45).round(3)}:d=#{(hold * 0.55).round(3)}[p#{i}v#{v}]"
  end
  graph << "#{(0...ratios.size).map { |v| "[p#{i}v#{v}]" }.join}" \
           "amix=inputs=#{ratios.size}:normalize=0[pad#{i}]"
end

# Gentler than the beat sets: 13 bits and a 6 kHz ceiling, because the crush
# that reads as grit on a stab reads as hiss on something held.
graph << "#{prog.each_index.map { |i| "[pad#{i}]" }.join}concat=n=#{prog.size}:v=0:a=1," \
         "#{Rack.sonitex(bits: 13, lo: 55, hi: 6200, drive: 1.05)}," \
         "#{Rack.vcs(depth: 0.55, smear: 2.8)}," \
         "chorus=0.7:0.9:70|95:0.45|0.3:0.2|0.28:1.6|2.4," \
         "aecho=0.9:0.85:180|340|610:0.42|0.28|0.17," \
         "extrastereo=m=1.9[phrase]"

inputs << "-stream_loop -1 -i #{bed.shellescape}"
bed_i = inputs.size - 1
# The record itself, far down and far back. Not a bed to hear -- a bed to notice
# the absence of, which is what keeps the pads from sounding synthesised.
graph << "[#{bed_i}:a]asetrate=44100*#{(DRAG * 0.5).round(6)},aresample=44100," \
         "atrim=0:#{(hold * prog.size).round(4)},volume=0.18," \
         "lowpass=f=1800,aecho=0.9:0.8:420:0.4," \
         "#{Rack.sonitex(bits: 12, lo: 40, hi: 2600, drive: 1.0)}," \
         "#{Rack.vcs(depth: 0.6, smear: 3.2)}[under]"

inputs << "-f lavfi -t #{TOTAL} -i anoisesrc=c=pink:d=#{TOTAL}:a=0.010"
air_i = inputs.size - 1
graph << "[#{air_i}:a]lowpass=f=4200,volume=0.7,#{Rack.vcs(depth: 0.5, smear: 4.0)}[air]"

phrase_s = (hold * prog.size).round(4)
graph << "[phrase][under]amix=inputs=2:weights=1.0 0.5:normalize=0:duration=first," \
         "atrim=0:#{phrase_s},asetpts=N/SR/TB[cycle]"
# One slow breath across the whole block rather than a tremolo rate:
# 1/(phrase*2) puts the swell either side of the loop point, so the place the
# cycle restarts is the place it is quietest.
graph << "[cycle]aloop=loop=-1:size=#{(phrase_s * 44100).round},atrim=0:#{TOTAL}," \
         "volume='0.72+0.28*sin(2*PI*t/#{(phrase_s * 2).round(3)})':eval=frame," \
         "vibrato=f=0.28:d=0.06," \
         "acompressor=threshold=0.5:ratio=2.4:attack=180:release=900[body]"
graph << "[body][air]amix=inputs=2:weights=1 0.30:normalize=0:duration=first," \
         "#{Rack.vcs(depth: 0.3, smear: 4.4)}," \
         "#{Rack.sonitex(bits: 12, lo: 42, hi: 9000, drive: 1.04)}," \
         "aecho=0.88:0.75:730|1130:0.24|0.14," \
         "treble=g=-2:f=7000,bass=g=3:f=110," \
         "dynaudnorm=f=400:g=13:p=0.9:m=10," \
         "volume=1.9," \
         "alimiter=limit=0.97:level=disabled," \
         "aformat=sample_rates=44100:channel_layouts=stereo[out]"

Rack.journal!(
  at: Time.now.utc.iso8601, set: "ambient_pads", bed: slug, sample_worth: sw,
  bpm: g[:bpm], drag: DRAG, bars_in_loop: g[:bars_in_loop], progression: prog,
  chop_at: slice_at, hold_s: hold, bar_s: bar, drums: nil,
  weights: { phrase: 1.0, under: 0.5, air: 0.30 },
  sonitex: [13, 12, 12], vcs: 5, rig: "live/ambient_pads.als.rb"
)

Rack.play!(inputs, graph,
           "▶ pads  #{slug}  sw=#{format('%.2f', sw.to_f)}  #{g[:bpm]}bpm " \
           "(#{g[:bars_in_loop]}bar loop, drag #{DRAG})  hold #{hold}s  " \
           "#{prog.map { |semi, v| "#{semi}#{v}" }.join(' ')}  chop@#{slice_at}s")
