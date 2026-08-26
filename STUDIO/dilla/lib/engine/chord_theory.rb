# frozen_string_literal: true
#
# Chord theory: templates, scales, key detection, transposition, voicings.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

CHORD_TEMPLATES = {
  "maj" => [0, 4, 7],
  "min" => [0, 3, 7],
  "7" => [0, 4, 7, 10],
  "maj7" => [0, 4, 7, 11],
  "m7" => [0, 3, 7, 10],
  "m9" => [0, 3, 7, 10, 2],
  "maj9" => [0, 4, 7, 11, 2],
  "sus" => [0, 5, 7],
  "dim" => [0, 3, 6],
  # No natural fifth. "alt" means the fifth AND the ninth are altered; with a
  # perfect fifth at 7 this was a 7b9 wearing an altered dominant's name, and
  # the engine held both spellings at once -- DillaProducerDNA::CHORD_TEMPLATES
  # has [0, 4, 8, 10, 1] for the same symbol. Which chord you got depended on
  # whether the render reached chord_from_quality (this table) or build_voicing
  # (that one), and both are live. Across the 15 symbols the two tables share,
  # this was the only disagreement; test_chord_tables_agree pins that.
  "7alt" => [0, 4, 8, 10, 1],
  "7#11" => [0, 4, 7, 10, 6],
  "m11" => [0, 3, 7, 10, 5],
  "sus4" => [0, 5, 7, 10],
  "aug" => [0, 4, 8],
  "6" => [0, 4, 7, 9],
}.freeze

# Real progression generator (not a lookup table) — a weighted-random walk
# over scale-degree functional harmony, the same tonic/predominant/dominant
# circulation Bach's chorales and jazz standards both run on: I tends
# toward IV/V/vi, ii/IV lean toward V, V resolves to I, vi wanders through
# ii/IV before finding its way back. Extended qualities (m9/maj9/dominant7)
# keep it in the same lush-pad harmonic language as the researched
# progressions rather than plain triads.
SCALE_DEGREE_QUALITY = {
  major: { 1 => "maj9", 2 => "m9", 3 => "m7", 4 => "maj9", 5 => "7", 6 => "m9", 7 => "dim" },
  minor: { 1 => "m9", 2 => "dim", 3 => "maj9", 4 => "m9", 5 => "7", 6 => "maj9", 7 => "7" },
}.freeze
SCALE_SEMITONES = {
  major: [0, 2, 4, 5, 7, 9, 11],
  minor: [0, 2, 3, 5, 7, 8, 10],
}.freeze
# Degree -> {next_degree => relative weight}. Standard functional motion:
# tonic radiates outward, predominants (ii/IV) gravitate to the dominant,
# the dominant resolves home, vi is the deceptive detour.
DEGREE_TRANSITIONS = {
  1 => { 4 => 3, 5 => 3, 6 => 2, 2 => 1 },
  2 => { 5 => 4, 7 => 1, 4 => 1 },
  3 => { 6 => 2, 4 => 1, 2 => 1 },
  4 => { 5 => 3, 1 => 2, 2 => 1 },
  5 => { 1 => 4, 6 => 1, 4 => 1 },
  6 => { 2 => 2, 4 => 2, 5 => 1 },
  7 => { 1 => 3, 3 => 1 },
}.freeze

def weighted_pick(rng, weights)
  total = weights.values.sum
  roll = rng.rand(total)
  acc = 0
  weights.each do |value, weight|
    acc += weight
    return value if roll < acc
  end
  weights.keys.first
end

# Generates a fresh progression by scale-degree random walk rather than
# picking from CHORD_PROGRESSIONS. root_hz sets the key center, mode is
# :major or :minor, length is chord count. Same seed -> same progression,
# so a track can be reproduced; no seed -> genuinely new each render.
# Raises upper extensions into the octave they belong in.
#
# CHORD_TEMPLATES writes m9 as [0,3,7,10,2] and 7b9 as [0,4,7,10,1]. Those
# trailing small numbers are ninths, but taken literally they voice as a major
# or minor SECOND against the root -- a cluster, not an extension. That is why
# altered chords sounded blunt even after the qualities were mapped correctly:
# the note was present and in the wrong octave, which is audibly worse than
# absent.
#
# The template's own ordering says which is which: intervals ascend through the
# chord tones, so any interval smaller than one already seen is an extension
# written in its simple form. m9 becomes [0,3,7,10,14], 7b9 [0,4,7,10,13],
# 7#11 [0,4,7,10,18].
#
# One implementation, in the module that owns the templates. This file carried a
# byte-identical copy.
def voice_extensions(intervals)
  DillaLofiMachine.voice_extensions(intervals)
end

# 6, not 5. Templates like 13 and maj13 carry six chord tones, and at five the
# sixth was silently dropped -- always the topmost after sorting, which is the
# extension that names the chord.
# There are two CHORD_TEMPLATES tables with different coverage -- this file's
# and DillaLofiMachine's, which carries m7b5, 7b9, 13, maj13, mmaj7 and m6 that
# this one lacks. A caller has no way to know which qualities live where, and
# the failure is a bare KeyError from deep inside a render. Fall through to the
# other table rather than making every caller guess.
def chord_template_for(quality)
  CHORD_TEMPLATES[quality] ||
    DillaLofiMachine::CHORD_TEMPLATES[quality] ||
    CHORD_TEMPLATES.fetch("maj9")
end

def chord_from_root(root_hz, quality, voices: 6)
  intervals = voice_extensions(chord_template_for(quality))
  hz = intervals.map { |iv| (root_hz * (2**(iv / 12.0))).round(2) }
  # See pad_voicing: doubled thirds and sevenths, not stacked roots. One padding
  # rule for both callers; only the trim below differs.
  DillaLofiMachine.pad_voicing(hz, root_hz, intervals, voices)
  hz.sort.first(voices)
end

# --- keeping a sampled loop's harmony -----------------------------------------
#
# A sampled loop brings its own key with it. If the engine generates pads in a
# different one, the two are out of tune with each other and no amount of
# mixing fixes that. This measures what key the loop is in and moves the
# generated harmony onto it.
#
# Goertzel per semitone rather than an FFT: only 12 pitch classes matter here,
# and this needs no gem and no sidecar file.
# On by default: layering something that disagrees with the sample is a worse
# outcome than layering nothing, so the guard has to be the default rather than
# a flag someone remembers to set. HARMONIC_GUARD=0 turns it off.
HARMONIC_GUARD = ENV.fetch("HARMONIC_GUARD", "1") != "0"
# 0.55 sits below every musically sensible cut measured here (0.697, 0.71,
# 0.836) and above the reading from a cut taken off the wrong part of a record
# (0.27), so it separates the two cases without being tuned to either.
HARMONIC_GUARD_MIN = (ENV["HARMONIC_GUARD_MIN"] || 0.55).to_f
# Below this the root itself is a guess and everything tonal drops out. Between
# the two the root stands but the mode does not, and the pads voice without
# thirds. 0.36 is under the 0.27 misfit measured on a badly placed cut plus a
# margin, and well under the 0.54 of a cut that was merely modally ambiguous.
HARMONIC_MUTE_MIN = (ENV["HARMONIC_MUTE_MIN"] || 0.36).to_f

HARMONIC_KEEP = ENV["HARMONIC_KEEP"] == "1"
HARMONIC_SHUFFLE = ENV["HARMONIC_SHUFFLE"] == "1"
CHROMA_RATE = 22_050
CHROMA_BLOCK_SEC = 0.5
CHROMA_ANALYSIS_SEC = 8.0
CHROMA_LOW_HZ = 60.0
CHROMA_HIGH_HZ = 2000.0

# Krumhansl-Schmuckler key profiles: how strongly each scale degree is weighted
# in music that is actually in that key. Correlating a measured chroma against
# all 24 rotations is the standard way to name a key from audio.
KRUMHANSL_MAJOR = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88].freeze
KRUMHANSL_MINOR = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17].freeze

def goertzel_magnitude(block, freq)
  coeff = 2.0 * Math.cos(2.0 * Math::PI * freq / CHROMA_RATE)
  prev = 0.0
  prev2 = 0.0
  block.each do |x|
    cur = x + (coeff * prev) - prev2
    prev2 = prev
    prev = cur
  end
  Math.sqrt([(prev * prev) + (prev2 * prev2) - (coeff * prev * prev2), 0.0].max)
end

def sample_chroma(path)
  @sample_chroma_cache ||= {}
  return @sample_chroma_cache[path] if @sample_chroma_cache.key?(path)

  @sample_chroma_cache[path] = begin
    raw = IO.popen(["ffmpeg", "-v", "error", "-t", CHROMA_ANALYSIS_SEC.to_s, "-i", path,
                    "-ac", "1", "-ar", CHROMA_RATE.to_s, "-f", "s16le", "-"], "rb", &:read)
    samples = raw.to_s.unpack("s<*").map { |s| s / PCM16_FULL_SCALE }
    if samples.empty?
      nil
    else
      block = (CHROMA_RATE * CHROMA_BLOCK_SEC).to_i
      acc = Array.new(12, 0.0)
      (0...(samples.size / block)).each do |b|
        chunk = samples[b * block, block]
        next unless chunk && chunk.size == block

        (2..6).each do |octave|
          12.times do |pc|
            freq = 440.0 * (2.0**(((octave * 12) + pc - 57) / 12.0))
            next unless freq.between?(CHROMA_LOW_HZ, CHROMA_HIGH_HZ)

            acc[pc] += goertzel_magnitude(chunk, freq)
          end
        end
      end
      peak = acc.max
      peak.positive? ? acc.map { |v| v / peak } : nil
    end
  rescue StandardError => e
    warn "chroma: #{e.message}"
    nil
  end
end

def correlate(a, b)
  ma = a.sum / a.size
  mb = b.sum / b.size
  num = (0...a.size).sum { |i| (a[i] - ma) * (b[i] - mb) }
  den = Math.sqrt((0...a.size).sum { |i| (a[i] - ma)**2 } * (0...b.size).sum { |i| (b[i] - mb)**2 })
  den.positive? ? num / den : 0.0
end

# => [root_pitch_class, :major|:minor, fit] or nil
def sample_key(path)
  ch = sample_chroma(path)
  return nil unless ch

  best = nil
  12.times do |rot|
    rotated = Array.new(12) { |i| ch[(i + rot) % 12] }
    { major: KRUMHANSL_MAJOR, minor: KRUMHANSL_MINOR }.each do |mode, template|
      fit = correlate(rotated, template)
      best = [rot, mode, fit] if best.nil? || fit > best[2]
    end
  end
  best
end

def hz_to_pitch_class(hz)
  return 0 unless hz.to_f.positive?

  ((69 + (12 * Math.log2(hz / 440.0))).round % 12)
end

NOTE_TO_PITCH_CLASS = {
  "C" => 0, "C#" => 1, "Db" => 1, "D" => 2, "D#" => 3, "Eb" => 3, "E" => 4,
  "F" => 5, "F#" => 6, "Gb" => 6, "G" => 7, "G#" => 8, "Ab" => 8, "A" => 9,
  "A#" => 10, "Bb" => 10, "B" => 11
}.freeze

# Shifts every note letter in a chord symbol, root and slash bass alike, so
# "Bbm/E" transposed up 3 becomes "Dbm/G". Lower-case suffixes (m, maj, sus,
# nc) and digits are left alone -- only capital A-G names a pitch here.
def transpose_chord_name(name, shift)
  return name if shift.zero?

  name.to_s.gsub(/([A-G])([b#]?)/) do
    pc = NOTE_TO_PITCH_CLASS["#{Regexp.last_match(1)}#{Regexp.last_match(2)}"]
    pc ? PITCH_CLASSES[(pc + shift) % 12] : Regexp.last_match(0)
  end
end

# Moves every chord by the interval between the pads' own root and the loop's,
# choosing the shorter direction so the pads do not jump an octave to get there.
#
# Names move with the frequencies. Transposing :hz alone leaves the labels
# describing the harmony before the transpose, and since beauty_report scores
# off c[:name] the reported score then describes a progression nobody rendered.
def transpose_pads_to(pads, target_pc)
  return pads if pads.empty?

  current_pc = hz_to_pitch_class(pads.first[:hz].min)
  shift = (target_pc - current_pc) % 12
  shift -= 12 if shift > 6
  return pads if shift.zero?

  factor = 2.0**(shift / 12.0)
  pads.map do |c|
    c.merge(hz: c[:hz].map { |h| (h * factor).round(2) },
            name: transpose_chord_name(c[:name], shift))
  end
end

# Reorders chords so their top voice traces one arc -- up to a peak, then down
# -- instead of wandering. The melody a listener follows is the top note of each
# chord, so ordering by that is ordering the tune. The first chord stays put:
# it is the harmonic home, and an arc that does not start at home is a
# different wander.
# Rebuilds every chord as root, fifth and ninth -- no third.
#
# The third is the note that says major or minor. Drop it and the chord commits
# to neither, which is what you want under a sample whose mode you could not
# read: it cannot clash with a reading it never made. What is left is open and
# slightly austere, the sound of a fifth ringing, and it sits under a horn line
# or a string section without arguing with either.
#
# The ninth is included because root-and-fifth alone is thin across a whole
# track. A ninth is two fifths stacked, so it belongs to the same consonance and
# still names no mode.
QUINTAL_INTERVALS = [0, 7, 14].freeze

def quintal_voicing(pads)
  pads.map do |chord|
    root = chord[:hz].min
    next chord unless root.to_f.positive?

    chord.merge(
      hz: QUINTAL_INTERVALS.map { |semis| (root * (2.0**(semis / 12.0))).round(2) },
      # "5" is how a chord with no third has been written on charts for decades.
      # The suffix has to go, or beauty_report scores a seventh that is not there.
      name: "#{chord[:name].to_s.sub(/\A([A-G][b#]?).*/) { Regexp.last_match(1) }}5",
    )
  end
end

def shuffle_pads_for_melody(pads)
  return pads if pads.length < 4

  home, *rest = pads
  by_top = rest.sort_by { |c| c[:hz].max }
  rising = []
  falling = []
  by_top.each_with_index { |c, i| (i.even? ? rising : falling) << c }
  [home] + rising + falling.reverse
end

def generate_progression(root_hz: 130.81, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  quality_for = SCALE_DEGREE_QUALITY.fetch(mode)
  semitones = SCALE_SEMITONES.fetch(mode)
  degree = 1
  Array.new(length) do
    quality = quality_for.fetch(degree)
    chord_root_hz = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
    chord = { name: "deg#{degree}#{quality}", hz: chord_from_root(chord_root_hz, quality) }
    degree = weighted_pick(rng, DEGREE_TRANSITIONS.fetch(degree))
    chord
  end
end

# Dilla's chromatic-minor-descent language (Donuts/Fantastic Vol. 2) isn't
# functional resolution — it's the *same* extended chord quality (m9/maj9)
# walked scalar/chromatic steps, occasionally toggling major/minor color.
# "Parallel planing" in classical-theory terms.
PLANING_STEP_WEIGHTS = { -2 => 3, -1 => 2, 2 => 2, -3 => 1, 3 => 1, -5 => 1 }.freeze
PLANING_QUALITIES = %w[m9 maj9].freeze

def generate_planing_progression(root_hz: 130.81, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  scale = SCALE_SEMITONES.fetch(mode)
  degree = 0
  quality = mode == :minor ? "m9" : "maj9"
  Array.new(length) do
    octave_shift = (degree.to_f / scale.length).floor
    chord_root_hz = root_hz * (2**((scale[degree % scale.length] + octave_shift * 12) / 12.0))
    chord = { name: "planing#{degree}#{quality}", hz: chord_from_root(chord_root_hz, quality) }
    quality = PLANING_QUALITIES.sample(random: rng) if rng.rand < 0.25
    degree += weighted_pick(rng, PLANING_STEP_WEIGHTS)
    chord
  end
end

# Chromatic-mediant language (chord analysis): root
# motion by thirds (chromatic mediants) rather than fifths, with an
# occasional tritone substitution standing in for a dominant resolution.
MEDIANT_STEP_WEIGHTS = { 3 => 3, -3 => 3, 4 => 2, -4 => 2, 6 => 1 }.freeze
MEDIANT_QUALITIES = %w[m9 maj9 7].freeze

def generate_chromatic_mediant_progression(root_hz: 130.81, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  semitone_offset = 0
  Array.new(length) do
    chord_root_hz = root_hz * (2**(semitone_offset / 12.0))
    quality = MEDIANT_QUALITIES.sample(random: rng)
    chord = { name: "mediant#{semitone_offset}#{quality}", hz: chord_from_root(chord_root_hz, quality) }
    semitone_offset += weighted_pick(rng, MEDIANT_STEP_WEIGHTS)
    chord
  end
end

# Aydin Esen's bitonal color: layer a second triad a tritone or major
# 2nd above the primary chord's root (a real polychord stack) rather than
# extending the primary chord further up the tertian stack.
POLYTONAL_OFFSETS = [6, 2, 10].freeze

def generate_polytonal_progression(root_hz: 130.81, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  quality_for = SCALE_DEGREE_QUALITY.fetch(mode)
  semitones = SCALE_SEMITONES.fetch(mode)
  degree = 1
  Array.new(length) do
    quality = quality_for.fetch(degree)
    chord_root_hz = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
    hz = chord_from_root(chord_root_hz, quality, voices: 4)
    if rng.rand < 0.45
      poly_root = chord_root_hz * (2**(POLYTONAL_OFFSETS.sample(random: rng) / 12.0))
      hz += chord_from_root(poly_root, "maj", voices: 2)
    end
    chord = { name: "poly#{degree}#{quality}", hz: hz.sort.first(6) }
    degree = weighted_pick(rng, DEGREE_TRANSITIONS.fetch(degree))
    chord
  end
end

# Real pedal-point technique (Bach organ works, film-scoring tension
# device): freeze the bass note while the chords above it keep changing.
# Implemented by literally replacing each chord's lowest voice with a
# fixed anchor pitch for a stretch — the upper structure still moves, only
# the foundation holds still, which is the actual effect.
def apply_pedal_point(pads, probability: 0.35, seed: nil)
  return pads if pads.length < 3
  rng = seed ? Random.new(seed) : Random.new
  pedal_root = pads.first[:hz].min
  pads.map.with_index do |chord, i|
    next chord if i.zero? || rng.rand >= probability
    hz = chord[:hz].dup
    hz[hz.index(hz.min)] = pedal_root
    { name: "#{chord[:name]}_pedal", hz: hz.sort }
  end
end

# Negative harmony (Ernst Levy / popularized by Jacob Collier): reflect
# every pitch around a fixed axis between the tonic and dominant. A major
# chord's mirror is its relative-minor-adjacent inversion — genuinely
# different color from any of the other generators, not just a mode swap.
def generate_negative_harmony_progression(root_hz: 130.81, mode: :minor, length: 8, seed: nil)
  source = generate_progression(root_hz:, mode:, length:, seed:)
  # Axis sits between the tonic and dominant (7 semitones up) — reflecting
  # around midi_axis = tonic_midi + 3.5 semitones is the standard convention.
  axis_midi = hz_to_midi(root_hz) + 3.5
  source.map do |chord|
    mirrored = chord[:hz].map { |hz| midi_to_hz((2 * axis_midi) - hz_to_midi(hz)) }
    { name: "neg_#{chord[:name]}", hz: mirrored.sort }
  end
end

# Neapolitan/tritone-first: root motion dominated by a half-step (bII, the
# Neapolitan) or a tritone, resolving to the tonic only rarely — deliberately
# avoids the fifth-based motion every other generator here leans on.
NEAPOLITAN_STEP_WEIGHTS = { 1 => 4, 6 => 3, 11 => 2, 4 => 1 }.freeze
NEAPOLITAN_QUALITIES = %w[maj7 m9 7].freeze

def generate_neapolitan_progression(root_hz: 130.81, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  semitone_offset = 0
  Array.new(length) do
    chord_root_hz = root_hz * (2**(semitone_offset / 12.0))
    quality = NEAPOLITAN_QUALITIES.sample(random: rng)
    chord = { name: "napl#{semitone_offset}#{quality}", hz: chord_from_root(chord_root_hz, quality) }
    step = weighted_pick(rng, NEAPOLITAN_STEP_WEIGHTS)
    semitone_offset += rng.rand < 0.5 ? step : -step
    chord
  end
end
