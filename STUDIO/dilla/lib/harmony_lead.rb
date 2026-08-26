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
    "9" => [2, 4], "11" => [2, 5, 7], "13" => [2, 4, 9],
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
    return :major_third_cycle_full unless prev_chord && chord
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

  # Chord → scale degrees the lead may use, 0-11 from the chord root.
  #
  # This decides every note every lead layer plays: dilla.rb's own
  # chord_scale_semitones delegates here, and scale_tones_for_chord builds the
  # melodic lead, the scale arp and the harmony arp out of the result. It was
  # wrong on the single most common chord in the catalogue.
  #
  # The old version tested `name.match?(/7\z/)` for dominant BEFORE it tested
  # for major, against the whole symbol including its root letter. "cmaj7" ends
  # in a 7, so every major-seventh chord matched the dominant branch and never
  # reached the major one:
  #
  #   Cmaj7 -> [0,2,4,5,7,9,10]   Mixolydian. Flat 7.
  #
  # That hands the lead a Bb to play over a Cmaj7 whose defining tone is B --
  # a minor second on the chord's most exposed note, on every maj7 in every
  # progression. Minor chords took the earlier branch and were fine, which is
  # exactly the shape of the complaint: the pads were right and the lead was
  # fighting them.
  #
  # Dominant 13ths failed the other way. "c13" matches neither /7\z/ nor "maj",
  # so it fell through to the Ionian default and put a natural 7 over a chord
  # whose seventh is flat.
  #
  # Two changes stop both. The root letter is stripped first, so the suffix is
  # matched on its own and "maj7" can never look like a dominant. And the order
  # runs most-specific to least, with the fallthrough last rather than a
  # dominant rule sitting in front of it.
  #
  # The 4th is omitted from the major and dominant sets. The perfect 11th is the
  # avoid note over both -- it sits a semitone above the major 3rd and buries it
  # -- and standard practice is to drop it or sharpen it to #11. Minor keeps its
  # 4th, where the 11th is consonant and is half of what makes m11 voicings
  # sound the way they do. Chords that ask for the bright colour (lyd, maj9,
  # maj13) get the #11 instead of nothing.
  DORIAN = [0, 2, 3, 5, 7, 9, 10].freeze
  AEOLIAN = [0, 2, 3, 5, 7, 8, 10].freeze
  LOCRIAN = [0, 2, 3, 5, 6, 8, 10].freeze
  PHRYGIAN = [0, 1, 3, 5, 7, 8, 10].freeze
  LYDIAN = [0, 2, 4, 6, 7, 9, 11].freeze
  IONIAN_NO4 = [0, 2, 4, 7, 9, 11].freeze
  MIXO_NO4 = [0, 2, 4, 7, 9, 10].freeze

  def chord_quality(name)
    # Slash bass says nothing about the scale -- Bbm/E is still minor -- and the
    # root letter is what made "maj7" testable as a dominant.
    normalized_symbol(name).sub(%r{/.*\z}, "").sub(/\A[a-g][#b]?/, "")
  end

  # The five notes major and minor agree on: root, second, fourth, fifth,
  # flat seventh. Missing from it are the third and the sixth -- precisely the
  # two degrees that differ between the modes. A line drawn from these notes is
  # consonant over a loop whichever mode it turns out to be in.
  #
  # It is also, not by accident, the pentatonic scale that most of the world's
  # folk music is built from, so playing inside it costs nothing musically.
  NEUTRAL_PENTATONIC = [0, 2, 5, 7, 10].freeze

  def chord_scale_semitones(chord)
    # Set when the key detector read a root it trusts and a mode it does not.
    # See the harmonic guard in dilla.rb.
    return NEUTRAL_PENTATONIC if ENV["MODE_UNCERTAIN"] == "1"

    resolve_avoid_notes(scale_from_symbol(chord), chord)
  end

  def scale_from_symbol(chord)
    q = chord_quality(chord[:name])

    return LOCRIAN if q.include?("dim") || q.include?("m7b5") || q.include?("o7")
    return PHRYGIAN if q.include?("phry")
    # Minor before anything that could match a digit. "maj" is excluded so
    # "maj7" cannot be read as m-something.
    # Dorian is the default for minor, not Aeolian, and the clash check is what
    # settled it rather than taste. Aeolian's b6 sits a semitone above the 5th,
    # so over Am7 the lead gets an F to play against the chord's E -- the same
    # avoid-note shape that made maj7 fail, one degree along. Dorian's natural 6
    # has no note above a chord tone at all, and it is the minor sound this
    # idiom actually uses. AEOLIAN is kept for a chord that asks for the b6.
    if q.include?("aeol") || q.include?("nat_minor")
      return AEOLIAN
    elsif q.start_with?("dor") || (q.start_with?("m") && !q.start_with?("maj")) ||
          q.include?("min") || q.start_with?("-")
      return DORIAN
    end
    return LYDIAN if q.include?("lyd") || q.include?("maj9") || q.include?("maj13") || q.include?("#11")
    return IONIAN_NO4 if q.include?("maj") || q.include?("add9") || q.match?(/\A6?\z/)
    return MIXO_NO4 if q.match?(/\A(7|9|11|13)/) || q.include?("dom") || q.include?("mix") || q.include?("alt")

    IONIAN_NO4
  end

  # The chord's own voicing, as semitones from its root.
  #
  # The name is a label and the voicing is the fact. Bm7b5 as registered here
  # sounds a b9 that its symbol never mentions, and a scale chosen from the
  # symbol alone cannot know that.
  def voiced_semitones(chord)
    hz = chord[:hz]
    return [] unless hz.is_a?(Array) && hz.any?

    pc = root_pitch_class(chord[:name])
    return [] unless pc

    hz.map { |h| ((69 + (12 * Math.log2(h / 440.0))).round - pc) % 12 }.uniq
  end

  LETTER_PC = { "c" => 0, "d" => 2, "e" => 4, "f" => 5, "g" => 7, "a" => 9, "b" => 11 }.freeze

  def root_pitch_class(name)
    # Before the slash: an upper structure over a pedal is still rooted on the
    # upper structure, which is what chord_root_pc in dilla.rb decides too.
    m = normalized_symbol(name).split("/").first.to_s.match(/\A([a-g])([#b]?)/)
    return unless m && (base = LETTER_PC[m[1]])

    (base + (m[2] == "#" ? 1 : 0) - (m[2] == "b" ? 1 : 0)) % 12
  end

  # Drop scale degrees that sit a semitone ABOVE a note the chord is sounding.
  #
  # That interval is the one that reads as a mistake: the scale tone buries the
  # chord tone under it and the ear hears the clash rather than the colour. A
  # semitone BELOW is a leading tone and is left alone, because approaching a
  # chord tone from underneath is how melodies work.
  #
  # Doing this against the voicing rather than the symbol is what catches the
  # three chords the symbol-driven table still got wrong -- C7b9, E7b9 and
  # Bm7b5 all voice a b9 and were being handed the natural 9 above it.
  #
  # Only ever removes, never substitutes, and refuses to strip a scale below
  # four notes: a lead with nothing left to play is worse than one avoid note.
  MIN_SCALE_TONES = 4

  def resolve_avoid_notes(scale, chord)
    tones = voiced_semitones(chord)
    return scale if tones.empty?

    kept = scale.reject { |s| !tones.include?(s) && tones.include?((s - 1) % 12) }
    kept.length >= MIN_SCALE_TONES ? kept : scale
  end
end
