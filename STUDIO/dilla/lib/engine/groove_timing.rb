# frozen_string_literal: true
#
# Per-role swing offsets, cyclic timing drift and section density.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Different degrees of swing on different voices -- the near-polyrhythmic
# quality described in accounts of both producers, and the thing a single
# global swing figure cannot produce however large it is set.
#
# The kick is 0: locked to the grid, which is what everything else is heard as
# leaning against. Take that reference away and the leaning stops reading as
# feel and starts reading as an unsteady tempo. Percussion is furthest behind
# at 1.45 -- shakers and maracas played deliberately late are named repeatedly
# as the source of the push and pull against kick and snare.
# The melodic roles were missing entirely, and they are the busiest roles in the
# engine: lead appears 90 times, warm 75, ep 50, texture 28. With no entry they
# fell through `SWING_ROLE_SCALE[role] || 1.0` and were swung at exactly the
# hi-hat rate — the most exaggerated lean in the kit — while bass sat at 0.3 and
# pad at 0.5 because someone had already decided sustained material should lean
# less than the hats.
#
# That is backwards for this feel. The records this engine is named after put the
# keys and the lead behind or across the drums, not locked to the hat; a Rhodes
# chord swung as hard as a shaker is the sound of a sequencer, which is the one
# thing the pocket exists to avoid. Sustained voices take the pad's 0.5, leads
# sit a little further back at 0.6 — enough to be heard leaning, short of the
# ghost-note 1.2 that would make a held note sound late rather than lazy.
#
# `kick` was the other one, and it is a plain defect: kick_anchor is 0.0 because
# it is the grid reference everything else leans against, and a bare `:kick`
# role — three call sites — was swinging at 1.0. Same drum, opposite treatment,
# decided by which name the call site happened to use.
SWING_ROLE_SCALE = {
  kick_anchor: 0.0, kick: 0.0, kick_sync: 0.15,
  snare: 0.85, clap: 0.85,
  hat_down: 1.0, hat_up: 1.1, hat: 1.0, open: 1.0,
  ghost: 1.2,
  perc: 1.45,
  bass: 0.3, pad: 0.5,
  ep: 0.5, warm: 0.5, texture: 0.4, native: 0.5,
  lead: 0.6, xlead: 0.6, scale_lead: 0.6, creative_lead: 0.6,
}.freeze
SWING_ROLE_SPREAD = ENV.fetch("SWING_ROLE_SPREAD", "1").to_f.clamp(0.0, 3.0)

# Swing above 50 expressed as milliseconds of lean for this role.
def swing_role_offset_ms(role, beat_p)
  return 0.0 if SWING_ROLE_SPREAD.zero? || beat_p.nil?

  # resolve_swing needs a preset and sonic that this call site does not have, so
  # read the pinned value and fall back to the researched figure rather than to
  # whatever the preset happens to carry. 54 sits inside the 53-56 those sources
  # give for the Dilla swing.
  swing = (ENV["SWING"] || 54).to_f
  return 0.0 unless swing > 50.0

  scale = SWING_ROLE_SCALE[role] || 1.0
  # An eighth is half a beat; a swing of 66 pushes the off-eighth by 16% of it.
  ((swing - 50.0) / 100.0) * (beat_p * 500.0) * scale * SWING_ROLE_SPREAD
end

def cyclic_timing_offset(role, bar_index, step_index, timing, beat_p, cycle: 4)
  range = timing&.fetch(role, nil) || MICROTIMING_MS.fetch(role)
  cyclic_bar = bar_index % cycle
  seed = (cyclic_bar * 97) + (step_index * 31) + stable_hash(role)
  raw = range.begin + (seed % (range.end - range.begin + 1))
  return raw unless beat_p

  # Per-role swing lean, added to every path below that has a beat period.
  sw = swing_role_offset_ms(role, beat_p)
  tick_ms = (beat_p * 1000.0) / 96.0
  quantized = ((raw / tick_ms).round * tick_ms).round(3)
  if ENV["NO_QUANTIZE"] == "1"
    jitter = Random.new(seed).rand(-2.0..2.0)
    return (quantized + jitter + sw).round(3)
  end
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym
  ticks = DillaLofiMachine.humanize_ticks_for(track)
  if ticks.positive?
    bpm = 60.0 / beat_p
    h_ms = DillaLofiMachine.humanize_ms(bpm, ticks)
    jitter = Random.new(seed + 17).rand(-h_ms..h_ms)
    return (quantized + jitter + sw).round(3)
  end
  (quantized + sw).round(3)
end

def phase_gain_multiplier(phase)
  case phase
  when :exposition then 0.94
  when :development then 0.78
  when :recapitulation then 1.0
  when :coda then 0.68
  else 1.0
  end
end

def chord_phase_at(bar, pad_chords, chord_phases, chord_bars:, phrase_bars: nil)
  return if pad_chords.nil? || pad_chords.empty? || chord_phases.nil? || chord_phases.empty?
  idx = dilla_chord_index(bar, pad_chords, chord_bars:, phrase_bars:)
  chord_phases[idx]
end

def section_density(bar, n_bars, chord_phases: nil, pad_chords: nil, chord_bars: 2, phrase_bars: nil)
  base = if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
           prof = @composition_session.profile_at(bar)
           tension = @composition_session.tension_at(bar)
           (prof[:drums] * 0.5 + tension * 0.5).clamp(0.2, 1.0)
         else
           sec = dilla_section_legacy(bar, n_bars)
           case sec
           when :intro then 0.55
           when :breakdown then 0.45
           when :build
             build_start = (n_bars * 0.82).to_i
             0.72 + 0.28 * ((bar - build_start).to_f / [n_bars * 0.18, 1].max).clamp(0.0, 1.0)
           when :outro then 0.5
           else 1.0
           end
         end
  phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars:, phrase_bars:)
  base * (phase ? phase_gain_multiplier(phase) : 1.0)
end
