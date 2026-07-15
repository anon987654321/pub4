# frozen_string_literal: true

# Lo-fi machine semantics — timing, drum grids, chord voicings, and harmony
# profiles (no song titles). Ported from RG-69 reference + production DNA.
module DillaLofiMachine
  CHORD_TEMPLATES = {
    "maj" => [0, 4, 7],
    "min" => [0, 3, 7],
    "7" => [0, 4, 7, 10],
    "maj7" => [0, 4, 7, 11],
    "m7" => [0, 3, 7, 10],
    "m9" => [0, 3, 7, 10, 2],
    "maj9" => [0, 4, 7, 11, 2],
    "6" => [0, 4, 7, 9],
    "m11" => [0, 3, 7, 10, 5]
  }.freeze

  NOTE_PC = {
    "C" => 0, "B#" => 0, "Db" => 1, "C#" => 1, "D" => 2, "Eb" => 3, "D#" => 3,
    "E" => 4, "Fb" => 4, "F" => 5, "Gb" => 6, "F#" => 6, "G" => 7, "Ab" => 8,
    "G#" => 8, "A" => 9, "Bb" => 10, "A#" => 10, "B" => 11, "Cb" => 11
  }.freeze

  DILLA_TIMING = {
    snare: -22..-10, ghost: -12..10, hat_down: -2..4, hat_up: 12..24,
    kick_anchor: 4..10, kick_sync: 8..18, bass: 24..38, pad: 4..14
  }.freeze

  FLYLO_TIMING = {
    snare: -26..-12, ghost: -8..14, hat_down: 4..10, hat_up: 16..32,
    kick_anchor: 2..8, kick_sync: 6..16, bass: 22..42, pad: 6..18
  }.freeze

  MADLIB_TIMING = {
    snare: -20..-8, ghost: -6..16, hat_down: 0..8, hat_up: 10..22,
    kick_anchor: 3..9, kick_sync: 7..16, bass: 20..36, pad: 2..12
  }.freeze

  # Warm mid-register voicings (Hz) — chord palette, not song references.
  CHORD_VOICINGS = {
    "Bbm" => [233.08, 277.18, 349.23],
    "Ab" => [207.65, 261.63, 311.13],
    "Fm7" => [174.61, 207.65, 261.63, 311.13],
    "Fm" => [174.61, 207.65, 261.63],
    "Cm" => [130.81, 155.56, 196.00],
    "Gm" => [196.00, 233.08, 293.66],
    "Ebmaj7" => [155.56, 196.00, 233.08, 293.66],
    "Db" => [138.59, 174.61, 207.65],
    "Dbmaj7" => [138.59, 174.61, 207.65, 261.63],
    "Cm7" => [130.81, 155.56, 196.00, 233.08],
    "Bbm7" => [116.54, 138.59, 174.61, 207.65],
    "Dm" => [146.83, 174.61, 220.00],
    "Am" => [110.00, 130.81, 164.81]
  }.freeze

  PAD_WAVEFORMS = %i[sine square sawtooth triangle].freeze

  # 16-step MPC grids: kicks/snares/hats/ghosts/claps/perc + swing/humanize.
  DRUM_PRESETS = {
    dilla_slight: {
      swing: 57, humanize: 2, bpm: 95, mode: :dilla_time,
      kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 10], claps: [4, 12], perc: [3, 11]
    },
    dilla_drunk: {
      swing: 62, humanize: 4, bpm: 92, mode: :dilla_time,
      kicks: [0, 3, 6, 10, 13], snares: [4, 7, 12],
      hats: [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15],
      ghosts: [5, 14], claps: [12], perc: [2, 10, 15]
    },
    madlib_dusty: {
      swing: 60, humanize: 3, bpm: 93, mode: :dilla_time,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [1, 3, 5, 7, 9, 11, 13, 15],
      ghosts: [6, 14], claps: [4, 12], perc: [6, 14]
    },
    flylo_abstract: {
      swing: 54, humanize: 5, bpm: 84, mode: :straight_sixteenth,
      kicks: [0, 5, 8, 13], snares: [2, 6, 10, 15],
      hats: [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15],
      ghosts: [7, 13], claps: [7, 13], perc: [1, 5, 8, 12]
    },
    mpc3000: {
      swing: 62, humanize: 2, bpm: 90, mode: :dilla_time,
      kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 9], claps: [4, 12], perc: [3, 11]
    },
    sp303: {
      swing: 58, humanize: 2, bpm: 96, mode: :dilla_time,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [1, 3, 5, 7, 9, 11, 13, 15],
      ghosts: [], claps: [], perc: [6, 14]
    },
    sp1200: {
      swing: 54, humanize: 1, bpm: 90, mode: :dilla_time,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 10], claps: [4, 12], perc: []
    },
    boom_808: {
      swing: 50, humanize: 1, bpm: 90, mode: :straight_sixteenth,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: (0..15).to_a,
      ghosts: [], claps: [4, 12], perc: []
    }
  }.freeze

  LOFI_DEFAULTS = {
    bit_depth: 12, vinyl: 0.40, pad_lowpass_hz: 3200, master_lowpass_hz: 2800,
    pad_attack_ms: 800, pad_release_ms: 2000, pad_volume_pct: 40,
    filter_cutoff_hz: 12_000
  }.freeze

  DEFAULT_DRUM_PRESET = :dilla_slight
  DEFAULT_PAD_WAVE = :sine
  DEFAULT_PROFILE = :minor_iv_loop

  # Semantic harmony profiles — chord chemistry + groove family, no song names.
  HARMONY_PROFILES = {
    maj7_minor_cycle: {
      producer: :dilla, key: "Ab / Fm", bpm: 94, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Dbmaj7 Cm7 Fm7 Bbm7], timing: DILLA_TIMING
    },
    minor_iv_loop: {
      producer: :dilla, key: "F minor", bpm: 91, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Bbm Ab Fm7 Fm], timing: DILLA_TIMING
    },
    major_lifting: {
      producer: :dilla, key: "E major", bpm: 96, swing: 53,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Emaj7 G#m7 G#m7 G#maj7], timing: DILLA_TIMING
    },
    slash_ninth_cycle: {
      producer: :dilla, key: "C# minor", bpm: 90, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[C#m9 G#m9 A#7 C#maj9], timing: DILLA_TIMING
    },
    two_chord_hypnosis: {
      producer: :dilla, key: "Eb minor", bpm: 92, swing: 57,
      chord_bars: 4, phrase_bars: 8, feel: :dilla_drunk, voicing: :spread,
      drum_preset: :dilla_drunk, chords: %w[Ebm7 Bbm7], timing: DILLA_TIMING
    },
    relative_major_turn: {
      producer: :dilla, key: "G major", bpm: 88, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Cmaj9 Bm7 Am7 D7], timing: DILLA_TIMING
    },
    minor_turnaround: {
      producer: :dilla, key: "G major", bpm: 90, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Bm7 Bm7 Cmaj9 Em7], timing: DILLA_TIMING
    },
    warm_minor_arc: {
      producer: :dilla, key: "Bb / Dm", bpm: 86, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :madlib_dusty, voicing: :spread,
      drum_preset: :madlib_dusty, chords: %w[Dm7 Cm7 Fmaj9 Gm7], timing: DILLA_TIMING
    },
    quartal_west_coast: {
      producer: :flylo, key: "C major", bpm: 84, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :flylo_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true, intro_bars: 8,
      drum_preset: :flylo_abstract, chords: %w[Cmaj9 Am9 Fmaj9 G6], timing: FLYLO_TIMING
    },
    slow_ballad_wash: {
      producer: :flylo, key: "G major", bpm: 81, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :flylo_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract, chords: %w[G6 Em9 Cmaj9 Dmaj9], timing: FLYLO_TIMING
    },
    minor_triad_walk: {
      producer: :madlib, key: "D minor", bpm: 96, swing: 58,
      chord_bars: 2, phrase_bars: 8, feel: :sp303, voicing: :spread,
      drum_preset: :sp303, chords: %w[Dm Gm Am], timing: MADLIB_TIMING
    },
    neo_soul_pocket: {
      producer: :dilla, key: "Dm", bpm: 93, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Dm7 Eb7 Gm7 Am7], timing: DILLA_TIMING
    }
  }.freeze

  # Old track ids → semantic profile (backward compat only).
  LEGACY_ALIASES = {
    timeless: :maj7_minor_cycle,
    time_donut: :maj7_minor_cycle,
    fall_in_love: :minor_iv_loop,
    climax: :major_lifting,
    get_dis_money: :slash_ninth_cycle,
    thelonious: :two_chord_hypnosis,
    selfish: :relative_major_turn,
    look_of_love: :minor_turnaround,
    so_far_to_go: :warm_minor_arc,
    flylo_camel: :quartal_west_coast,
    flylo_roberta: :slow_ballad_wash,
    madlib_accordion: :minor_triad_walk
  }.freeze

  STREAM_ROTATION = %w[
    maj7_minor_cycle minor_iv_loop slow_ballad_wash two_chord_hypnosis relative_major_turn
    minor_turnaround warm_minor_arc quartal_west_coast minor_triad_walk
    major_lifting slash_ninth_cycle neo_soul_pocket
  ].freeze

  CURATED_PROGRESSIONS = HARMONY_PROFILES.keys.freeze

  module_function

  def normalize_profile(track)
    sym = track.to_s.downcase.tr("-", "_").to_sym
    LEGACY_ALIASES.fetch(sym, sym)
  end

  def harmony_profile?(track)
    HARMONY_PROFILES.key?(normalize_profile(track))
  end

  def profile_entry(track)
    HARMONY_PROFILES[normalize_profile(track)]
  end

  def profile_preset(track)
    entry = profile_entry(track)
    return nil unless entry
    drum_key = (ENV["DRUM_PRESET"] || entry[:drum_preset] || DEFAULT_DRUM_PRESET).to_s.downcase.tr("-", "_").to_sym
    preset = entry.slice(:bpm, :chord_bars, :phrase_bars, :swing, :feel, :voicing, :quintuplet,
                         :stereo_pan, :sidechain, :intro_bars, :half_time_bars, :timing, :drum_preset)
                  .merge(progression: normalize_profile(track), producer: entry[:producer], drum_preset: drum_key)
    drum = DRUM_PRESETS[drum_key] || DRUM_PRESETS[DEFAULT_DRUM_PRESET]
    preset[:feel] = drum_key
    preset[:swing] = drum[:swing] if drum && !ENV["SWING"]
    preset[:bpm] = drum[:bpm] if drum && !ENV["BPM"]
    preset[:quintuplet] = drum[:mode] == :dilla_time if drum && !ENV["QUINTUPLET"]
    preset
  end

  def progression_for(track)
    entry = profile_entry(track)
    return nil unless entry
    entry[:chords].map { |sym| chord_from_symbol(sym) }
  end

  def drum_pattern_set(preset_key)
    p = DRUM_PRESETS[preset_key]
    return nil unless p
    {
      kicks: [p[:kicks]], snares: [p[:snares]], hats: [p[:hats]],
      ghosts: [p[:ghosts]], opens: [6, 14], claps: [p[:claps]], perc: [p[:perc]],
      swing: p[:swing], humanize: p[:humanize]
    }
  end

  def humanize_ms(bpm, ticks = 2)
    beat_ms = 60_000.0 / bpm
    (beat_ms / 96.0 * ticks).round(2)
  end

  def humanize_ticks_for(track)
    entry = profile_entry(track)
    drum_key = entry&.dig(:drum_preset) || entry&.dig(:feel) || DEFAULT_DRUM_PRESET
    if ENV["DRUM_PRESET"]
      drum_key = ENV["DRUM_PRESET"].to_s.downcase.tr("-", "_").to_sym
    end
    DRUM_PRESETS.dig(drum_key, :humanize) || DRUM_PRESETS.dig(DEFAULT_DRUM_PRESET, :humanize) || 0
  end

  def chord_from_symbol(sym)
    sym = sym.to_s.strip
    if (hz = CHORD_VOICINGS[sym])
      return { name: sym, hz: hz.dup }
    end
    m = sym.match(/\A([A-G][#b]?)(m9|m7|m11|maj9|maj7|m|7|6)?\z/i)
    raise ArgumentError, "bad chord symbol: #{sym}" unless m
    root_name = m[1][0].upcase + m[1][1..]
    suffix = m[2].to_s.downcase
    quality = case suffix
              when "" then "maj9"
              when "m" then "m9"
              when "maj7" then "maj7"
              when "maj9" then "maj9"
              when "m7" then "m7"
              when "m9" then "m9"
              when "7" then "7"
              when "6" then "6"
              when "m11" then "m11"
              else "maj9"
              end
    root_hz = note_hz(root_name, octave: 3)
    hz = build_voicing(root_hz, quality)
    { name: sym, hz: hz }
  end

  def note_hz(name, octave: 3)
    base = name[0].upcase
    acc = name[1..] || ""
    acc = acc.tr("♯", "#").tr("♭", "b")
    pc = NOTE_PC.fetch("#{base}#{acc}")
    midi = 12 + (octave * 12) + pc
    (440.0 * (2.0**((midi - 69.0) / 12.0))).round(2)
  end

  def build_voicing(root_hz, quality, voices: 4)
    intervals = CHORD_TEMPLATES.fetch(quality) { CHORD_TEMPLATES["maj9"] }
    hz = intervals.map { |iv| (root_hz * (2**(iv / 12.0))).round(2) }
    extra = intervals.max + 2
    hz << (root_hz * (2**(extra / 12.0))).round(2) while hz.length < voices
    voiced = hz.sort.first(voices)
    midis = voiced.map { |h| 69.0 + 12.0 * Math.log2(h / 440.0) }
    midis = midis.map { |m| m + 12.0 while m < 50.0; m -= 12.0 while m > 76.0; m }
    midis.map { |m| (440.0 * (2.0**((m - 69.0) / 12.0))).round(2) }.uniq.first(voices)
  end

  def mpc_swing_from_sonic_fraction(frac)
    (50.0 + frac.to_f * 25.0).clamp(52.0, 62.5)
  end

  def lofi_sonic_overlay(_track = nil)
    l = LOFI_DEFAULTS
    {
      "pad_lowpass_hz" => env_i("PAD_LOWPASS", l[:pad_lowpass_hz]),
      "master_lowpass_hz" => env_i("MASTER_LOWPASS", l[:master_lowpass_hz]),
      "vinyl_noise" => (env_i("VINYL", (l[:vinyl] * 100).round) / 100.0 * 0.2).round(3),
      "crush_mix" => ((16 - env_i("BIT_DEPTH", l[:bit_depth])).to_f / 16.0 * 0.35).round(2),
      "pad_attack_ms" => env_i("PAD_ATTACK", l[:pad_attack_ms]),
      "pad_release_ms" => env_i("PAD_RELEASE", l[:pad_release_ms]),
      "pad_volume_pct" => env_i("PAD_VOL", l[:pad_volume_pct])
    }
  end

  def pad_waveform
    w = (ENV["PAD_WAVE"] || DEFAULT_PAD_WAVE).to_s.downcase.to_sym
    PAD_WAVEFORMS.include?(w) ? w : DEFAULT_PAD_WAVE
  end

  def native_wave_for_pad
    { sine: :triangle, triangle: :warm_pad, square: :organ, sawtooth: :pwm }[pad_waveform]
  end

  def machine_status(track = nil)
    track ||= ENV["TRACK"] || DEFAULT_PROFILE
    entry = profile_entry(track)
    drum_key = (ENV["DRUM_PRESET"] || entry&.dig(:drum_preset) || DEFAULT_DRUM_PRESET).to_s
    {
      profile: normalize_profile(track),
      key: entry&.dig(:key),
      drum_preset: drum_key,
      pad_wave: pad_waveform,
      dfam: ENV["DFAM"] != "0",
      lofi: LOFI_DEFAULTS,
      drum_presets: DRUM_PRESETS.keys
    }
  end

  def env_i(key, default)
    v = ENV[key]
    return default if v.nil? || v.empty?
    v.to_i
  end

  # --- backward-compatible aliases ---
  def producer_track?(track)
    harmony_profile?(track)
  end

  def track_entry(track)
    profile_entry(track)
  end

  def track_preset(track)
    profile_preset(track)
  end

  RG69_CHORDS = CHORD_VOICINGS.transform_values { |hz| { hz: hz } }.freeze
  RG69_DRUM_PRESETS = DRUM_PRESETS
  RG69_LOFI = LOFI_DEFAULTS
  PRODUCER_TRACKS = HARMONY_PROFILES
end

DillaProducerDNA = DillaLofiMachine