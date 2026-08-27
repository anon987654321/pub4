# frozen_string_literal: true
#
# Fitting a rap vocal to the beat: snapping, warping, key shifting.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- phrase snapping ---------------------------------------------------------
#
# atempo can only fix a take that HAS a tempo. A freely-sung take has no
# periodic spacing to stretch onto a grid, and measuring this proved it: across
# source BPMs from 96 to 128 against a 92 BPM beat, gunnhild landed 31%, 20%,
# 19%, 18%, 25% and 14% of her onsets on the grid, against a ~20% random-phase
# baseline. Slowing her down made the alignment WORSE. There is no ratio that
# works because the thing a ratio scales -- the spacing between her syllables --
# is not constant in the first place.
#
# So place instead of stretch: cut the take at its sung lines and start each
# line on a grid line, letting the silence between lines absorb the drift. The
# alignment then comes from where each line BEGINS, which is what a listener
# hears as being on the beat, and no line is time-warped internally so the
# delivery inside it stays hers.
RAP_VOCAL_SNAP_BEATS = (ENV["RAP_VOCAL_SNAP_BEATS"] || 2).to_f

# Dead-on the grid is not the goal -- it is only the reference the lean is
# measured from. rap_vocal_pocket_nudge_sec already drags the whole vocal 3-4
# ticks of 96 PPQ behind the beat (20-27ms at 92), but that is one constant for
# the entire take. Dilla's feel is not constant; it wanders line to line, and
# the wander is the point. RAP_VOCAL_LEAN_MS sets the base drag, and each line
# is offset from it by a fixed walk.
#
# The walk is a literal table rather than rng: a render has to reproduce, and a
# "feel" you cannot get back is not a feel, it is an accident.
RAP_VOCAL_LEAN_MS = (ENV["RAP_VOCAL_LEAN_MS"] || 0).to_f
RAP_VOCAL_LEAN_WALK = [0, 7, -5, 12, -3, 9, -8, 4, 2, -6, 11, -2].freeze

# How far the beat steps back while the rap is going. Set the ratio to 1 to
# disable the duck entirely and get the old fixed-weight mix back.
RAP_VOCAL_DUCK_THRESHOLD_DB = (ENV["RAP_VOCAL_DUCK_THRESHOLD_DB"] || -30).to_f.clamp(-60.0, 0.0)
RAP_VOCAL_DUCK_RATIO = (ENV["RAP_VOCAL_DUCK_RATIO"] || 2).to_f.clamp(1.0, 20.0)

# Reverse pre-swell: the head of each line, reversed and darkened, arriving
# exactly as the line starts. Impractical before line placement existed --
# it needs every downbeat known to the millisecond, which is precisely what
# snapping produces.
RAP_VOCAL_SWELL = ENV["RAP_VOCAL_SWELL"] == "1"
RAP_VOCAL_SWELL_SEC = (ENV["RAP_VOCAL_SWELL_SEC"] || 0.45).to_f.clamp(0.1, 2.0)
RAP_VOCAL_SWELL_VOL = (ENV["RAP_VOCAL_SWELL_VOL"] || 0.45).to_f.clamp(0.0, 1.5)

# Every segment currently gets a 20ms in / 50ms out fade so seams cannot click.
# Dilla did not clean his seams -- chop tails ran into the next chop. This lets
# the collisions through on purpose.
RAP_VOCAL_RAW_SEAMS = ENV["RAP_VOCAL_RAW_SEAMS"] == "1"

# Warp each line onto the grid, instead of only starting it there.
#
# The measurement above rules out ONE ratio for the whole take, and rightly:
# a freely-sung take has no constant syllable spacing for a ratio to scale.
# It does not rule out a ratio PER LINE. Each placed line has a known length
# and a known slot, so stretching it onto the nearest whole number of grid
# units is a different operation from stretching the take -- it is what a
# DAW's warp markers do, and the reason they work on takes atempo cannot.
#
# Placement alone fixes where a line BEGINS; a line that runs long still ends
# between grid lines and the next one starts from a slot it never reached.
# Warping fixes where it ENDS too.
#
# Off by default: it alters delivery inside a line, which placement
# deliberately preserves, and that is a taste decision rather than a
# correctness one. RAP_VOCAL_WARP=1 turns it on.
#
# The clamp matters more than the ratio. Outside roughly ±14% a stretched
# voice stops sounding like a performance and starts sounding like a plugin,
# so a line needing more than that is left alone rather than mangled -- the
# grid is not worth the formant damage.
RAP_VOCAL_WARP = ENV["RAP_VOCAL_WARP"] == "1"
RAP_VOCAL_WARP_MIN = (ENV["RAP_VOCAL_WARP_MIN"] || 0.88).to_f
RAP_VOCAL_WARP_MAX = (ENV["RAP_VOCAL_WARP_MAX"] || 1.14).to_f

# atempo=r plays r times faster, so a line of `length` becomes length/r. To
# land on `target` the ratio is length/target. Returns nil when the line is
# already close enough to a grid multiple to leave alone, or too far from one
# to reach without audible damage.
def rap_vocal_warp_ratio(length, grid)
  return nil unless RAP_VOCAL_WARP
  return nil if grid <= 0

  units = (length / grid).round
  return nil if units < 1

  target = units * grid
  ratio = length / target
  return nil if (ratio - 1.0).abs < 0.01
  return nil unless ratio.between?(RAP_VOCAL_WARP_MIN, RAP_VOCAL_WARP_MAX)

  ratio
end

def rap_vocal_line_lean(index)
  return 0.0 if RAP_VOCAL_LEAN_MS.zero?

  walk = RAP_VOCAL_LEAN_WALK[index % RAP_VOCAL_LEAN_WALK.length]
  (RAP_VOCAL_LEAN_MS + walk) / 1000.0
end

# Line detection thresholds. The catalog's stored "phrases" cannot be used for
# this: they are peak clusters joined at 0.35s, which on sung material collapse
# to bare onsets -- gunnhild's 100 stored phrases have a MEDIAN LENGTH OF ZERO,
# so cutting on them yields empty segments. These find voiced spans instead, and
# were swept against gunnhild for line-sized output: hold 0.14 / rel 0.55 gives
# 43 lines with a median of 1.23s, about two beats at 92 BPM. A longer hold
# swallows whole verses (0.20 gives one 13.96s span), a shorter one shatters
# words (0.06 gives a 0.49s median).
RAP_VOCAL_LINE_HOLD = (ENV["RAP_VOCAL_LINE_HOLD"] || 0.14).to_f
RAP_VOCAL_LINE_REL = (ENV["RAP_VOCAL_LINE_REL"] || 0.55).to_f
RAP_VOCAL_LINE_MIN = (ENV["RAP_VOCAL_LINE_MIN"] || 0.35).to_f

# Analysis rate and band. 8 kHz is plenty for locating syllables -- the band
# that decides where a voice is has nothing above 6 kHz in it -- and decoding
# less means the envelope pass costs nothing. Shared with rap_vocal_onset_times.
RAP_VOCAL_ANALYSIS_RATE = 8_000
RAP_VOCAL_ANALYSIS_HOP = 0.010
RAP_VOCAL_VOICE_HIGHPASS_HZ = 200
RAP_VOCAL_VOICE_LOWPASS_HZ = 6_000
PCM16_FULL_SCALE = 32_768.0

# The level a "loud" frame is measured against. Not the maximum: one clipped
# frame would then set the floor for the whole take.
RAP_VOCAL_LOUD_PERCENTILE = 0.90
# Below this a frame is silence no matter what the percentile says, so an
# all-but-silent stem cannot have its own noise promoted into "lines".
RAP_VOCAL_ABSOLUTE_FLOOR = 0.0015
RAP_VOCAL_MIN_ANALYSIS_FRAMES = 10

# RMS envelope of `path` in the voice band, one value per hop.
def rap_vocal_envelope(path, hop: RAP_VOCAL_ANALYSIS_HOP)
  raw = IO.popen(["ffmpeg", "-v", "error", "-i", path, "-af",
                  "highpass=f=#{RAP_VOCAL_VOICE_HIGHPASS_HZ}," \
                  "lowpass=f=#{RAP_VOCAL_VOICE_LOWPASS_HZ}",
                  "-ac", "1", "-ar", RAP_VOCAL_ANALYSIS_RATE.to_s,
                  "-f", "s16le", "-"], "rb", &:read)
  samples = raw.to_s.unpack("s<*")
  return [] if samples.empty?

  frame = (RAP_VOCAL_ANALYSIS_RATE * hop).to_i
  samples.each_slice(frame).map do |chunk|
    Math.sqrt(chunk.sum { |s| (s / PCM16_FULL_SCALE)**2 } / chunk.size)
  end
end

# The sung lines of a take: contiguous voiced spans, in its own timeline.
def rap_vocal_sung_lines(path, hop: RAP_VOCAL_ANALYSIS_HOP)
  env = rap_vocal_envelope(path, hop:)
  return [] if env.size < RAP_VOCAL_MIN_ANALYSIS_FRAMES

  # Relative floor, not absolute: demucs stem levels vary by tens of dB between
  # sources (measured -9.8 to -46.8), so any fixed threshold either passes
  # everything or nothing depending on which vocal it meets.
  sorted = env.sort
  loud = sorted[(sorted.size * RAP_VOCAL_LOUD_PERCENTILE).to_i].to_f
  floor = [loud * RAP_VOCAL_LINE_REL, RAP_VOCAL_ABSOLUTE_FLOOR].max
  hold_frames = (RAP_VOCAL_LINE_HOLD / hop).to_i

  lines = []
  start = nil
  quiet = 0
  env.each_with_index do |level, i|
    if level >= floor
      start ||= i
      quiet = 0
    elsif start
      quiet += 1
      next unless quiet > hold_frames

      lines << [start * hop, (i - quiet) * hop]
      start = nil
    end
  end
  lines << [start * hop, (env.size - 1) * hop] if start
  lines.select { |from, to| to - from >= RAP_VOCAL_LINE_MIN }
       .map { |from, to| [from.round(3), to.round(3)] }
end

# Decides where each line lands. Walks the lines in order, putting every one at
# the next free grid line, and returns [] if the take has too few lines to build
# from -- the caller then falls back to the uniform stretch rather than
# rendering something thin.
RAP_VOCAL_LINE_PREROLL_SEC = 0.06   # keep the consonant that starts the line
RAP_VOCAL_LINE_TAIL_SEC = 0.25      # and the vowel that ends it
RAP_VOCAL_SNAP_MIN_LINES = 4
# A runt line is skipped without advancing the cursor, so the loop needs a stop
# that does not depend on making progress.
RAP_VOCAL_SNAP_MAX_PASSES = 512

# A take gets used once. `taken % usable.size` wrapped back to the first line
# whenever the performance ran out before the section did, so a short stem was
# heard two, three or eight times over — the same words returning on a loop,
# which is the one thing a rap verse cannot survive. When the lines run out the
# vocal now stops and the beat carries the rest.
#
# RAP_VOCAL_REPEAT=1 restores the wrap for material where looping is the point
# (a hook, a chant), which is why this is a switch rather than a deletion.
RAP_VOCAL_REPEAT = ENV["RAP_VOCAL_REPEAT"] == "1"

def rap_vocal_snap_placements(lines, take_sec, duration:, grid:, from_sec: 0.0, gap:)
  return [] if lines.size < RAP_VOCAL_SNAP_MIN_LINES

  usable = lines.select { |(from, _)| from >= from_sec }
  usable = lines if usable.size < RAP_VOCAL_SNAP_MIN_LINES

  placements = []
  cursor = 0.0
  taken = 0
  passes = 0
  while cursor < duration && passes < RAP_VOCAL_SNAP_MAX_PASSES
    passes += 1
    break if !RAP_VOCAL_REPEAT && taken >= usable.size
    line_from, line_to = usable[taken % usable.size]
    taken += 1

    # Cut up to the next line's start so a tail is never clipped mid-vowel.
    next_from = lines.find { |(from, _)| from > line_from }&.first
    cut_from = [line_from - RAP_VOCAL_LINE_PREROLL_SEC, 0.0].max
    cut_to = [line_to + RAP_VOCAL_LINE_TAIL_SEC, next_from || take_sec, take_sec].min
    length = cut_to - cut_from
    next if length < RAP_VOCAL_LINE_MIN

    slot = (cursor / grid).ceil * grid
    break if slot >= duration

    length = [length, duration - slot].min
    next if length < RAP_VOCAL_LINE_MIN

    # `at` is where the VOICE should land. The cut starts `lead` earlier so the
    # opening consonant survives, so the segment itself has to be placed that
    # much before the grid line -- otherwise every line sits exactly one
    # pre-roll late, which measured as a flat ~62ms lag on every single line.
    lean = rap_vocal_line_lean(placements.size)
    at = [slot + lean, 0.0].max
    lead = line_from - cut_from
    # Warping changes how long the placed line sounds for, so the cursor has
    # to advance by the SOUNDED length or every line after this one inherits
    # the error.
    warp = rap_vocal_warp_ratio(length, grid)
    sounded = warp ? length / warp : length
    sounded_lead = warp ? lead / warp : lead
    placements << { from: cut_from.round(3), length: length.round(3),
                    at: at.round(3), lead: lead.round(3), lean: lean.round(4),
                    warp: warp&.round(4) }
    cursor = at + (sounded - sounded_lead) + gap
  end
  placements
end

SEAM_FADE_IN_SEC = 0.02
SEAM_FADE_OUT_SEC = 0.05
# Not an articulation -- just enough to stop the DC step at a hard cut popping.
SEAM_RAW_FADE_SEC = 0.003
# Darkened, because a reverse swell that keeps its consonants reads as audio
# played backwards rather than as a rise into the beat.
SWELL_LOWPASS_HZ = 2600
SWELL_ECHO_FRACTION = 0.35
SWELL_ECHO_DECAY = 0.45
SWELL_FADE_FRACTION = 0.8
SWELL_MIN_SEC = 0.1

# One ffmpeg input cut from `stretched`, delayed into place.
def rap_vocal_placed_input(source, from:, length:, at:, index:, filters:, label:)
  ms = [(at * 1000).round, 0].max
  {
    args: ["-ss", from.round(3).to_s, "-t", length.round(3).to_s, "-i", source],
    chain: "[#{index}:a]#{filters},adelay=#{ms}|#{ms}[#{label}#{index}]",
    label: "[#{label}#{index}]",
  }
end

# Cuts `stretched` into its lines and reassembles them on the grid.
def rap_vocal_render_snapped!(stretched, fit_path, placements, duration:, outer:, tail:)
  parts = []

  placements.each do |p|
    # atempo runs first, so everything after it is measured in sounded time:
    # the fade-out lands relative to the warped length, and the pre-roll that
    # positions the segment shrinks by the same ratio.
    warp = p[:warp]
    sounded_len = warp ? p[:length] / warp : p[:length]
    sounded_lead = warp ? p[:lead].to_f / warp : p[:lead].to_f
    seam = if RAP_VOCAL_RAW_SEAMS
             "afade=t=in:st=0:d=#{SEAM_RAW_FADE_SEC}"
           else
             out_at = [sounded_len - SEAM_FADE_OUT_SEC, 0.0].max
             "afade=t=in:st=0:d=#{SEAM_FADE_IN_SEC}," \
               "afade=t=out:st=#{out_at.round(3)}:d=#{SEAM_FADE_OUT_SEC}"
           end
    seam = "atempo=#{warp.round(4)},#{seam}" if warp
    parts << rap_vocal_placed_input(stretched, from: p[:from], length: p[:length],
                                    at: p[:at] - sounded_lead, index: parts.size,
                                    filters: seam, label: "s")
  end

  if RAP_VOCAL_SWELL
    placements.each do |p|
      swell = [RAP_VOCAL_SWELL_SEC, p[:length]].min
      next if swell < SWELL_MIN_SEC

      # Land the swell so it ENDS on the line's own downbeat: start it a swell
      # earlier, and reverse the line's head so the loudest part is last.
      at = p[:at] - swell
      next if at.negative?

      filters = "areverse,lowpass=f=#{SWELL_LOWPASS_HZ}," \
                "aecho=0.8:0.7:#{(swell * 1000 * SWELL_ECHO_FRACTION).round}:#{SWELL_ECHO_DECAY}," \
                "afade=t=in:st=0:d=#{(swell * SWELL_FADE_FRACTION).round(3)}," \
                "volume=#{RAP_VOCAL_SWELL_VOL}"
      parts << rap_vocal_placed_input(stretched, from: p[:from], length: swell,
                                      at:, index: parts.size,
                                      filters:, label: "w")
    end
  end

  chain = parts.map { |p| p[:chain] }
  # normalize=0: amix would otherwise divide by the input count, and with ~30
  # mostly non-overlapping lines that is a ~30x attenuation of every one of them.
  chain << "#{parts.map { |p| p[:label] }.join}" \
           "amix=inputs=#{parts.size}:normalize=0:dropout_transition=0[snap]"
  chain << "[snap]#{outer}#{tail}[vout]"
  sh! "ffmpeg", "-y", *parts.flat_map { |p| p[:args] },
      "-filter_complex", chain.join(";"),
      "-map", "[vout]", "-t", duration.round(3).to_s,
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", fit_path
  fit_path
end

# --- Vocal key alignment -----------------------------------------------------
# atempo preserves pitch. That is correct for a tempo fit and it is also why the
# vocal path has never changed a stem's key: rap_vocal_atempo_chain, asetpts and
# the crossfade loop all leave pitch alone, and nothing else in the chain touches
# it. So a stem whose notes sit outside the beat's key stays outside it for the
# entire render.
#
# Measured on gunnhild's 86bpm/32bar fit against db_major_minor_fall (Dbmaj7 Cm7 Fm7
# Bbm7 — Db major): the three strongest pitch classes in the vocal are A (17.5%
# of voiced energy), Ab (14.7%) and B (13.1%). A and B are not in Db major. In
# total 38.3% of the vocal's energy landed on non-key notes against 32.1% on key
# notes, with A — a major third against the Fm7 the progression sits on — the
# single loudest thing in the take.
#
# This is a key mismatch, not a detuned stem: the same fit measures -0.6 cents
# mean deviation from equal temperament, so it is in tune with itself and with
# A=440. Correcting it needs a transpose, not a fine-tune.
RAP_VOCAL_KEY_OCTAVES = (3..5).freeze
# ~130-988 Hz. Below C3 a semitone is narrower than the analysis resolution
# (3.9 Hz at N=2048/8kHz), so those octaves would smear into their neighbours.
RAP_VOCAL_KEY_SR = 8_000
RAP_VOCAL_KEY_N = 2_048
RAP_VOCAL_KEY_HOP = 1_024
# A transpose is a real cost -- asetrate resampling shifts formants, so a voice
# moved far reads as pitched-up/down rather than as the same singer in a new
# key. Cap it at a whole tone and take the smaller of two near-equal wins.
RAP_VOCAL_KEY_MAX_SHIFT = 2
# Don't spend a transpose on a coin-flip: the shift has to move at least this
# much of the vocal's energy onto key notes to be worth the formant cost.
RAP_VOCAL_KEY_MIN_GAIN = 0.05

# Chroma vector: 12 pitch classes, framewise Goertzel at each class's frequency
# in each analysed octave. Goertzel rather than a full FFT because only 36 of
# 1024 bins are ever read, and framewise rather than one pass over the whole
# take because a 16s window resolves to 0.06 Hz — far narrower than a sung note
# wanders, so the energy would smear across bins instead of accumulating.
def audio_chroma(path)
  raw = pipe_floats(path, "highpass=f=110,lowpass=f=1100," \
                          "aformat=sample_fmts=flt:channel_layouts=mono:sample_rates=#{RAP_VOCAL_KEY_SR}")
  return nil if raw.length < RAP_VOCAL_KEY_N

  targets = RAP_VOCAL_KEY_OCTAVES.flat_map do |octave|
    (0..11).map do |pc|
      midi = ((octave + 1) * 12) + pc
      [pc, 440.0 * (2**((midi - 69) / 12.0))]
    end
  end
  # Goertzel coefficient per target frequency, plus a Hann window reused across
  # frames.
  coeffs = targets.map { |pc, hz| [pc, 2.0 * Math.cos(2.0 * Math::PI * hz / RAP_VOCAL_KEY_SR)] }
  han = Array.new(RAP_VOCAL_KEY_N) { |n| 0.5 - (0.5 * Math.cos(2.0 * Math::PI * n / (RAP_VOCAL_KEY_N - 1))) }
  chroma = Array.new(12, 0.0)
  frames = 0
  pos = 0
  while pos + RAP_VOCAL_KEY_N <= raw.length
    win = Array.new(RAP_VOCAL_KEY_N) { |n| raw[pos + n] * han[n] }
    rms = Math.sqrt(win.sum { |v| v * v } / RAP_VOCAL_KEY_N)
    # Voiced frames only. Silence and breath carry no key, and a gated stem is
    # mostly silence — including it adds a flat floor to every class.
    if rms > 0.008
      coeffs.each do |pc, coeff|
        s1 = 0.0
        s2 = 0.0
        i = 0
        while i < RAP_VOCAL_KEY_N
          s0 = win[i] + (coeff * s1) - s2
          s2 = s1
          s1 = s0
          i += 1
        end
        chroma[pc] += Math.sqrt((s1 * s1) + (s2 * s2) - (coeff * s1 * s2))
      end
      frames += 1
    end
    pos += RAP_VOCAL_KEY_HOP
  end
  return nil if frames.zero?

  total = chroma.sum
  return nil unless total.positive?

  chroma.map { |v| v / total }
end

# Root pitch class of a chord name. PAD_CHORD_LOOKUP only holds the voicings the
# pad engine registered, and the progressions name chords it never registered:
# db_major_minor_fall is Dbmaj7/Cm7/Fm7/Bbm7 while the lookup carries the ...maj9/m9
# forms, so every one of its four chords missed and the whole progression scored
# as having no harmony at all.
CHORD_ROOT_RE = /\A([A-G])([b#]?)/
def chord_name_root_class(name)
  m = CHORD_ROOT_RE.match(name.to_s)
  return nil unless m

  base = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }[m[1]]
  return nil if base.nil?

  case m[2]
  when "b" then (base - 1) % 12
  when "#" then (base + 1) % 12
  else base
  end
end

# Third and fifth implied by the name, so a chord the lookup does not carry still
# contributes the interval that decides major vs minor -- the distinction the
# vocal actually clashes with.
def chord_name_tone_classes(name)
  root = chord_name_root_class(name)
  return [] if root.nil?

  body = name.to_s.sub(CHORD_ROOT_RE, "").sub(%r{/.*\z}, "")
  minor = body.match?(/\Am(?!aj)/)
  dim = body.match?(/\Adim|\A0/)
  third = if dim || minor then 3 else 4 end
  fifth = dim ? 6 : 7
  [root, (root + third) % 12, (root + fifth) % 12]
end

# How strongly each pitch class belongs to the progression, as a weight rather
# than a member/non-member flag. A binary set is useless on the slash-chord
# progressions: pedal_e_descent (D/E Db/E C/E Bm/E Bbm/E Am/E) unions to all
# twelve classes, so every shift scored a perfect 100% and the comparison
# carried no information. Counting how many chords contain a class keeps the
# tonic centre distinguishable from a passing chromatic tone.
def progression_pitch_class_weights(progression)
  names = CHORD_PROGRESSIONS[progression]
  return nil if names.nil? || names.empty?

  weights = Array.new(12, 0.0)
  names.each do |name|
    chord = PAD_CHORD_LOOKUP[name]
    classes = Array(chord && chord[:hz]).filter_map do |hz|
      next nil unless hz.to_f.positive?
      (69 + (12 * Math.log2(hz.to_f / 440.0))).round % 12
    end
    classes = chord_name_tone_classes(name) if classes.empty?
    # Root and third carry the chord's identity; count the whole voicing but
    # give the root extra weight so the tonic centre wins ties.
    classes.uniq.each { |c| weights[c] += 1.0 }
    root = chord_name_root_class(name)
    weights[root] += 0.5 if root
  end
  total = weights.sum
  return nil unless total.positive?

  weights.map { |w| w / total }
end

# Pick the transpose that best lines the vocal's energy up with the progression's
# harmony: the dot product of the vocal chroma against the shifted chord-tone
# weights. Ties go to the smaller shift, and 0 wins unless a shift clears
# RAP_VOCAL_KEY_MIN_GAIN relative to it, so a vocal already in key is untouched.
def rap_vocal_key_shift(chroma, key_weights, max_shift: RAP_VOCAL_KEY_MAX_SHIFT)
  return 0 if chroma.nil? || key_weights.nil?

  scored = (-max_shift..max_shift).map do |shift|
    # Shifting the audio up by `shift` moves energy at class c to c+shift, so
    # compare chroma[c] against the weight of where it lands.
    fit = (0..11).sum { |c| chroma[c] * key_weights[(c + shift) % 12] }
    [shift, fit]
  end
  base = scored.find { |shift, _| shift.zero? }.last
  return 0 unless base.positive?

  # The threshold is relative, and it scales with the size of the move. Relative
  # because the dot product's scale depends on how concentrated the
  # progression's weights are, so one absolute number would mean different
  # things for a 4-chord vamp and a 12-class slash cycle. Scaled because the
  # cost is not flat: a whole tone through asetrate resamples formants by 12%,
  # which reads as a pitched-up singer rather than the same singer in a new key,
  # so it has to earn twice what a semitone does. Measured on gunnhild: this is
  # what separates db_major_minor_fall (+1 at 5.1%, taken) from its own +2 at 8.7%
  # (rejected — a bigger move on weaker evidence).
  qualified = scored.select do |shift, fit|
    next false if shift.zero?
    (fit - base) / base >= RAP_VOCAL_KEY_MIN_GAIN * shift.abs
  end
  return 0 if qualified.empty?

  qualified.max_by { |shift, fit| [fit.round(6), -shift.abs] }.first
end

# asetrate raises pitch and tempo together; atempo puts the tempo back. That
# leaves the take its original length in the new key. Formants move with the
# resample, which is the reason RAP_VOCAL_KEY_MAX_SHIFT is small.
def rap_vocal_pitch_shift_chain(semitones)
  return nil if semitones.to_i.zero?

  ratio = 2**(semitones.to_f / 12.0)
  "asetrate=#{(SAMPLE_RATE * ratio).round},aresample=#{SAMPLE_RATE}," \
    "#{rap_vocal_atempo_chain(1.0 / ratio)}"
end

# Resolved once per fit and cached on the catalog entry: the chroma pass costs a
# full decode plus 36 Goertzel accumulators per frame, and a stem's key does not
# change between renders.
def rap_vocal_resolved_key_shift(entry, vocal_path, progression)
  return 0 if ENV["RAP_VOCAL_KEY_ALIGN"] == "0"

  forced = ENV["RAP_VOCAL_KEY_SHIFT"]
  return forced.to_i.clamp(-6, 6) if forced && !forced.strip.empty?

  key_weights = progression_pitch_class_weights(progression)
  return 0 if key_weights.nil?

  chroma = entry.is_a?(Hash) ? entry["chroma"] : nil
  if chroma.nil? || chroma.length != 12
    chroma = audio_chroma(vocal_path)
    return 0 if chroma.nil?
    if entry.is_a?(Hash)
      entry["chroma"] = chroma.map { |v| v.round(5) }
      cat = rap_vocal_load_catalog
      cat["vocals"] = Array(cat["vocals"]).map { |v| v["slug"] == entry["slug"] ? entry : v }
      rap_vocal_save_catalog!(cat)
    end
  end
  rap_vocal_key_shift(chroma, key_weights)
end

def rap_vocal_fit!(slug_or_path, beat_bpm:, n_bars:, bar_offset: nil, progression: nil)
  bar_offset ||= ENV["RAP_VOCAL_OFFSET"]&.to_f
  entry = rap_vocal_resolve(slug_or_path)
  vocal_path = entry.is_a?(Hash) ? entry["vocal_path"] : entry
  unless vocal_path && File.file?(vocal_path)
    warn "rap-vocal fit: unknown or missing slug #{slug_or_path}"
    return
  end
  # Always re-isolate uncleaned stems; already-isolated stems get a light polish only.
  isolated = entry.is_a?(Hash) && entry["isolated"] == true
  if entry.is_a?(Hash) && !isolated
    cleaned = File.join(File.dirname(vocal_path), "vocals.clean.wav")
    rap_vocal_clean_stem!(vocal_path, cleaned, aggressive: true)
    # Keep the raw demucs stem. This used to `mv` the cleaned file over
    # vocal_path, destroying the only local copy of the isolation output --
    # and because the entry is then marked isolated, it never re-cleans, so a
    # mis-gated clean is permanent with no way back. gunnhild lost its 0-16s
    # vocal section this way (present in the demucs stem, silent in the working
    # copy). Point the entry at the cleaned file instead and leave the source.
    raw_keep = File.join(File.dirname(vocal_path), "vocals.raw.wav")
    FileUtils.cp(vocal_path, raw_keep) unless File.exist?(raw_keep)
    FileUtils.mv(cleaned, vocal_path)
    entry["raw_path"] = raw_keep
    entry["isolated"] = true
    entry["voice_only"] = true
    entry["phrases"] = rap_vocal_phrase_onsets(vocal_path)
    cat = rap_vocal_load_catalog
    cat["vocals"] = Array(cat["vocals"]).map { |v| v["slug"] == entry["slug"] ? entry : v }
    rap_vocal_save_catalog!(cat)
    isolated = true
  end
  beat_bpm = beat_bpm.to_f
  vocal_bpm = rap_vocal_source_bpm(entry, vocal_path, target: beat_bpm)
  vocal_bpm = beat_bpm unless vocal_bpm&.positive?
  # Clamp stretch: extreme atempo starts to chipmunk/garble speech.
  ratio = (beat_bpm / vocal_bpm).clamp(0.5, 2.0)

  # Snap when the take has no measurable pulse, stretch when it has one.
  # RAP_VOCAL_SNAP=1/0 forces either way.
  forced_bpm = ENV["RAP_VOCAL_BPM"].to_f.positive?
  has_pulse = !rap_vocal_measure_bpm(vocal_path).nil?
  snapping = case ENV["RAP_VOCAL_SNAP"]
             when "0" then false
             when "1" then true
             else !has_pulse
             end
  if snapping && !forced_bpm
    # With no pulse, `vocal_bpm` is a stored guess and stretching by it is the
    # meaningless operation this path exists to replace. Leave her at her own
    # speed unless someone asks for a stretch on purpose.
    ratio = 1.0
  end
  duration = (60.0 / beat_bpm) * 4.0 * n_bars
  phrases = entry.is_a?(Hash) ? entry["phrases"] : nil
  # An explicit bar_offset (caller or RAP_VOCAL_OFFSET) is a deliberate pick
  # -- honor it outright. Only auto-picked offsets get floored to the real
  # speech onset, since that floor exists to skip residual intro thump, not
  # to override someone choosing a different section on purpose.
  phrase_start = nil
  if bar_offset
    ss = bar_offset
  else
    # Pick the region by content first -- the densest `duration * ratio`
    # seconds of actual singing -- then let the phrase/bar logic nudge within
    # it. Falls back to the old earliest-strong-phrase rule if the content
    # scan cannot run.
    needed = duration * ratio
    content = rap_vocal_content_offset(vocal_path, needed)
    phrase_start = rap_vocal_phrase_start(phrases) || 0.0
    ss = if content
           # Snap the content region to the vocal's own bar grid, so the cut
           # starts on a downbeat and stays on the grid once stretched.
           #
           # This was `content + (bar_nudge % target_bar_seconds)`: it added a
           # remainder of one measurement to the start of another, in a
           # different tempo's units. Whatever came out was not a bar boundary
           # in either timeline.
           source_bar = (60.0 / vocal_bpm) * 4.0
           phase = rap_vocal_best_bar_offset(vocal_path, vocal_bpm, phrases:).to_f
           bars_in = ((content - phase) / source_bar).round
           [phase + (bars_in * source_bar), 0.0].max.round(4)
         else
           # Same grid as above — the vocal's own, not the beat's.
           [rap_vocal_best_bar_offset(vocal_path, vocal_bpm, phrases:), phrase_start].max
         end
  end
  out_dir = File.dirname(vocal_path)
  # Transposed into the beat's key in stage 1 below. Resolved here because the
  # shift has to be part of the filename: bpm+bars alone named the same file for
  # two tracks at the same tempo in different keys, so whichever rendered first
  # won and the second silently reused a fit built for someone else's harmony.
  key_shift = rap_vocal_resolved_key_shift(entry, vocal_path, progression)
  key_tag = key_shift.zero? ? "" : format("_key%+d", key_shift)
  fit_path = File.join(out_dir, "fit_#{beat_bpm.round}_#{n_bars}bars#{key_tag}.wav")
  # Already-isolated → light polish only (no second heavy makeup that re-lifts bleed).
  # Fresh/unclean → full voice-only isolation.
  voice_chain = isolated ? rap_vocal_voice_polish_filter : rap_vocal_isolation_filter
  # Loop source so short verses cover full N bars (voice-only — never pad with kit).
  # Soft edge fades avoid wrap clicks after atempo.
  fade = [0.012, duration * 0.004].max.round(4)
  loudnorm_i = ENV.fetch("RAP_VOCAL_LOUDNORM_I", "-17")
  limiter = ENV.fetch("RAP_VOCAL_LIMITER", "0.93")
  # Stacking this loudnorm+limiter here AND the mix-stage limiter in
  # mix_rap_vocal_layer! double-squashes dynamics into a "maxed"/pumped
  # feel even with no true clipping.
  #
  # Now off by default, because the fit's absolute level does not survive the
  # mix stage anyway: mix_rap_vocal_layer! measures this file's voice-band RMS
  # and applies its own norm_db to hit the anchor. So loudnorm's I=-17 target is
  # discarded a step later and the only thing it leaves behind is LRA=7's
  # dynamic-range compression plus a second limiter — squashed transients on a
  # vocal whose own spectrum measures smooth (peak 400-630 Hz, monotonic
  # rolloff above). That is what reads as hard/sharp once it is also loud.
  # RAP_VOCAL_SKIP_LOUDNORM=0 restores the old behaviour.
  # Measured 2026-08-10, so nobody re-derives it: the report "the vocals go up
  # and down in volume" is NOT this stage. Re-enabling loudnorm here (LRA=11, no
  # second limiter) moves the fitted store_p stem from LRA 4.4 to 3.9 -- the
  # stem is already even, and there is no wide dynamic range at this point for
  # loudnorm to control. That change was made, measured, and reverted.
  #
  # Where to look instead: the anchor in mix_rap_vocal_layer!
  # (RAP_VOCAL_ANCHOR_DB, currently -3.0) sets the voice against the FULL-band
  # beat RMS, which includes kick and bass, so it governs audibility directly;
  # and alimiter on the summed mix is the only dynamics acting on vocal peaks,
  # so it is the candidate for both the pumping and the saturation.
  tail = if ENV.fetch("RAP_VOCAL_SKIP_LOUDNORM", "1") == "1"
           ""
         else
           ",loudnorm=I=#{loudnorm_i}:TP=-2.5:LRA=7,alimiter=limit=#{limiter}:level_out=#{(limiter.to_f + 0.01).round(2)}"
         end
  # Stage 1: process the usable region ONCE (isolation + tempo match), no loop.
  # The old single-pass version did `-stream_loop -1` with `-ss`, which restarts
  # at the seek point every wrap, and applied afade only at the outer edges of
  # the whole output -- so every wrap was an unfaded hard splice landing mid-word.
  # With gunnhild (11.5s usable from ss) a 32-bar render wrapped ~8 times, which
  # is exactly the "choppy" report.
  seg_path = File.join(out_dir, "seg_#{beat_bpm.round}_#{n_bars}bars.wav")
  # Transpose in the same pass as the tempo fit and before the loudnorm/limiter
  # tail, so the level measured downstream is the level of what actually plays.
  pitch_chain = rap_vocal_pitch_shift_chain(key_shift)
  if pitch_chain
    dmesg("rap-vocal key: #{key_shift.positive? ? '+' : ''}#{key_shift} semitone#{key_shift.abs == 1 ? '' : 's'} " \
          "into #{progression || 'beat'} key",
          unit: "vox0", parent: "dilla0")
  end
  seg_af = ["#{voice_chain},#{rap_vocal_atempo_chain(ratio)}", pitch_chain, "asetpts=PTS-STARTPTS"]
           .compact.join(",")
  sh! "ffmpeg", "-y", "-ss", ss.round(3).to_s, "-i", vocal_path,
      "-af", seg_af,
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", seg_path
  seg_len = audio_duration_sec(seg_path).to_f

  # Stage 2: fill `duration`. One pass if the segment already covers it;
  # otherwise repeat it with a real crossfade at each seam so the joins are
  # inaudible instead of clicking.
  xfade = ENV.fetch("RAP_VOCAL_XFADE", "0.35").to_f.clamp(0.05, 2.0)
  xfade = [xfade, seg_len / 3.0].min if seg_len.positive?
  outer = "afade=t=in:st=0:d=#{fade},afade=t=out:st=#{(duration - fade).round(3)}:d=#{fade}"

  # seg_path already runs from `ss` to the end of the take, so its lines are the
  # whole usable performance and the placer picks from all of them.
  snapped = nil
  if snapping
    beat_sec = 60.0 / beat_bpm
    lines = rap_vocal_sung_lines(seg_path)
    placements = rap_vocal_snap_placements(lines, seg_len, duration:,
                                           grid: beat_sec * RAP_VOCAL_SNAP_BEATS,
                                           gap: beat_sec * 0.25)
    if placements.size >= 4
      rap_vocal_render_snapped!(seg_path, fit_path, placements, duration:, outer:, tail:)
      snapped = placements
      dmesg("rap-vocal snap: #{placements.size} lines of #{lines.size} onto a " \
            "#{RAP_VOCAL_SNAP_BEATS.round}-beat grid (no pulse to stretch)",
            unit: "vox0", parent: "dilla0")
    else
      warn "rap-vocal snap: #{lines.size} lines gave #{placements.size} placements — " \
           "using the uniform stretch instead"
    end
  end

  if snapped
    nil # built by rap_vocal_render_snapped!
  elsif seg_len <= 0 || seg_len >= duration
    sh! "ffmpeg", "-y", "-i", seg_path, "-t", duration.round(3).to_s,
        "-af", "#{outer}#{tail}",
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", fit_path
  elsif !RAP_VOCAL_REPEAT
    # The take is shorter than the section and repeating is off, so it plays once
    # and the beat carries the rest. apad fills the remainder with silence: the
    # downstream mix expects a stem of exactly `duration`, and a short one would
    # be handled by amix's dropout logic instead, which is not the same thing.
    dmesg("rap-vocal once: #{seg_len.round(2)}s over #{duration.round(2)}s, no repeat",
          unit: "vox0", parent: "dilla0")
    sh! "ffmpeg", "-y", "-i", seg_path,
        "-af", "#{outer}#{tail},apad", "-t", duration.round(3).to_s,
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", fit_path
  else
    # Each crossfade consumes `xfade` of overlap, so n copies span
    # n*seg_len - (n-1)*xfade.
    copies = (((duration - xfade) / (seg_len - xfade)).ceil + 1).clamp(2, 64)
    inputs = Array.new(copies) { ["-i", seg_path] }.flatten
    chain = []
    prev = "0:a"
    (1...copies).each do |i|
      out = i == copies - 1 ? "xf" : "xf#{i}"
      chain << "[#{prev}][#{i}:a]acrossfade=d=#{xfade.round(3)}:c1=tri:c2=tri[#{out}]"
      prev = out
    end
    chain << "[#{prev}]#{outer}#{tail}[vout]"
    dmesg("rap-vocal loop: #{copies} copies of #{seg_len.round(2)}s, #{xfade.round(2)}s crossfades",
          unit: "vox0", parent: "dilla0")
    sh! "ffmpeg", "-y", *inputs, "-filter_complex", chain.join(";"),
        "-map", "[vout]", "-t", duration.round(3).to_s,
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", fit_path
  end
  FileUtils.rm_f(seg_path)
  peak = band_rms(fit_path, highpass: 200, lowpass: 6_000) rescue -90.0
  sub_bleed = band_rms(fit_path, highpass: 30, lowpass: 120) rescue -90.0
  if peak < -50.0
    warn "rap-vocal fit: stem too quiet (rms≈#{peak.round(1)} dB) — #{fit_path}"
  end
  if sub_bleed > -38.0
    warn "rap-vocal fit: sub bleed still high (#{sub_bleed.round(1)} dB <120Hz) — re-clean recommended"
  end
  if entry.is_a?(Hash)
    entry["last_fit"] = { "path" => fit_path, "beat_bpm" => beat_bpm, "n_bars" => n_bars,
                          "offset_sec" => ss, "phrase_start" => phrase_start,
                          "source_bpm" => vocal_bpm, "tempo_ratio" => ratio.round(4),
                          "rms_db" => peak, "sub_bleed_db" => sub_bleed,
                          "snapped_lines" => snapped&.size, "has_pulse" => has_pulse,
                          "key_shift" => key_shift, "progression" => progression&.to_s,
                          "voice_only" => true }
    entry["bpm_estimate"] = vocal_bpm if vocal_bpm.positive?
    entry["voice_only"] = true
    cat = rap_vocal_load_catalog
    cat["vocals"] = Array(cat["vocals"]).map { |v| v["slug"] == entry["slug"] ? entry : v }
    rap_vocal_save_catalog!(cat)
  end
  placed = snapped ? " snapped=#{snapped.size}lines" : ""
  puts "rap-vocal fit: #{fit_path} src=#{vocal_bpm}bpm → #{beat_bpm}bpm " \
       "ratio=#{ratio.round(3)} start=#{ss}s bars=#{n_bars}#{placed} " \
       "voice≈#{peak.round(1)}dB sub≈#{sub_bleed.round(1)}dB"
  fit_path
end

def rap_vocal_mix_params
  # Level trim applied on top of the beat-relative anchor below. History: 1.15
  # (voice-forward) → 0.85 (pulled down on request) → 1.0. At 0.85, combined
  # with the old -6 dB anchor, the vocal landed ~7 dB under the beat in the
  # band where the two actually compete, which read as inaudible rather than
  # as "sitting in the mix". Anchor + trim are separate knobs now so the
  # placement target and the taste trim can move independently.
  vocal_vol = ENV.fetch("RAP_VOCAL_MIX", "1.0").to_f
  bed_w = ENV.fetch("RAP_VOCAL_BED_WEIGHT", "1.0").to_f
  voc_w = ENV.fetch("RAP_VOCAL_WEIGHT", "1.0").to_f
  # 3.0 dB of shelf from 9 kHz up, an octave and a bit wide, on a source that
  # already gets +2.2 dB at 3.2 kHz from the isolation chain and has no de-esser
  # anywhere after it. That stacked boost on sibilants is the "sharp" report.
  # 1.0 dB keeps consonants legible without the top-end edge, and the deesser
  # below catches what remains.
  sparkle_db = ENV.fetch("RAP_VOCAL_SPARKLE_DB", "1.0").to_f
  deess = ENV.fetch("RAP_VOCAL_DEESS", "0.35").to_f.clamp(0.0, 1.0)
  hpf_hz = ENV.fetch("RAP_VOCAL_HPF", "90").to_f
  lowmid_cut_db = ENV.fetch("RAP_VOCAL_LOWMID_CUT_DB", "2.0").to_f
  { vocal_vol:, bed_w:, voc_w:, sparkle_db:, deess:, hpf_hz:, lowmid_cut_db: }
end

# Mirrors DillaGroove's snare pocket push (role_timing_offset's early-snare
# tick offset) so the vocal's overall entry lands in the pushed pocket the
# backbeat sits in, instead of dead-on-grid. A rap vocal phrases off the
# snare, not the kick; this nudges the clip's anchor, not per-syllable timing.
def rap_vocal_pocket_nudge_sec(beat_bpm)
  return 0.0 if ENV["RAP_VOCAL_POCKET_NUDGE"] == "0"
  return 0.0 unless defined?(DillaGroove) && DillaGroove.enabled?
  beat_p = 60.0 / beat_bpm.to_f
  tick = beat_p / 96.0
  mul = DillaGroove.pocket_dna? ? 4 : 3
  tick * mul
end

# Gain staging is load-bearing here. amix runs normalize=0, so the weights
# are absolute: the voice reaches the limiter at vocal_vol*voc_w against the
# bed at bed_w. Push that ratio too far and alimiter clamps on every vocal
# peak and applies the reduction to the whole mix, taking the kit down with
# it. Keep the ratio modest and let the voice sit, rather than buying
# presence with gain the limiter then reclaims from the drums. Filter chain
# stays single-stage on purpose (no gate/compressor/sidechain): that
# combination previously made a good vocal source disappear once mixed.
def mix_rap_vocal_layer!(beat_path, vocal_path, dest, beat_bpm: nil)
  mix = rap_vocal_mix_params
  # Normalize the fitted stem against the beat BEFORE the mix knob: stems
  # arrive at wildly different levels (gunnhild's demucs stem is far quieter
  # than jonas_v's was), so a fixed multiplier made quiet stems disappear
  # into the bed entirely. RAP_VOCAL_MIX now means the same thing for every
  # stem: 1.0 = voice band anchored 6 dB under the full beat.
  beat_rms = band_rms(beat_path, highpass: 20, lowpass: 20_000)
  voice_rms = band_rms(vocal_path, highpass: 150, lowpass: 8_000)
  # Where the vocal sits relative to the beat, in dB. 0.0 = level with it,
  # negative tucks it under. beat_rms here is the FULL band (20-20k), so 0.0
  # anchored the voice band level with kick, bass and kit summed together —
  # which is louder than a lead vocal sits in any mix, and is the "way too loud"
  # report. History: -6.0 (inaudible, because it stacked with a 0.85 trim) →
  # 0.0 (too loud) → -3.0. The trim knob is separate now, so the earlier
  # -6 dB failure does not apply to this value.
  anchor_db = ENV.fetch("RAP_VOCAL_ANCHOR_DB", "-3.0").to_f
  norm_db = ((beat_rms + anchor_db) - voice_rms).clamp(-12.0, 24.0)
  nudge = beat_bpm ? rap_vocal_pocket_nudge_sec(beat_bpm) : 0.0
  trim = nudge.positive? ? "atrim=start=#{nudge.round(4)},asetpts=PTS-STARTPTS," : ""
  filter = [
    "[1:a]aformat=channel_layouts=stereo,#{trim}volume=#{norm_db.round(2)}dB," \
    "highpass=f=#{mix[:hpf_hz]}," \
    "bass=g=-#{mix[:lowmid_cut_db]}:f=300:width_type=o:width=1.0," \
    "treble=g=#{mix[:sparkle_db]}:f=9000:width_type=o:width=1.2," \
    "#{mix[:deess].positive? ? "deesser=i=#{mix[:deess].round(2)}:m=0.5:f=0.18," : ''}" \
    "volume=#{mix[:vocal_vol]}[v0]",
    # The vocal keys a duck on the beat. Both halves of this used to be one
    # fixed amix into a limiter, and that is why the voice came and went: the
    # weights are constant, so when the beat thickens the SUM rises, the limiter
    # pulls the whole sum down, and the vocal — the smaller part of it — goes
    # down with the beat. Thin the beat out again and the voice reappears. It
    # was never the vocal moving; it was the bed moving under a shared limiter.
    #
    # Turning the voice up is the wrong repair. Level is what drives the limiter,
    # so a louder vocal makes the pumping worse and adds the hardness that reads
    # as saturation. Ducking the bed instead makes room without adding level:
    # the sum gets quieter while the rap is going, so the limiter does less work
    # exactly when intelligibility matters most.
    #
    # Measured, not estimated: against a steady key at -30 dB threshold the bed
    # drops 4.50 dB at ratio 2, against 0.30 dB at ratio 1 and 7.40 dB at
    # ratio 6. Four and a half dB is the broadcast voiceover range — decisive
    # enough that the voice sits in front, short of the audible pump of a
    # dance-mix sidechain. A real vocal is intermittent where the test key was
    # steady, so that figure is the ceiling rather than the average.
    # 6 ms catches a syllable onset; 260 ms is longer than the gap
    # between words, so it rides a whole line rather than chattering between
    # them, which is the difference between presence and a tremolo.
    "[v0]asplit=2[v_mix][v_key]",
    "[0:a][v_key]sidechaincompress=" \
    "threshold=#{RAP_VOCAL_DUCK_THRESHOLD_DB}dB:ratio=#{RAP_VOCAL_DUCK_RATIO}:" \
    "attack=6:release=260:makeup=1:detection=rms:link=average[bed]",
    "[bed][v_mix]amix=inputs=2:weights=#{mix[:bed_w]} #{mix[:voc_w]}:duration=first:dropout_transition=0:normalize=0," \
    "alimiter=limit=0.96:level_out=0.97[out]",
  ].join(";")
  sh! "ffmpeg", "-y", "-i", beat_path, "-i", vocal_path,
      "-filter_complex", filter,
      "-map", "[out]", *codec_for(dest), dest
end
