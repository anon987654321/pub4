# frozen_string_literal: true
#
# Melodic lead writing: voice leading, phrase shape, parallel-interval rejection.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Occasional lead bursts — not every chord gets an arp. When they fire, use
# intricate patterns (euclidean, fibonacci, flylo wobble, etc.) with
# call-and-response and patch-specific gate lengths.
# --- The counter-line -------------------------------------------------------
#
# A second tune that answers the chords, instead of a busier copy of them.
#
# What was wrong. Every other lead in this file is built by walking the list of
# pad events -- the chords. For each chord it takes that chord's notes, starts
# when the chord starts, and stops when the chord stops. So the lead played the
# same notes as the backing, at the same moment, only faster. That is not a
# second part. It is the first part again with more notes in it, and it buried
# the chords rather than answering them.
#
# What this does instead. It asks the chords only one question -- "what notes
# are allowed right now?" -- and decides everything else itself: when to come
# in, how long to hold, which way to move, and how far behind the beat to sit.
#
# The rules below are borrowed, not invented. Sources are named where they
# apply. Nothing here is a matter of taste that could not be checked.

# A step is a tone or less. Anything past a fifth is a jump too far to sing.
LEAD_STEP_SEMITONES = 2
LEAD_LEAP_MAX = 7

# Where the line sits. Roughly a singer's range, centred near middle C, which
# is the neutral register string and vocal arrangers write pads in -- high
# enough to be heard over the chords, low enough not to shriek.
LEAD_RANGE_HZ = (220.0..880.0).freeze
LEAD_CENTRE_HZ = 330.0

# Beats within a bar where a note may start. Never the downbeat: the chord lands
# there, and the answer should arrive after the question.
LEAD_ONSET_BEATS = [1.0, 2.5, 3.0].freeze

# How far behind the beat the line sits, in MPC ticks at 96 PPQ.
#
# The whole engine is built on the idea that a part which lands exactly on the
# grid sounds like a machine, and lo-fi guidance says the same thing in plainer
# words: do not quantize everything, the moments that sit slightly off are where
# the feel comes from. The first version of this generator ignored all of that
# and placed every note on an exact grid position, in a file named after the
# producer whose entire signature is that his parts do not.
#
# Sung and bowed lines drag: a voice takes time to speak and a bow takes time to
# bite, so they arrive after the note they are answering. Hence a base lag,
# plus a small per-note wobble so no two entries are identical.
#
# Ticks rather than milliseconds, matching GROOVE_FEELS: the MPC3000 nudge tool
# could only land on tick boundaries, and a fractional offset is one the machine
# this models could never have produced.
LEAD_LAG_TICKS = 5
LEAD_LAG_JITTER_TICKS = 3
MPC_PPQ = 96

def melodic_lead_enabled? = ENV.fetch("MELODIC_LEAD", "1") != "0"

# How far apart two pitches are, in semitones. Positive means the second is
# higher.
def semitones_between(from_hz, to_hz)
  return 0.0 unless from_hz&.positive? && to_hz&.positive?

  12.0 * Math.log2(to_hz / from_hz)
end

# Are these the same note, ignoring which octave it lands in?
def same_pitch_class?(a_hz, b_hz)
  offset = semitones_between(a_hz, b_hz).abs % 12
  offset < 0.25 || offset > 11.75
end

# Which chord is sounding at this moment. The events are in time order, so the
# answer is the last one to have started.
def pad_chord_at(pad_events, time)
  pad_events
    .take_while { |(start, *)| start <= time + 1e-6 }
    .reverse_each
    .find { |(_, _, chord, _)| chord.is_a?(Hash) && chord[:hz]&.any? }
    &.fetch(2)
end

# The gap between the counter-line and the chord under it, folded into one
# octave. 0 is a unison or octave, 7 a perfect fifth.
def harmonic_interval(lead_hz, pad_hz)
  return unless lead_hz&.positive? && pad_hz&.positive?

  semitones_between(pad_hz, lead_hz).round % 12
end

PERFECT_INTERVALS = [0, 7].freeze

# The oldest rule in counterpoint, and the half I left out the first time.
#
# Two voices a fifth apart that both move and are still a fifth apart have, to
# the ear, stopped being two voices -- the interval is so consonant that the
# upper one is heard as an overtone of the lower. Octaves do it worse. Every
# species-counterpoint text forbids it and every generator that encodes those
# rules penalises it outright.
#
# The first version of this scorer rewarded contrary motion and stopped there,
# which catches only the case where both voices move the same way. Two voices
# CAN move in opposite directions and still arrive at consecutive fifths, and
# nothing here would have noticed.
def parallel_perfect?(prev_lead, lead, prev_pad, pad)
  return false unless prev_lead && prev_pad && lead && pad
  return false if prev_lead == lead || prev_pad == pad   # nothing moved

  before = harmonic_interval(prev_lead, prev_pad)
  after = harmonic_interval(lead, pad)
  return false unless before && after

  before == after && PERFECT_INTERVALS.include?(after)
end

# Per-phrase ceilings, from the same generators the motion rules come from.
#
# Each rule below is a cost, not a ban, so a single note can break one when
# every alternative is worse. Left at that, a whole phrase can be nothing but
# leaps, because each leap won its own comparison. These are the caps that stop
# a local decision becoming a global habit.
LEAD_PARALLEL_SHARE_MAX = 0.5
LEAD_LEAP_SHARE_MAX = 0.3
LEAD_REPEAT_SHARE_MAX = 0.5

# Rate one candidate note. Higher is better.
def lead_note_score(hz, prev_hz, pad_direction, chord, tally: nil, prev_pad_top: nil, pad_top: nil)
  return 0.0 unless hz&.positive?
  return 1.0 unless prev_hz&.positive?

  move = semitones_between(prev_hz, hz)
  distance = move.abs
  score = 0.0

  score += case distance
           when 0 then -0.6                        # standing still says nothing
           when ..LEAD_STEP_SEMITONES then 1.0     # a step: how tunes move
           when ..4 then 0.35                      # a small skip, still singable
           when ..LEAD_LEAP_MAX then -0.2          # a real jump, needs a reason
           else -1.0                               # further than anyone sings
           end

  # The rule that makes this a second voice rather than a thicker first one.
  unless pad_direction.zero? || move.zero?
    score += move.positive? == pad_direction.positive? ? -0.5 : 0.8
  end

  # Consecutive fifths and octaves, refused hard enough that only an empty
  # alternative set can let one through.
  score -= 3.0 if parallel_perfect?(prev_hz, hz, prev_pad_top, pad_top)

  # Notes already in the chord settle; the rest of the scale passes through.
  score += 0.3 if chord[:hz].any? { |chord_hz| same_pitch_class?(hz, chord_hz) }

  # Drift back toward the middle of the range, so a run of good local choices
  # cannot walk the line off the top or bottom of its register.
  score -= (semitones_between(LEAD_CENTRE_HZ, hz).abs / 24.0)

  score + phrase_cap_penalty(tally, move, pad_direction)
end

# Once a phrase has spent its allowance of leaps, repeats or parallel motion,
# more of the same gets expensive.
def phrase_cap_penalty(tally, move, pad_direction)
  return 0.0 unless tally && tally[:notes].positive?

  n = tally[:notes].to_f
  penalty = 0.0
  distance = move.abs
  parallel = !pad_direction.zero? && !move.zero? && (move.positive? == pad_direction.positive?)

  penalty -= 1.5 if parallel && (tally[:parallel] / n) >= LEAD_PARALLEL_SHARE_MAX
  penalty -= 1.5 if distance > 4 && (tally[:leaps] / n) >= LEAD_LEAP_SHARE_MAX
  penalty -= 1.5 if distance.zero? && (tally[:repeats] / n) >= LEAD_REPEAT_SHARE_MAX
  penalty
end

# Which way the chords have just moved: up, down, or nowhere.
def pad_direction(previous_top, current_top)
  return 0 unless previous_top && current_top

  current_top <=> previous_top
end

# Pick the moments in one phrase where the line may speak.
#
# The first bar is left alone on purpose -- the chords need a bar to say
# something before anything answers. The rest are spread evenly rather than
# chosen at random, because random picks clump and the gaps are the point.
def lead_onsets_for_phrase(phrase_start, phrase_bars, bar_p, beat_p, wanted, ceiling)
  candidates = (1...phrase_bars).flat_map do |bar|
    LEAD_ONSET_BEATS.map { |beat| phrase_start + (bar * bar_p) + (beat * beat_p) }
  end
  candidates.select! { |t| t < ceiling - beat_p }
  return [] if candidates.empty?

  stride = [candidates.length / wanted, 1].max
  candidates.each_slice(stride).map(&:first).first(wanted)
end

# A shape the line returns to.
#
# Without one, every phrase is decided note by note and nothing ever comes back,
# so a listener has nothing to recognise -- which is half of why a whole demo
# reads as repetitive without ever repeating anything memorable. Sample chopping
# is described as letting a producer shift the focus onto particular themes and
# motifs, and a motif is exactly what this engine had none of.
#
# The motif is stored as CONTOUR -- how many scale steps to move, not which
# notes -- so it survives being played over a different chord. Each phrase takes
# a transformation of it, in the order a composer would: state it, state it
# again, invert it, reverse it. That is repetition with variation, which is what
# holds attention, rather than either novelty or literal repeat.
LEAD_MOTIF_TRANSFORMS = %i[plain plain inverted retrograde].freeze

# Phrases where the line says nothing at all.
#
# A part that plays in every phrase stops being an answer and becomes a texture.
# The whole Detroit end of this lineage treats space as the instrument -- few
# elements, worked hard, with room around them -- and the arranging guidance
# says the same thing about counter-melodies: they go BETWEEN the phrases, and
# between means there are phrases they are not in.
#
# The third phrase of every four, and never the first.
#
# The shape has to be stated before its absence can be felt, and it has to come
# back afterwards or the silence reads as the piece ending rather than as
# breathing. Third of four gives state / state / gone / back.
#
# Not `phrase % 4 == 0`, which was the first attempt: over a 16-bar piece there
# are exactly four phrases, numbered 0 to 3, and none of 1, 2 or 3 is divisible
# by four -- so the rest never once happened at the length these actually render
# at. It measured as 4 phrases out of 4 playing.
LEAD_REST_EVERY = 4
LEAD_REST_PHASE = 2

def lead_phrase_rests?(phrase)
  return false if phrase.zero?
  return false if ENV.fetch("LEAD_PHRASE_RESTS", "1") == "0"

  (phrase % LEAD_REST_EVERY) == LEAD_REST_PHASE
end

# Ghost notes.
#
# The quiet, half-struck note just before the one that lands. On the drums it is
# the ghost snare that makes a Dilla pattern breathe instead of march, and it is
# the single most recognisable thing about the drum programming this engine is
# named for. There is no reason it should belong only to drums -- a singer
# scoops into a note and a bowed string speaks before it sounds.
#
# A sixteenth early, a third of the velocity, and a step below: quiet enough to
# be felt rather than heard, which is the point of a ghost.
LEAD_GHOST_VELOCITY = 0.34
LEAD_GHOST_LEAD_IN_BEATS = 0.25

def lead_ghost_for(time, velocity, hz, tones, beat_p, rng)
  return unless ENV.fetch("LEAD_GHOSTS", "1") != "0"
  return unless rng.rand < 0.35

  below = tones.select { |t| t < hz && semitones_between(t, hz) <= 3 }.max
  return unless below

  start = time - (LEAD_GHOST_LEAD_IN_BEATS * beat_p)
  return if start <= 0

  [start, velocity * LEAD_GHOST_VELOCITY, { name: "counter_ghost", hz: [below * counter_lead_detune] },
   LEAD_GHOST_LEAD_IN_BEATS * beat_p * 0.8]
end

def lead_motif(rng, length)
  # Small steps, mostly, with the occasional skip: a singable shape.
  Array.new(length) { [-2, -1, -1, 1, 1, 2, 3].sample(random: rng) }
end

def lead_motif_step(motif, transform, index)
  return 0 if motif.empty?

  case transform
  when :inverted then -motif[index % motif.length]
  when :retrograde then motif[(motif.length - 1 - (index % motif.length))]
  else motif[index % motif.length]
  end
end

def lead_events_melodic(pad_events, cfg, duration: nil, n_bars: nil)
  return [] if pad_events.empty? || !melodic_lead_enabled?

  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  tick_p = beat_p / MPC_PPQ
  total = duration || pad_events.map { |event| event[0].to_f + event[3].to_f }.max
  return [] unless total.to_f.positive?

  phrase_bars = ENV.fetch("LEAD_PHRASE_BARS", "4").to_i.clamp(1, 16)
  per_phrase = ENV.fetch("LEAD_NOTES_PER_PHRASE", "4").to_i.clamp(1, 12)
  answer_chords = ENV.fetch("LEAD_CONTRARY", "1") != "0"
  humanize = ENV.fetch("LEAD_HUMANIZE", "1") != "0"
  lag_ticks = ENV.fetch("LEAD_LAG_TICKS", LEAD_LAG_TICKS.to_s).to_i
  rng = Random.new(stable_hash(cfg[:track].to_s) + (@render_seed || 0) + 5501)

  motif = lead_motif(rng, per_phrase)
  phrase_p = bar_p * phrase_bars
  previous_hz = nil
  previous_top = nil

  (total / phrase_p).ceil.times.flat_map do |phrase|
    next [] if lead_phrase_rests?(phrase)

    onsets = lead_onsets_for_phrase(phrase * phrase_p, phrase_bars, bar_p, beat_p, per_phrase, total)
    transform = LEAD_MOTIF_TRANSFORMS[phrase % LEAD_MOTIF_TRANSFORMS.length]
    tally = { notes: 0, parallel: 0, leaps: 0, repeats: 0 }

    onsets.each_with_index.filter_map do |time, index|
      chord = pad_chord_at(pad_events, time)
      next unless chord

      tones = scale_tones_for_chord(chord)
      next if tones.empty?

      top = chord[:hz].max
      direction = answer_chords ? pad_direction(previous_top, top) : 0

      reachable = tones.select { |hz| LEAD_RANGE_HZ.cover?(hz) }
      reachable = tones if reachable.empty?
      if previous_hz
        near = reachable.select { |hz| semitones_between(previous_hz, hz).abs <= LEAD_LEAP_MAX }
        reachable = near unless near.empty?
      end

      # The motif proposes, the rules dispose. Where the motif's next step lands
      # is scored like any other candidate, so a shape that would cause parallel
      # fifths or walk off the register loses to one that does not -- the theme
      # survives, the mistakes do not.
      wanted = lead_motif_step(motif, transform, index)
      chosen = reachable.max_by do |hz|
        base = lead_note_score(hz, previous_hz, direction, chord,
                               tally:, prev_pad_top: previous_top, pad_top: top)
        steps = previous_hz ? (semitones_between(previous_hz, hz) / 2.0).round : 0
        base + (steps == wanted ? 0.9 : 0.0) + (rng.rand * 0.15)
      end
      next unless chosen

      next_time = onsets[index + 1] || (phrase * phrase_p) + phrase_p
      sustain = [[(next_time - time) * 0.82, beat_p * 0.75].max, total - time].min
      next if sustain <= 0.05

      # Sit behind the beat, and never twice by the same amount.
      offset = humanize ? (lag_ticks + rng.rand(-LEAD_LAG_JITTER_TICKS..LEAD_LAG_JITTER_TICKS)) * tick_p : 0.0
      start = (time + offset).clamp(0.0, total - sustain)

      if previous_hz
        move = semitones_between(previous_hz, chosen)
        tally[:leaps] += 1 if move.abs > 4
        tally[:repeats] += 1 if move.zero?
        tally[:parallel] += 1 if !direction.zero? && !move.zero? && (move.positive? == direction.positive?)
      end
      tally[:notes] += 1

      previous_hz = chosen
      previous_top = top
      velocity = (0.30 + (rng.rand * 0.06)) * (index.zero? ? 1.0 : 0.92)
      # Detuned in the note, not by varispeeding the finished layer -- see
      # counter_lead_space_chain for what that cost in timing.
      note = [start, velocity, { name: "counter_lead", hz: [chosen * counter_lead_detune] }, sustain]
      ghost = lead_ghost_for(start, velocity, chosen, reachable, beat_p, rng)
      ghost ? [ghost, note] : [note]
    end.flatten(1)
  end
end

def lead_events_creative(pad_events, cfg, duration: nil, n_bars: nil)
  return [] if pad_events.empty?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars ||= duration ? (duration / bar_p).ceil : 32
  seed = (stable_hash(cfg[:track].to_s) % 100_000) + (@render_seed || 0) + 8801
  rng = Random.new(seed)
  leitmotif = leitmotif_for(pad_events)
  arp_style = @render_arp_style || :updown
  lead_patch = @render_lead_patch
  gate_mul = (lead_patch&.fetch(:gate, 0.82) || 0.82)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    gate_mul *= @composition_session.performer_profile[:gate_mul]
  end
  octave_mul = 2.0 ** ((lead_patch&.fetch(:octave, 2) || 2) - 2)
  events = []
  burst_remaining = 0
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    next unless chord && chord[:hz]&.any?
    bar_approx = (time / bar_p).floor.clamp(0, n_bars - 1)
    section = dilla_section(bar_approx, n_bars)
    progress = i.to_f / [pad_events.length - 1, 1].max
    motif_cell = if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
                   @composition_session.motif_for_bar(bar_approx)
                 end
    leitmotif = motif_cell.degrees_for_playback if motif_cell
    if burst_remaining.positive?
      burst_remaining -= 1
    else
      chance = if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
                 prof = @composition_session.profile_at(bar_approx)
                 (prof[:lead] * prof[:melodic_density]).clamp(0.05, 0.92)
               else
                 lead_section_chance(section, progress)
               end
      chance += 0.15 if i % 11 == 5
      next unless rng.rand < chance
      burst_remaining = rng.rand(1..3)
    end
    # Scale-locked only — no chromatic approach tones off the pad harmony.
    tones = lead_scale_locked_tones_hz(chord, lead_patch:)
    tones = scale_tones_for_chord(chord) if tones.empty?
    next if tones.empty?
    if octave_mul != 1.0
      tones = tones.map { |hz| hz * octave_mul }.select do |hz|
        m = hz_to_midi(hz)
        m.between?(55, 90)
      end
      tones = lead_scale_locked_tones_hz(chord, lead_patch:) if tones.empty?
    end
    burst_cfg = { style: arp_style, subdiv: 2, gate: gate_mul, vel: 0.72 }
    variation = arp_variation_for_chord(i, chord, cfg, burst_cfg, patch: lead_patch, role: :creative_lead)
    pattern = case variation[:pattern_mode]
              when :motif then motif_from_chord(chord).map { |d| d % tones.length }
              when :retrograde then invert_motif(leitmotif)
              when :call then leitmotif + invert_motif(leitmotif)
              when :sparse then leitmotif.each_with_index.filter_map { |d, si| (si.even? || rng.rand < 0.5) ? d : nil }
              else [leitmotif, invert_motif(leitmotif), leitmotif.reverse,
                    arp_degrees_for(variation[:style], tones.length, rng),
                    leitmotif + invert_motif(leitmotif)][i % 5]
              end
    pattern = arp_pattern_for_chord(chord, variation, tones.length, rng) if rng.rand < 0.38
    subdiv = variation[:subdiv]
    step_dur = [(sustain || 1.0) / (pattern.length * subdiv.to_f), 0.045].max
    step_dur *= 1.35 if section == :build
    step_dur *= variation[:n_steps_mul].clamp(0.55, 1.0)
    swing_push = (cfg[:quintuplet] ? step_dur * 0.04 : 0.0) * variation[:swing_mul]
    pattern.each_with_index do |degree, step|
      next if arp_rest_step?(step, variation[:rest_prob], i + 500)
      hz = tones[degree % tones.length]
      # Diatonic approach: previous scale degree, never chromatic half-step.
      if step.zero? && i.positive? && tones.length > 1
        idx = tones.index(hz) || 0
        approach = tones[(idx - 1) % tones.length]
      else
        approach = hz
      end
      t = time + variation[:time_offset] + 0.04 + step * step_dur + (step.odd? ? swing_push : 0.0) +
          variation[:step_jitter] * ((step % 3) - 1) +
          DillaGroove.melody_time_offset(bar_approx, step, beat_p)
      vel = (velocity * (0.88 - step * 0.04)).clamp(0.18, 0.95)
      vel *= 1.12 if section == :build
      pan = if cfg[:stereo_pan]
step.even? ? -0.45 : 0.45
else
(step.even? ? -0.12 : 0.12)
end
      events << [t, vel, { name: "lead", hz: [approach] }, step_dur * gate_mul, pan]
    end
    next unless rng.rand < 0.55 && i.positive?
    answer_style = ARP_PATTERN_BUILDERS.keys.sample(random: rng)
    answer_pat = arp_degrees_for(answer_style, tones.length, rng)
    conv_offset = if composition_enabled?
                    DillaComposition::Conversation.answer_offset(:lead, beat_p)
                  else
                    0.0
                  end
    answer_offset = conv_offset + pattern.length * step_dur * 0.45
    answer_oct = 1.0
    answer_pat.each_with_index do |degree, step|
      hz = tones[degree % tones.length] * answer_oct
      t = time + 0.04 + answer_offset + step * step_dur * 1.1
      vel = (velocity * 0.42 * (1.0 - step * 0.03)).clamp(0.1, 0.55)
      pan = if cfg[:stereo_pan]
step.even? ? 0.55 : -0.55
else
(step.even? ? 0.18 : -0.18)
end
      events << [t, vel, { name: "lead_answer", hz: [hz] }, step_dur * gate_mul * 0.75, pan]
    end
  end
  events
end

def warm_dilla_pad_post(path, cfg: nil, sonic: nil)
  cfg ||= dilla_resolve_config
  sonic ||= cfg[:sonic]
  return path unless tool_available?("ffmpeg")
  lp = sonic_pad_lowpass(sonic)
  tmp = "#{path}.pad_tmp.wav"
  fluidsynth = defined?(@render_used_fluidsynth_pad) && @render_used_fluidsynth_pad
  filt = if fluidsynth
           [
             "aformat=channel_layouts=stereo",
             "lowpass=f=#{lp}:width_type=q:width=0.82",
             "equalizer=f=260:t=o:w=1.0:g=#{pad_mud_db(0.6)}",
             "equalizer=f=900:t=h:w=800:g=0.8",
             "equalizer=f=3200:t=h:w=1400:g=0.6",
             # aecho/chorus take in_gain:out_gain, NOT a wet/dry mix -- both
             # scale the whole signal. 0.34:0.44 is 0.15x (-16.7 dB) and
             # 0.34:0.54 another 0.18x (-12.4 dB); stacked they buried the
             # entire harmonic bus ~29 dB, which is why the chords were
             # inaudible under the drums. Effect depth lives in the decays
             # and depths args, so keep those and run the gains near unity.
             "aecho=0.9:0.85:90|180:0.2|0.1",
             "chorus=0.9:0.85:30|40:0.14|0.1:0.18|0.14:0.92|1.15",
             "acompressor=threshold=-22dB:ratio=1.5:attack=65:release=280:makeup=1.5",
             "volume=1.1",
             "alimiter=limit=0.96:level_out=0.98",
           ]
         else
           patch_fx = @render_warm_patch&.dig(:fx) || @render_ep_patch&.dig(:fx)
           [
             "aformat=channel_layouts=stereo",
             "lowpass=f=#{lp}:width_type=q:width=0.88",
             "equalizer=f=260:t=o:w=1.0:g=#{pad_mud_db}",
             "equalizer=f=520:t=h:w=700:g=#{pad_mud_db(0.9)}",
             "equalizer=f=1100:t=o:w=0.9:g=-0.6",
             "equalizer=f=3200:t=h:w=1600:g=1.0",
             ("tremolo=f=3.2:d=0.06" if cfg[:style_family] == :dilla),
             # Same in_gain:out_gain fix as the fluidsynth branch above.
             "aecho=0.9:0.85:100|180:0.2|0.1",
             "chorus=0.9:0.85:30|40:0.16|0.12:0.2|0.18:0.95|1.2",
             patch_fx,
             "acompressor=threshold=-24dB:ratio=1.6:attack=60:release=260:makeup=1.6",
             "volume=1.12",
             "alimiter=limit=0.96:level_out=0.98",
           ]
         end
  sh! "ffmpeg", "-y", "-i", path, "-af", filt.compact.join(","), "-c:a", "pcm_s16le", tmp
  FileUtils.mv(tmp, path)
  path
end
