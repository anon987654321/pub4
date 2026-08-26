# frozen_string_literal: true
#
# Composition session state and the resolved per-render config.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# --- J Dilla Time beat engine (MPC3000 cyclic microtiming) ---

COMPOSITION_SECTION_KIND = {
  intro: :intro, verse: :main, hook: :build, bridge: :main,
  solo: :build, breakdown: :breakdown, outro: :outro
}.freeze

def composition_enabled?
  ENV["COMPOSITION"] != "0"
end

def composition_session!(n_bars: nil, track: nil, force_new: false)
  if force_new
    remove_instance_variable(:@composition_session) if instance_variable_defined?(:@composition_session)
  end
  return @composition_session if !force_new && instance_variable_defined?(:@composition_session) && @composition_session && !n_bars
  # What was actually ASKED for, before the "yancey"/"donuts" fallbacks below
  # flatten "unset" and "set to the default" into the same value. Session.load!
  # needs that distinction: a nil means "keep what the file has", and without it
  # every render would overwrite the evolved session's performer with a default
  # nobody chose.
  asked = ->(key) {
    v = ENV[key].to_s.strip
    v.empty? ? nil : v.downcase.tr("-", "_").to_sym
  }
  asked_performer = asked.call("PERFORMER")
  asked_groove = asked.call("GROOVE_DNA")
  asked_track = track || (ENV["TRACK"].to_s.strip.empty? ? nil : ENV["TRACK"].to_s.strip)

  track ||= (ENV["TRACK"] || "timeless").to_s
  n_bars ||= bars
  performer = asked_performer || :yancey
  groove = asked_groove || :donuts
  apply_learned_env_for_track!(track.to_s) if track
  @composition_session = if composition_enabled? && !force_new && File.exist?(DillaComposition::SESSION_PATH)
                           DillaComposition::Session.load!(default_track: track, n_bars:,
                                                           performer: asked_performer,
                                                           groove_dna: asked_groove,
                                                           track: asked_track)
                         else
                           DillaComposition::Session.new(track:, performer:,
                                                         groove_dna: groove, n_bars:)
                         end
  composition_feed_from_learn!(@composition_session)
  @composition_session
end

def reset_composition_session!
  remove_instance_variable(:@composition_session) if instance_variable_defined?(:@composition_session)
end

def dilla_timing_ms(role, bar_index, step_index, timing = nil, beat_p = nil)
  base = cyclic_timing_offset(role, bar_index, step_index, timing, beat_p, cycle: 4)
  return base unless composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
  perf = @composition_session.performer_profile
  groove = @composition_session.groove_profile
  extra = case role
          when :kick_anchor, :kick_sync then perf[:kick_lag_ms]
          when :snare then perf[:snare_early_ms]
          when :hat_down, :hat_up then perf[:hat_late_ms]
          when :bass then (perf[:kick_lag_ms] * 1.6).round(1)
          when :ghost then (perf[:ghost_boost] * 4 - 4).round(1)
          else 0
          end
  dna = if %i[kick_anchor kick_sync].include?(role)
          groove[:kick_offset_ms][step_index % groove[:kick_offset_ms].length]
        elsif %i[hat_down hat_up].include?(role)
          groove[:hat_offset_ms][step_index % groove[:hat_offset_ms].length]
        else
          0
        end
  (base + extra + dna).round(3)
end

def time_of_day_swing_offset
  hour = Time.now.hour
  # Peaks around 2-4am (loosest/latest feel), tightest around 2pm.
  distance_from_3am = [((hour - 3) % 24), (24 - ((hour - 3) % 24))].min
  (4.0 - distance_from_3am * (4.0 / 12.0)).round(1)
end

def dilla_resolve_config
  cfg = enhanced_resolve_config
  cfg = apply_profile_mash!(cfg)
  cfg = apply_form_to_cfg!(cfg)
  prog_override = ENV["PROGRESSION"]
  if prog_override
    cfg = cfg.merge(progression: prog_override.to_s.downcase.tr("-", "_").to_sym)
  end
  cfg
end

def dilla_chord_index(bar, pad_chords, chord_bars:, phrase_bars: nil, chord_bar_lens: nil)
  return 0 if pad_chords.nil? || pad_chords.empty?
  if chord_bar_lens&.any?
    cum = 0
    chord_bar_lens.each_with_index do |len, idx|
      cum += [len, 1].max
      return idx % pad_chords.length if bar < cum
    end
    return (pad_chords.length - 1) % pad_chords.length
  end
  slot = bar / [chord_bars, 1].max
  if la_beat_progression_enabled? || ENV.fetch("LINEAR_CHORD_INDEX", "0") != "0"
    return slot % pad_chords.length
  end
  if phrase_bars
    slots_per_phrase = [phrase_bars / [chord_bars, 1].max, 1].max
    slot % [slots_per_phrase, pad_chords.length].min
  else
    slot % pad_chords.length
  end
end

def dilla_swing_offset(step_index, step_p, swing, quintuplet: false, bar: 0, bpm: 90)
  return 0.0 if swing.to_f <= 0.0 || step_index.even?
  amount = swing.clamp(0.0, 100.0) / 100.0
  tick_sec = step_p / 24.0 # 96 ticks/beat, step_p is a 16th (1/4 beat) -> 24 ticks/step
  # NOTE: swing_jitter_ms is intentionally NOT added here -- every caller of
  # this function separately routes the same (bpm, step, bar) through
  # DillaGroove.apply_event_timing!/apply_pocket_place right after, which
  # already adds swing_jitter_ms itself. Adding it here too silently doubled
  # the jitter magnitude on every single scheduled hit in the whole engine.
  unless quintuplet
    base = (step_p * amount * 0.5)
    ticks = tick_sec.positive? ? (base / tick_sec).round : 0
    return ticks * tick_sec
  end
  # Real Dilla technique (Charnas/Hein analysis): the beat divides into 5
  # equal parts, not the standard 4 (16ths) or 6 (triplets) — the "and"
  # lands at the 3rd of 5 divisions, a 3:2 ratio rather than 2:1. That's a
  # different rhythmic subdivision, not just a different swing percentage.
  beat_p = step_p * 4.0
  quintuplet_pos = beat_p * 3.0 / 5.0
  straight_pos = step_p * 2.0
  base = (quintuplet_pos - straight_pos) * amount
  ticks = tick_sec.positive? ? (base / tick_sec).round : 0
  ticks * tick_sec
end

def dilla_velocity(base, bar_index, step_index, spread: 0.10)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    spread = @composition_session.performer_profile[:velocity_spread]
    spread += (ENV["VELOCITY_SPREAD_NUDGE"] || "0").to_f
    groove = @composition_session.groove_profile
    curve = groove[:velocity_curve]
    base *= curve[step_index % curve.length] if curve
  end
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym
  spread += DillaLofiMachine.humanize_ticks_for(track) * 0.012 if DillaLofiMachine.harmony_profile?(track)
  seed = (bar_index * 1_009) + (step_index * 313) + (base * 10_000).to_i
  rng = Random.new(seed)
  gaussian = Math.sqrt(-2.0 * Math.log([rng.rand, 1e-9].max)) * Math.cos(2.0 * Math::PI * rng.rand)
  [[base * (1.0 + gaussian * spread), 0.03].max, 1.0].min.round(3)
end

GENERATED_STYLES = %i[
  functional planing chromatic_mediant polytonal negative_harmony neapolitan
  major_third_cycle_full backdoor slash modal_interchange tritone_sub
].freeze

def resolve_pad_chord_symbol(n)
  PAD_CHORD_LOOKUP[n] || MODAL_MINOR_CHORDS.find { |c| c[:name] == n } ||
    begin
      DillaLofiMachine.chord_from_symbol(n)
    rescue StandardError
      nil
    end
end

def curated_progression_pads(key)
  sym = key&.to_sym
  return unless sym
  if artist_verified_only? && !ARTIST_VERIFIED_PROGRESSIONS.key?(sym)
    return
  end
  names = artist_verified_chords(sym) || CHORD_PROGRESSIONS[sym]
  return unless names.is_a?(Array) && names.length >= 2
  pads = names.filter_map { |n| resolve_pad_chord_symbol(n) }
  pads.length >= 2 ? pads : nil
end
