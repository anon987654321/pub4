# The builtin progressions, played.
#
# dilla.rb carries 401 named chord progressions -- transcribed, curated and
# device tables -- and until now they only sounded inside a full render. The
# other two sets in this room are the crate: everything sounding in them is a
# record. This one is the opposite and exists for the contrast. Nothing here is
# sampled. Every voice is a sine stacked into a chord the table names, and the
# only thing it shares with the crate sets is the room they go through.
#
# dilla.rb is loaded for the tables rather than copied from, and for
# chord_template_for, which is the mapping from a chord's name to its intervals.
# Copied, the two would voice the same symbol differently within a month, and
# the progressions are the whole content of this set. It costs 0.8s against a
# 96-second block.
# dilla first: it runs bundler/setup, and anything that has already activated a
# gem the Gemfile pins differently sends it down its inline-theory fallback with
# a warning. rack.rb requires json, so loading it first is enough to do that.
require_relative "../dilla"
require_relative "rack"

TOTAL = 96
# A2 to A3. The beat sets pitch a record down and never above its own note;
# there is no record here to stay under, so the equivalent discipline is a low
# register and a ceiling -- a synthesised chord voiced high is the one thing in
# this room that would sound like a plugin.
ROOT_A = 110.0

NOTE_PC = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }.freeze
# The tables were written by ear over years and they spell chords the way a
# person writing them down does, not the way a parser wants: "C7#9 Hendrix"
# carries a note to the reader, "Ebm7fil" a filter tag, "m9overC" a slash chord
# without the slash, and "maj9nc"/"maj9low" a rendering instruction. All of it
# is after the quality and none of it changes which notes sound, so it comes off
# before the lookup. Measured over all 288 distinct symbols in the tables: every
# one parses, and every quality resolves to a real template.
ALIAS = { "m" => "min", "7sus" => "9sus", "7sus4" => "9sus4", "mMaj7" => "mmaj7" }.freeze

def parse_chord(sym)
  s = sym.to_s.split(/\s+/).first.to_s
  bass = nil
  if (m = s.match(%r{(?:/|over)([A-G])([b#]?)\z}))
    bass = pc_of(m[1], m[2])
    s = s[0...m.begin(0)]
  end
  s = s.sub(/(?:fil|nc|low|climax)\z/, "").sub("s11", "#11")
  m = s.match(/\A([A-G])([b#]?)(.*)\z/) or return nil

  q = m[3].sub(/\AMaj/, "maj")
  q = "maj" if q.empty?
  [pc_of(m[1], m[2]), ALIAS.fetch(q, q), bass]
end

def pc_of(letter, acc) = (NOTE_PC.fetch(letter) + (acc == "b" ? -1 : acc == "#" ? 1 : 0)) % 12

# Four or eight chords. Two is a vamp with no arc and sixteen outruns a
# 96-second block at this tempo, so both are left to the full renderer.
name, symbols = CHORD_PROGRESSIONS.select { |_, v| [4, 8].include?(v.length) }.to_a.sample
chords = symbols.filter_map { |s| [s, parse_chord(s)] if parse_chord(s) }

# No record, so no record to take a tempo from. 82-94 is where the crate sits
# once the drag is on it, and the kit is the same drunk kit, so the two beat
# sets sit at the same count and can follow each other.
bpm = (82 + rand * 12).round(1)
beat = (60.0 / bpm).round(4)
bar = (beat * 4).round(4)
step = (beat / 2).round(4)
sxt = (beat / 4).round(4)
chord_s = (bar * (chords.size == 8 ? 0.5 : 1.0)).round(4)

inputs = []
graph = []

chords.each_with_index do |(sym, (pc, quality, bass)), i|
  root = ROOT_A * (2**(pc / 12.0))
  # dilla's own voicing, so a symbol sounds here as it sounds in a render.
  hz = chord_from_root(root, quality, voices: 4)
  # A slash bass is the point of a slash chord: the note under everything,
  # an octave below the voicing rather than inside it.
  hz = [(ROOT_A / 2) * (2**(bass / 12.0))] + hz if bass
  hz.each_with_index do |f, v|
    # Detuned by a few cents, alternating side. Four exact sines beat against
    # nothing and read as a test tone; a couple of cents apart they read as an
    # instrument, which is the cheapest honest way to get there.
    cents = v.zero? ? 0 : ((v.odd? ? 1 : -1) * (3 + v))
    f2 = (f * (2**(cents / 1200.0))).round(3)
    inputs << "-f lavfi -t #{(chord_s + 0.6).round(4)} -i sine=f=#{f2}:d=#{(chord_s + 0.6).round(4)}"
    idx = inputs.size - 1
    # Struck, not held: a fast front and a decay across the chord's length is
    # what makes this a beat set rather than the pad set with a synth in it.
    graph << "[#{idx}:a]atrim=0:#{chord_s},volume=#{(0.5 / (v + 1.4)).round(3)}," \
             "afade=t=in:st=0:d=0.012," \
             "afade=t=out:st=#{(chord_s * 0.22).round(3)}:d=#{(chord_s * 0.78).round(3)}[n#{i}v#{v}]"
  end
  graph << "#{(0...hz.size).map { |v| "[n#{i}v#{v}]" }.join}" \
           "amix=inputs=#{hz.size}:normalize=0," \
           "lowpass=f=2600,highpass=f=70[chd#{i}]"
end

graph << "#{chords.each_index.map { |i| "[chd#{i}]" }.join}concat=n=#{chords.size}:v=0:a=1," \
         "#{Rack.sonitex(bits: 12, lo: 70, hi: 7600, drive: 1.22)}," \
         "#{Rack.vcs(depth: 0.5, smear: 1.6)}," \
         "chorus=0.6:0.9:48|72:0.4|0.3:0.22|0.3:1.8|2.6," \
         "aecho=0.8:0.85:97|181:0.30|0.18," \
         "tremolo=f=#{(1.0 / bar).round(3)}:d=0.12," \
         "extrastereo=m=1.5[phrase]"

kit = Rack.drunk_kit(inputs.size, inputs, graph,
                     beat: beat, bar: bar, step: step, sxt: sxt, total: TOTAL)
hits = kit[:hits]
crackle_i = kit[:crackle_i]

phrase_s = (chord_s * chords.size).round(4)
graph << "[phrase][kit]amix=inputs=2:weights=0.62 2.9:normalize=0:duration=first," \
         "#{Rack.vcs(depth: 0.38, smear: 1.7)}," \
         "#{Rack.sonitex(bits: 12, lo: 40, hi: 13000, drive: 1.12)}," \
         "atrim=0:#{phrase_s},asetpts=N/SR/TB[barmix]"

# The same arrangement rule as the sampled set: the harmony steps back in the
# middle so the kit carries it, then returns. Measured in phrases here rather
# than bars, because a phrase is four or eight chords and the drop has to land
# on one of them.
drop_from = (phrase_s * 2).round(3)
drop_to = (phrase_s * 3).round(3)
graph << "[barmix]aloop=loop=-1:size=#{(phrase_s * 44100).round},atrim=0:#{TOTAL}," \
         "volume='if(between(t,#{drop_from},#{drop_to}),0.5,1.0)':eval=frame," \
         "vibrato=f=1.5:d=0.11," \
         "acompressor=threshold=0.4:ratio=3.2:attack=9:release=210[body]"
graph << "[#{crackle_i}:a]highpass=f=2200,volume=0.9," \
         "#{Rack.vcs(depth: 0.6, smear: 0.9)}[crackle]"
graph << "[body][crackle]amix=inputs=2:weights=1 0.30:normalize=0:duration=first," \
         "#{Rack.vcs(depth: 0.34, smear: 2.4)}," \
         "#{Rack.sonitex(bits: 10, lo: 46, hi: 11500, drive: 1.1)}," \
         "#{Rack.vcs(depth: 0.26, smear: 3.6)}," \
         "aecho=0.85:0.7:83|151|229:0.20|0.12|0.06," \
         "treble=g=3:f=6500,bass=g=4:f=95," \
         "dynaudnorm=f=200:g=9:p=0.94:m=18," \
         "volume=2.4," \
         "alimiter=limit=0.98:level=disabled," \
         "aformat=sample_rates=44100:channel_layouts=stereo[out]"

Rack.journal!(
  at: Time.now.utc.iso8601, set: "chord_based_beats", bed: nil, progression_name: name.to_s,
  progression: symbols, bpm: bpm, bar_s: bar, chord_s: chord_s,
  weights: { phrase: 0.62, kit: 2.9, crackle: 0.30 },
  drums: { kick_ms: hits[:kick], snare_ms: hits[:snare], ghost_ms: hits[:ghost], hat_ms: hits[:hat] },
  sonitex: [12, 12, 11, 10], vcs: 6, rig: "live/chord_based_beats.als.rb"
)

Rack.play!(inputs, graph,
           "▶ chords  #{name}  #{bpm}bpm  #{chords.size} chords @ #{chord_s}s  " \
           "#{symbols.join(' ')}")
