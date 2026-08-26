# frozen_string_literal: true
#
# Choosing and voice-leading the progression for a render.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def safe_producer_progression(track)
  DillaLofiMachine.progression_for(track)
rescue StandardError => e
  warn "progression_for(#{track}): #{e.message}"
  nil
end

def dilla_progression(mode = :maj7_minor_cycle)
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym
  mode_sym = mode.to_sym
  prog_env = ENV["PROGRESSION"].to_s.downcase.tr("-", "_")
  prog_sym = prog_env.empty? ? nil : prog_env.to_sym
  # Catalog first. Learned aliases were collapsing every TRACK into a truncated
  # 6-chord promo loop (Dbmaj9…Abmaj9low) — theory and sound both suffered.
  prefer_learned = ENV.fetch("LEARNED_PROGRESSION", "0") != "0"
  catalog_keys = [prog_sym, mode_sym, track].compact.uniq
  unless prefer_learned
    catalog_keys.each do |key|
      pads = curated_progression_pads(key)
      return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
      pads = safe_producer_progression(key)
      return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
    end
  end
  eng = load_learned_engine
  learned_keys = [eng.dig("track_aliases", track.to_s), track.to_s, mode_sym.to_s, prog_env].compact.uniq
  learned_keys.each do |key|
    next if key.to_s.empty?
    pads = learned_progression_pads(key)
    return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
  end
  if prefer_learned
    catalog_keys.each do |key|
      pads = curated_progression_pads(key)
      return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
      pads = safe_producer_progression(key)
      return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
    end
  end
  if (producer_pads = safe_producer_progression(track))&.length.to_i >= 2
    return voice_led_pad_progression(producer_pads)
  end
  sonic = sonic_profile_for(track)
  engine_pads = progression_from_engine(sonic, mode)
  return voice_led_pad_progression(engine_pads) if engine_pads&.any?

  if GENERATED_STYLES.include?(mode.to_sym) || mode.to_sym == :generated
    root_hz = (ENV["GEN_ROOT"] || 130.81).to_f
    gen_mode = (ENV["GEN_MODE"] || "minor").to_sym
    length = (ENV["GEN_LENGTH"] || 8).to_i
    seed = ENV["GEN_SEED"]&.to_i
    style = mode.to_sym == :generated ? (ENV["GEN_STYLE"] || "functional").to_sym : mode.to_sym
    style = :functional if DillaHarmony.block_generated?(track, style)
    routed = route_generated_style(style, root_hz:, mode: gen_mode, length:, seed:)
    return voice_led_pad_progression(routed) if routed
    case style
    when :planing then return voice_led_pad_progression(generate_planing_progression(root_hz:, mode: gen_mode, length:, seed:))
    when :chromatic_mediant then return voice_led_pad_progression(generate_chromatic_mediant_progression(root_hz:, length:, seed:))
    when :polytonal then return voice_led_pad_progression(generate_polytonal_progression(root_hz:, mode: gen_mode, length:, seed:))
    when :negative_harmony then return voice_led_pad_progression(generate_negative_harmony_progression(root_hz:, mode: gen_mode, length:, seed:))
    when :neapolitan then return voice_led_pad_progression(generate_neapolitan_progression(root_hz:, length:, seed:))
    else return voice_led_pad_progression(generate_progression(root_hz:, mode: gen_mode, length:, seed:))
    end
  end
  names = CHORD_PROGRESSIONS.fetch(mode.to_sym, CHORD_PROGRESSIONS.fetch(:soul))
  voice_led_pad_progression(names.filter_map { |n| resolve_pad_chord_symbol(n) })
end

# Closest-tone voice leading + close jazz voicing so pads don't thrash register.
# Not every chord should bloom.
#
# 68% of the 1366 chords in the catalogue are ninths — m9 at 35%, maj9 at 33% —
# against 0.9% maj7 and 2.6% m7. Voiced literally, every chord is as lush as
# every other, so none of them arrive: an extension only reads as colour when
# something plainer sits next to it. This is why the harmony felt uniform rather
# than thin.
#
# Rather than rewrite 248 curated progressions, the extension is thinned at
# voicing time on passing chords — which is what a keys player does. The first
# and last chord keep their full voicing, because those are the arrival and the
# turnaround; interior chords lose their topmost tone on an alternating basis.
# Deterministic by position, so a progression voices the same way every render.
#
# HARMONIC_VARIETY=0 voices every chord in full, as before.
def harmonic_variety? = ENV.fetch("HARMONIC_VARIETY", "1") != "0"

def thin_passing_extensions(pads)
  return pads unless harmonic_variety? && pads.length >= 4

  pads.map.with_index do |ch, i|
    next ch unless ch.is_a?(Hash)
    next ch if i.zero? || i == pads.length - 1 || i.odd?

    hz = Array(ch[:hz])
    # Four voices is already a seventh chord; thinning below that removes chord
    # tones rather than colour, so leave those alone.
    next ch if hz.length <= 4

    ch.merge(hz: hz.sort.first(hz.length - 1))
  end
end

def voice_led_pad_progression(pads)
  return pads if pads.nil? || pads.length < 2
  return pads if ENV.fetch("VOICE_LEAD_PADS", "1") == "0"

  pads = thin_passing_extensions(pads)
  style = (ENV["VOICING"] || "rootless").to_s.downcase.tr("-", "_").to_sym
  style = :rootless unless DillaHarmony::VOICING_STYLES.include?(style)
  # `style` has to reach more than the `!= :cluster` test. Computed and consulted
  # only there, VOICING and the per-track VOICING_ROTATION select nothing: every render gets
  # the default spread shape on chord one and raw template stacks after it. The
  # style has to reach the voicing engine for the rotation to be audible.
  led = DillaHarmony.voice_lead_chords(pads, rootless: style != :cluster, voicing: style)
  return pads if led.nil? || led.empty?
  led.map.with_index do |ch, i|
    src = pads[i] || pads.last
    name = ch.is_a?(Hash) ? (ch[:name] || src[:name]) : src[:name]
    hz = ch.is_a?(Hash) ? ch[:hz] : ch
    { name:, hz:, bass_hz: src[:bass_hz] || src[:hz]&.min }
  end
rescue StandardError
  pads
end

def dilla_chord_bass_hz(chord)
  return 43.65 unless chord.is_a?(Hash)
  # Prefer the chord's declared bass over the lowest voiced tone. Slash chords
  # (D/E, Db/E, … — the whole Get Dis Money cycle) carry their pedal in
  # :bass_hz, and voice_led_pad_progression deliberately collapses :hz into a
  # narrow mid register for smooth pad motion. Taking hz.min there meant the
  # bass followed a voiced upper tone instead of the root: for D/E it played
  # G#3 (207.7 Hz) rather than E2 (82.4 Hz) — wrong note, and over an octave
  # above bass register, so the pedal that defines the progression vanished
  # and the track had no low end. Rootless pads over a real bass is the
  # correct division of labour; :bass_hz is what makes it work.
  bass = chord[:bass_hz] || (chord[:hz]&.any? ? chord[:hz].min : nil)
  bass || 43.65
end

def hz_to_midi(hz)
  DillaHarmony.hz_to_midi(hz)
end

def midi_to_hz(midi)
  DillaHarmony.midi_to_hz(midi)
end

def voice_lead_chords(chords)
  DillaHarmony.voice_lead_chords(chords)
end
