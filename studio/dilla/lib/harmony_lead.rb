# frozen_string_literal: true

# Chord-harmonic arp layer — arpeggiates voiced pad tones + extensions,
# voice-led across changes. Scale passing tones stay on scale_lead stem.
module DillaHarmonyLead
  PAD_REGISTER_CEILING = 76.0
  LEAD_REGISTER_LOW = 58.0
  LEAD_REGISTER_HIGH = 92.0

  EXTENSION_IV = {
    "maj9" => [2, 4], "m9" => [2, 5], "maj7" => [4], "m7" => [5, 10],
    "7" => [4, 10], "m11" => [2, 5, 7], "maj6" => [4, 9], "m6" => [5, 9],
    "9" => [2, 4], "11" => [2, 5, 7], "13" => [2, 4, 9]
  }.freeze

  module_function

  def normalized_symbol(name)
    name.to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "").downcase.gsub(/low\z/, "")
  end

  def extension_semitones(sym)
    base = sym.gsub(%r{/.*\z}, "")
    EXTENSION_IV.each do |suffix, ivs|
      return ivs if base.end_with?(suffix) || base == suffix
    end
    return [2, 4] if base.include?("maj9") || base.include?("m9")
    return [4] if base.include?("maj7") || base.match?(/7\z/)
    [2]
  end

  def voice_lead_arp_targets(tones_hz, prev_chord)
    return tones_hz unless prev_chord && prev_chord[:hz]&.any?
    prev_top = DillaHarmony.hz_to_midi(prev_chord[:hz].max)
    tones_hz.sort_by do |hz|
      m = DillaHarmony.hz_to_midi(hz)
      (m - prev_top).abs + (m < prev_top ? 4.0 : 0.0)
    end
  end

  def harmonic_arp_tones_for_chord(chord, prev_chord: nil, mode: :hybrid)
    return [] unless chord && chord[:hz]&.any?

    sym = normalized_symbol(chord[:name])
    tones = chord[:hz].sort.dup
    root_midi = DillaHarmony.hz_to_midi(tones.first).floor
    extension_semitones(sym).each do |iv|
      midi = root_midi + iv
      midi += 12 while midi < LEAD_REGISTER_LOW
      tones << DillaHarmony.midi_to_hz(midi) if midi <= LEAD_REGISTER_HIGH
    end
    tones = voice_lead_arp_targets(tones.uniq, prev_chord) if prev_chord
    floor = DillaHarmony.hz_to_midi(tones.max) >= PAD_REGISTER_CEILING ? PAD_REGISTER_CEILING : LEAD_REGISTER_LOW
    tones.filter_map do |hz|
      m = DillaHarmony.hz_to_midi(hz)
      next if m < floor - 2
      hz
    end.uniq.sort
  end

  def arp_style_for_change(prev_chord, chord, insight: nil)
    return :coltrane unless prev_chord && chord
    prev_sym = normalized_symbol(prev_chord[:name])
    sym = normalized_symbol(chord[:name])
    return :quint_spread if sym.include?("eb") && prev_sym.include?("bb")
    return :call if insight && insight[:notation].to_s.include?("V")
    return :motif if prev_sym == sym
    prev_iv = chord_intervals_simple(prev_chord)
    cur_iv = chord_intervals_simple(chord)
    shared = (prev_iv & cur_iv).length
    shared >= 3 ? :motif : :quint_spread
  end

  def chord_intervals_simple(chord)
    midis = chord[:hz].map { |h| DillaHarmony.hz_to_midi(h) }.sort
    root = midis.first
    midis.map { |m| ((m - root) % 12).round }.uniq
  end

  def section_density(section, progress)
    base = case section
           when :intro then 0.42
           when :breakdown then 0.52
           when :turn then 0.88
           when :build then 0.95
           when :outro then 0.58
           else 0.78
           end
    base * (progress < 0.1 ? 0.72 : 1.0)
  end

  def passing_tone_hz(chord, step, rng)
    return unless chord && chord[:hz]&.any?
    return if rng.rand > 0.14
    scale = chord_scale_semitones(chord)
    root = DillaHarmony.hz_to_midi(chord[:hz].min).floor
    semi = scale[(step + rng.rand(0..2)) % scale.length]
    midi = root + semi + 12
    return unless midi.between?(LEAD_REGISTER_LOW, LEAD_REGISTER_HIGH)
    DillaHarmony.midi_to_hz(midi)
  end

  # Chord → scale degrees (tonal-style heuristics; keeps arps in key with pads).
  def chord_scale_semitones(chord)
    name = normalized_symbol(chord[:name])
    return [0, 2, 3, 5, 7, 9, 10] if name.include?("dor") || name.include?("m11") || name.include?("m9")
    return [0, 2, 3, 5, 7, 8, 10] if name.match?(/\bm\d/) || name.include?("min") ||
                                      (name.include?("m") && !name.include?("maj") && !name.include?("dim"))
    return [0, 2, 3, 5, 6, 8, 10] if name.include?("dim") || name.include?("m7b5")
    return [0, 1, 3, 5, 7, 8, 10] if name.include?("phry")
    return [0, 2, 4, 6, 7, 9, 11] if name.include?("lyd") || name.include?("maj13") || name.include?("maj9")
    return [0, 2, 4, 5, 7, 9, 10] if name.match?(/7\z/) || name.include?("dom") || name.include?("mix")
    return [0, 2, 4, 5, 7, 9, 11] if name.include?("maj") || name.include?("add9") || name.match?(/\A[a-g][#b]?(6|)\z/)
    [0, 2, 4, 5, 7, 9, 11]
  end
end
