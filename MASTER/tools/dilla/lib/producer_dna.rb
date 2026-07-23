# frozen_string_literal: true

require "yaml"
require "timeout"

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
    "m11" => [0, 3, 7, 10, 5],
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
    "Dbmaj9" => [138.59, 174.61, 207.65, 261.63, 311.13],
    "Cm7" => [130.81, 155.56, 196.00, 233.08],
    "Cm9" => [130.81, 155.56, 196.00, 233.08, 293.66],
    "Fm9" => [174.61, 207.65, 261.63, 311.13, 392.00],
    "Bbm7" => [116.54, 138.59, 174.61, 207.65],
    "Bbm9" => [116.54, 138.59, 174.61, 207.65, 261.63],
    "Eb9" => [155.56, 196.00, 233.08, 311.13, 349.23],
    "Eb7" => [155.56, 196.00, 233.08, 311.13],
    "Cm7b5" => [130.81, 155.56, 184.99, 233.08],
    # Root+m3+b5+m7 in D — same shape as Cm7b5 above. Precomputed to bypass a
    # DillaMusicGems.chord_from_symbol hang on "Dm7b5" (the gem adapter never
    # returns for this exact symbol; root cause not chased, this sidesteps it).
    "Dm7b5" => [146.83, 174.61, 207.65, 261.63],
    "C7" => [261.63, 329.63, 392.00, 466.16],
    "C7alt" => [130.81, 164.81, 233.08, 277.18, 311.13],
    # root+3rd+b7+b9+#9 in G — same altered-dominant shape as C7alt above.
    "G7alt" => [196.00, 246.94, 349.23, 415.30, 466.16],
    # Root+3rd+5th+maj7+9th in C — precomputed for the same reason as Dm7b5:
    # DillaMusicGems (coltrane gem) hangs on this exact symbol too, cold or
    # warm process. Worth a real fix in lib/music_gems.rb at some point —
    # this only sidesteps the two symbols the new catalog entries need.
    "Cmaj9" => [130.81, 164.81, 196.00, 246.94, 293.66],
    "Dm" => [146.83, 174.61, 220.00],
    "Am" => [110.00, 130.81, 164.81],
    # Researched voicings used in soul / Donuts progressions (Hz from PAD_CHORD_LOOKUP).
    "Abmaj9low" => [103.83, 130.81, 155.56, 196.00, 233.08],
    "Bb7sus" => [116.54, 155.56, 174.61, 207.65, 261.63],
    "C7b9" => [130.81, 138.59, 164.81, 196.00, 233.08],
    "Fm/C" => [130.81, 174.61, 207.65, 261.63, 311.13],
    "Fmaj9" => [174.61, 220.00, 261.63, 329.63, 392.00],
    "Bbmaj7" => [116.54, 146.83, 174.61, 207.65, 293.66],
    "Bbmaj9" => [116.54, 138.59, 174.61, 207.65, 261.63],
    "Abmaj7" => [207.65, 261.63, 311.13, 392.00, 466.16],
  }.freeze

  CHORD_SUFFIXES = %w[
    maj9low maj9 maj7 m11 m9 m7 m7b5 7b9 7sus4 7sus 7alt 7 6 m
  ].freeze

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
    },
    # Industrial techno: four-on-floor, hard clap 2+4, busy hats, little swing.
    industrial_techno: {
      swing: 50, humanize: 1, bpm: 128, mode: :straight_sixteenth,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: (0..15).to_a,
      ghosts: [], claps: [4, 12], perc: [2, 6, 10, 14]
    },
  }.freeze

  LOFI_DEFAULTS = {
    bit_depth: 12, vinyl: 0.40, pad_lowpass_hz: 3200, master_lowpass_hz: 2800,
    pad_attack_ms: 800, pad_release_ms: 2000, pad_volume_pct: 40,
    filter_cutoff_hz: 12_000
  }.freeze

  DEFAULT_DRUM_PRESET = :dilla_slight
  DEFAULT_PAD_WAVE = :sine
  DEFAULT_PROFILE = :get_dis_money

  # Semantic harmony profiles — chord chemistry + groove family, no song names.
  BASE_HARMONY_PROFILES = {
    # Slum Village / Dilla — Get Dis Money (Ethan Hein exact E-pedal slash cycle).
    get_dis_money: {
      producer: :dilla, key: "E pedal", bpm: 92, swing: 54,
      chord_bars: 1, phrase_bars: 6, feel: :mpc3000, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[D/E Db/E C/E Bm/E Bbm/E Am/E], timing: DILLA_TIMING
    },
    # Donuts "Time" researched core — IV–iii–vi–ii in Ab (clean 7ths).
    time_donut: {
      producer: :dilla, key: "Ab / Fm", bpm: 90, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :timeless, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Dbmaj7 Cm7 Fm7 Bbm7], timing: DILLA_TIMING
    },
    # Fall in Love = Diana in the Autumn Wind sample (Ebm7–Bbm7).
    fall_in_love: {
      producer: :dilla, key: "Eb minor", bpm: 91, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Ebm7fil Bbm7fil], timing: DILLA_TIMING
    },
    climax: {
      producer: :dilla, key: "E major", bpm: 88, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :timeless, voicing: :rootless,
      drum_preset: :dilla_slight, chords: %w[Emaj7 G#m7 C#m7 E7climax], timing: DILLA_TIMING
    },
    untitled_how_does_it_feel: {
      producer: :dilla, key: "D major", bpm: 92, swing: 56,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :rootless,
      drum_preset: :dilla_slight, chords: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9], timing: DILLA_TIMING
    },
    # Classic Fm soul loop — i–iv–bVII–bVI (NOT artist-verified; experimental).
    soul: {
      producer: :dilla, key: "F minor", bpm: 88, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :timeless, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Fm9 Bbm9 Ebmaj9 Dbmaj9], timing: DILLA_TIMING
    },
    # Same Time cycle with ninths.
    maj7_minor_cycle: {
      producer: :dilla, key: "Ab / Fm", bpm: 94, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :timeless, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Dbmaj9 Cm9 Fm9 Bbm9], timing: DILLA_TIMING
    },
    # Hooktheory Donuts "Time" — full IV–iii–vi–ii–V turnaround (8 bars).
    fourth_third_sixth_second_turn: {
      producer: :dilla, key: "Ab / Fm", bpm: 86, swing: 56,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight,
      chords: %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Bbm9 Ebmaj9], timing: DILLA_TIMING
    },
    # Measured Fm engine loop — i–IV–iii–vi–ii–V–bVI–IV.
    timeless_authentic: {
      producer: :dilla, key: "F minor", bpm: 86, swing: 56,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight,
      chords: %w[Fm9 Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9], timing: DILLA_TIMING
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
      producer: :flylo, key: "C major", bpm: 86, swing: 54,
      chord_bars: 2, phrase_bars: 32, feel: :flylo_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true, intro_bars: 8,
      drum_preset: :flylo_abstract, chords: %w[Cmaj9 Am9 Fmaj9 G6], timing: FLYLO_TIMING
    },
    # Chromatic mediant drift profile.
    chromatic_mediant_drift: {
      producer: :flylo, key: "D minor", bpm: 86, swing: 54,
      chord_bars: 2, phrase_bars: 32, feel: :flylo_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true, intro_bars: 8,
      drum_preset: :flylo_abstract,
      chords: %w[Dm9 Cm11nc AbMaj13s11 Gm7 Eb7 A7nc Dmaj9nc DMaj7overG],
      timing: FLYLO_TIMING
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
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Dm7 Eb7 Gm7 Am7], timing: DILLA_TIMING
    },
    neo_soul: {
      producer: :dilla, key: "F minor", bpm: 84, swing: 58,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread, stereo_pan: true,
      drum_preset: :dilla_slight,
      chords: %w[Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9 Cm9 C7b9 Fm9], timing: DILLA_TIMING
    },
    dorian_iv_loop: {
      producer: :dilla, key: "G dorian", bpm: 90, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Gm9 Cmaj9 Fmaj9 Bbmaj7], timing: DILLA_TIMING
    },
    backdoor_resolve: {
      producer: :dilla, key: "C minor", bpm: 88, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :rootless,
      drum_preset: :mpc3000, chords: %w[Fm7 Bb7 Ebmaj7 Abmaj7], timing: DILLA_TIMING
    },
    iv_borrow_minor: {
      producer: :dilla, key: "A minor", bpm: 89, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :drop2,
      drum_preset: :dilla_slight, chords: %w[Am9 Dm9 Fmaj9 Em7], timing: DILLA_TIMING
    },
    bvi_bvii_minor: {
      producer: :dilla, key: "E minor", bpm: 91, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_drunk, voicing: :spread,
      drum_preset: :dilla_drunk, chords: %w[Em7 Cmaj7 Dmaj7 Em7], timing: DILLA_TIMING
    },
    ii_v_i_major: {
      producer: :dilla, key: "Bb major", bpm: 92, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :drop2,
      drum_preset: :mpc3000, chords: %w[Cm9 F7 Bbmaj9 Gm7], timing: DILLA_TIMING
    },
    ii_v_i_minor: {
      producer: :dilla, key: "D minor", bpm: 90, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :rootless,
      drum_preset: :dilla_slight, chords: %w[Gm7 A7 Dm9 Cm7], timing: DILLA_TIMING
    },
    gospel_bIII: {
      producer: :dilla, key: "F major", bpm: 94, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Fmaj9 Abmaj7 Bbmaj7 Fmaj9], timing: DILLA_TIMING
    },
    stevie_bVII: {
      producer: :dilla, key: "C major", bpm: 93, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :kenny_barron,
      drum_preset: :mpc3000, chords: %w[Cmaj9 Bbmaj7 Fmaj9 G6], timing: DILLA_TIMING
    },
    erykah_minor: {
      producer: :dilla, key: "F# minor", bpm: 87, swing: 58,
      chord_bars: 2, phrase_bars: 16, feel: :madlib_dusty, voicing: :bill_evans,
      drum_preset: :madlib_dusty, chords: %w[F#m9 Bm7 Emaj7 C#m7], timing: MADLIB_TIMING
    },
    glasper_quartal: {
      producer: :flylo, key: "Eb major", bpm: 82, swing: 52,
      chord_bars: 2, phrase_bars: 16, feel: :flylo_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract, chords: %w[Ebmaj9 Cm9 Abmaj9 Bb6], timing: FLYLO_TIMING
    },
    watermelon_turn: {
      producer: :dilla, key: "G minor", bpm: 88, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Gm9 Cm7 Fmaj9 Bbmaj7], timing: DILLA_TIMING
    },
    church_sus: {
      producer: :dilla, key: "Db major", bpm: 86, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Dbmaj9 Gbmaj7 Ab6 Dbmaj9], timing: DILLA_TIMING
    },
    minMaj_color: {
      producer: :madlib, key: "C minor", bpm: 85, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :sp303, voicing: :cluster,
      drum_preset: :sp303, chords: %w[Cm7 Abmaj7 G7 Ebmaj7], timing: MADLIB_TIMING
    },
    dominant_turn: {
      producer: :dilla, key: "A minor", bpm: 92, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :drop3,
      drum_preset: :dilla_slight, chords: %w[Am9 D7 Gmaj7 E7], timing: DILLA_TIMING
    },
    deceptive_turn: {
      producer: :dilla, key: "E minor", bpm: 89, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :rootless,
      drum_preset: :mpc3000, chords: %w[Em9 B7 Cmaj9 Am9], timing: DILLA_TIMING
    },
    plagal_jazz: {
      producer: :dilla, key: "F major", bpm: 90, swing: 53,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Fmaj9 Bbmaj7 Cmaj9 Fmaj9], timing: DILLA_TIMING
    },
    slash_neo_soul: {
      producer: :dilla, key: "Bb major", bpm: 91, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :so_what,
      drum_preset: :dilla_slight, chords: %w[Dm7/F Fmaj9/A Gm7/Bb Cmaj9/E], timing: DILLA_TIMING
    },
    suspended_ballad: {
      producer: :flylo, key: "D major", bpm: 78, swing: 55,
      chord_bars: 4, phrase_bars: 16, feel: :flylo_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract, chords: %w[Dmaj9 Am9 Gmaj9], timing: FLYLO_TIMING
    },
    minor_line_cliche: {
      producer: :dilla, key: "A minor", bpm: 88, swing: 54,
      chord_bars: 1, phrase_bars: 8, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Am Am/G Fmaj7 E7], timing: DILLA_TIMING
    },
    donda_minor: {
      producer: :dilla, key: "F minor", bpm: 95, swing: 58,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_drunk, voicing: :drop2,
      drum_preset: :dilla_drunk, chords: %w[Fm7 Abmaj7 Bbm7 Fm7], timing: DILLA_TIMING
    },
    keys_woman: {
      producer: :dilla, key: "Eb major", bpm: 84, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :madlib_dusty, voicing: :kenny_barron,
      drum_preset: :madlib_dusty, chords: %w[Ebmaj9 Cm9 Fm7 Bb7], timing: MADLIB_TIMING
    },
    jazz_ballad_waltz: {
      producer: :flylo, key: "Ab major", bpm: 72, swing: 52,
      chord_bars: 2, phrase_bars: 16, feel: :flylo_abstract, voicing: :bill_evans,
      stereo_pan: true,
      drum_preset: :flylo_abstract, chords: %w[Abmaj9 Fm7 Bbm7 Eb7], timing: FLYLO_TIMING
    },
    turnaround_ii_v: {
      producer: :dilla, key: "G major", bpm: 91, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :drop2,
      drum_preset: :dilla_slight, chords: %w[Am7 D7 Gmaj9 Bm7], timing: DILLA_TIMING
    },
    modal_safe: {
      producer: :dilla, key: "D Mixolydian", bpm: 89, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :quartal,
      drum_preset: :mpc3000, chords: %w[Dmaj9 Cmaj9 Gmaj9 A7], timing: DILLA_TIMING
    },
    neo_iv_cycle: {
      producer: :dilla, key: "C minor", bpm: 90, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Cm9 Fm7 Bbmaj7 Ebmaj9], timing: DILLA_TIMING
    },
    # Raymond Scott Electronium × Dilla — Common "The Light" neo-soul cycle.
    electronium_loop: {
      producer: :dilla, key: "F minor", bpm: 86, swing: 57,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Fm9 Dbmaj9 Eb9 Bbm9 Cm7b5 Fm9 C7alt Fm9],
      timing: DILLA_TIMING
    },
    electronium_classic: {
      producer: :dilla, key: "F minor", bpm: 86, swing: 57,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Fm7 Dbmaj7 Eb7 Bbm7 Cm7b5 Fm7 C7 Fm7],
      timing: DILLA_TIMING
    },
    # Aydin Esen — quartal modal wash (Bill Evans / Turkish jazz lineage).
    aydin_modal_quartal: {
      producer: :dilla, key: "C minor", bpm: 82, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :quartal,
      drum_preset: :dilla_slight,
      chords: %w[Cm9 Fmaj9 Bbmaj9 Ebmaj9 Abmaj7 Dm9 Bb7sus Cm9], timing: DILLA_TIMING
    },
    # Aydin Esen — ii–V chains with altered dominants and rich extensions.
    aydin_jazz_turn: {
      producer: :dilla, key: "Bb major", bpm: 88, swing: 53,
      chord_bars: 2, phrase_bars: 16, feel: :mpc3000, voicing: :bill_evans,
      drum_preset: :mpc3000,
      chords: %w[Dm9 Gm9 C7b9 Fmaj9 Bbm9 Eb9 Abmaj9 Dm9], timing: DILLA_TIMING
    },
    # Bach — circle-of-fifths descent (functional voice-leading).
    bach_circle_descent: {
      producer: :dilla, key: "A minor", bpm: 76, swing: 52,
      chord_bars: 1, phrase_bars: 8, feel: :mpc3000, voicing: :drop2,
      drum_preset: :mpc3000,
      chords: %w[Am9 Dm9 G7 Cmaj9 Fmaj9 Bm7b5 E7b9 Am9], timing: DILLA_TIMING
    },
    # Bach — descending bass (passacaglia motion) in neo-soul voicings.
    bach_descending_bass: {
      producer: :dilla, key: "D minor", bpm: 80, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :kenny_barron,
      drum_preset: :dilla_slight,
      chords: %w[Dm9 Dm/C Bbmaj9 A7 Dm9 Gm9 Cmaj9 Fmaj9], timing: DILLA_TIMING
    },
    # --- Expansion pack ---
    # Informed by functional voice-leading (common tones, stepwise outer voices),
    # Donuts-era harmonic economy (short loops, borrowed color, human pocket),
    # and analog pad craft (Prophet/Moog sustain, Crane-Song-style soft saturation).
    # "Good progression" criteria: home-away-home, ≤2–3 shared tones between
    # neighbors when possible, one surprise per 4 bars, return by bar 8–16.
    lydian_glass_cycle: {
      producer: :dilla, key: "F Lydian-leaning", bpm: 88, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :flylo_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract,
      chords: %w[Fmaj9 Am9 Gmaj9 Em9 Fmaj9 Dm9 Cmaj9 G7], timing: FLYLO_TIMING
    },
    pedal_upper_structures: {
      producer: :dilla, key: "C pedal", bpm: 84, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread,
      drum_preset: :dilla_slight,
      chords: %w[Cm9 C7sus Ab/C F/C Bbmaj9/C Gm7/C Dbmaj9/C Cm9], timing: DILLA_TIMING
    },
    bossa_major9_turn: {
      producer: :dilla, key: "F major", bpm: 92, swing: 56,
      chord_bars: 2, phrase_bars: 16, feel: :dilla_slight, voicing: :bill_evans,
      drum_preset: :dilla_slight,
      chords: %w[Fmaj9 Em7b5 A7b9 Dm9 Gm9 C7sus Fmaj9 D7], timing: DILLA_TIMING
    },
    phrygian_gold_arc: {
      producer: :dilla, key: "E minor / Phrygian color", bpm: 90, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000,
      chords: %w[Em9 Fmaj9 Gmaj9 Am9 Fmaj7 G7sus Bm7b5 Em9], timing: DILLA_TIMING
    },
    two_chord_luminous: {
      producer: :dilla, key: "Db / Fm", bpm: 78, swing: 54,
      chord_bars: 4, phrase_bars: 16, feel: :flylo_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract,
      chords: %w[Dbmaj9 Fm9], timing: FLYLO_TIMING
    },
    mixo_sus_loop: {
      producer: :dilla, key: "D Mixolydian", bpm: 96, swing: 53,
      chord_bars: 1, phrase_bars: 8, feel: :mpc3000, voicing: :quartal,
      drum_preset: :mpc3000,
      chords: %w[Dmaj9 Cmaj9 Gmaj9 Dmaj9 F#m9 Em9 A7sus Dmaj9], timing: DILLA_TIMING
    },
    common_tone_drift: {
      producer: :flylo, key: "E common-tone field", bpm: 86, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :flylo_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract,
      chords: %w[Em9 Cmaj9 Am9 Fmaj9 Em9 Gmaj9 Bm9 Em9], timing: FLYLO_TIMING
    },
    coltrane_lite_triad: {
      producer: :dilla, key: "F minor stations", bpm: 82, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread,
      drum_preset: :dilla_slight,
      chords: %w[Fm9 Abmaj9 Bmaj9 Fm9 Dbmaj9 Emaj9 Abmaj9 Fm9], timing: DILLA_TIMING
    },
    drone_quartal_wash: {
      producer: :flylo, key: "D drone", bpm: 80, swing: 52,
      chord_bars: 4, phrase_bars: 16, feel: :flylo_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract,
      chords: %w[Dm9 G/D C/D Am9 Dm9 Fmaj9/D G/D Dm9], timing: FLYLO_TIMING
    },
    waltz_relative_lift: {
      producer: :dilla, key: "C minor → Eb", bpm: 72, swing: 52,
      chord_bars: 2, phrase_bars: 16, feel: :flylo_abstract, voicing: :bill_evans,
      stereo_pan: true,
      drum_preset: :flylo_abstract,
      chords: %w[Cm9 Abmaj9 Bb7 Ebmaj9 Fm9 Bb7 Ebmaj9 G7], timing: FLYLO_TIMING
    },
    half_time_gospel_plagal: {
      producer: :dilla, key: "Bb major", bpm: 74, swing: 54,
      chord_bars: 4, phrase_bars: 16, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight,
      chords: %w[Bbmaj9 Ebmaj9 Abmaj9 F7sus Bbmaj9 Ebmaj9 F7sus Bbmaj9], timing: DILLA_TIMING
    },
    double_time_pocket: {
      producer: :dilla, key: "E minor", bpm: 108, swing: 56,
      chord_bars: 1, phrase_bars: 8, feel: :dilla_drunk, voicing: :spread,
      drum_preset: :dilla_drunk,
      chords: %w[Em9 Am9 D7 Gmaj9 Em9 Am9 D7 Gmaj9], timing: DILLA_TIMING
    },
    whole_tone_bridge: {
      producer: :flylo, key: "whole-tone → F minor", bpm: 88, swing: 54,
      chord_bars: 1, phrase_bars: 8, feel: :flylo_abstract, voicing: :cluster,
      drum_preset: :flylo_abstract,
      chords: %w[C7 D7 E7 F#7 Fm9 Dbmaj9 Ebmaj9 Fm9], timing: FLYLO_TIMING
    },
    upper_triad_tower: {
      producer: :dilla, key: "Bb tower", bpm: 90, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :mpc3000, voicing: :so_what,
      drum_preset: :mpc3000,
      chords: %w[Bbmaj9 D/Bb F/Bb G/Bb Bbmaj9 Eb/Bb F/Bb Bbmaj9], timing: DILLA_TIMING
    },
    minor_add9_lullaby: {
      producer: :dilla, key: "G minor", bpm: 70, swing: 53,
      chord_bars: 4, phrase_bars: 16, feel: :flylo_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :flylo_abstract,
      chords: %w[Gm9 Ebmaj9 Cm9 D7sus Gm9 Ebmaj9 Fmaj9 Gm9], timing: FLYLO_TIMING
    },
    dominant_chain_home: {
      producer: :dilla, key: "circle of fifths 7ths", bpm: 94, swing: 54,
      chord_bars: 1, phrase_bars: 8, feel: :mpc3000, voicing: :drop2,
      drum_preset: :mpc3000,
      chords: %w[C7 F7 Bb7 Eb7 Abmaj9 Dbmaj9 Cm9 F7], timing: DILLA_TIMING
    },
  }.freeze

  # Additive entries sourced from dilla_reference.yml (documented Slum
  # Village / Flying Lotus track analysis) — merged in rather than hand-typed
  # here so the sourcing/citation stays in one place. Existing named profiles
  # above are never overwritten by this.
  def self.load_documented_progressions
    path = File.expand_path("../dilla_reference.yml", __dir__)
    return {} unless File.file?(path)

    entries = YAML.safe_load_file(path)["documented_progressions"] || {}
    entries.each_with_object({}) do |(key, e), out|
      producer = e["producer"].to_sym
      flylo = producer == :flylo
      out[key.to_sym] = {
        producer:, key: e["key"], bpm: e["bpm"], swing: e["swing"],
        chord_bars: e["chord_bars"], phrase_bars: e["phrase_bars"],
        voicing: e["voicing"].to_sym,
        feel: flylo ? :flylo_abstract : :timeless,
        drum_preset: flylo ? :flylo_abstract : :dilla_slight,
        chords: e["chords"],
        timing: flylo ? FLYLO_TIMING : DILLA_TIMING
      }
    end
  rescue StandardError, Psych::Exception => e
    warn "dilla_reference.yml: documented progressions not loaded (#{e.message})"
    {}
  end

  HARMONY_PROFILES = BASE_HARMONY_PROFILES.merge(load_documented_progressions).freeze

  # Old track ids → semantic profile (backward compat only).
  LEGACY_ALIASES = {
    timeless: :time_donut,
    players: :neo_soul_pocket,
    neo_soul: :neo_soul,
    slash_ninth_cycle: :get_dis_money,
    thelonious: :two_chord_hypnosis,
    selfish: :relative_major_turn,
    look_of_love: :minor_turnaround,
    so_far_to_go: :warm_minor_arc,
    flylo_camel: :chromatic_mediant_drift,
    flylo_roberta: :slow_ballad_wash,
    madlib_accordion: :minor_triad_walk,
    long_soul: :maj7_minor_cycle,
    golden: :neo_soul,
  }.freeze

  # Full stream rotation — verified Dilla/SV/D'Angelo songs first, then the
  # broader curated harmony pack so stream/demo cycles progressions + colors.
  STREAM_ROTATION = %w[
    get_dis_money time_donut fall_in_love climax untitled_how_does_it_feel
    maj7_minor_cycle alternating_minor7_pair syncopated_slash_ninth
    major7_relative_minor_turn sus_add9_ballad
    neo_soul_pocket erykah_minor warm_minor_arc minor_turnaround
    quartal_west_coast slash_ninth_cycle dorian_iv_loop gospel_bIII
    minor_iv_loop two_chord_hypnosis relative_major_turn
    electronium_loop fourth_third_sixth_second_turn
    chromatic_mediant_drift lydian_glass_cycle pedal_upper_structures
    bossa_major9_turn phrygian_gold_arc mixo_sus_loop common_tone_drift
    glasper_quartal minMaj_color church_sus jazz_ballad_waltz
  ].freeze

  CURATED_PROGRESSIONS = HARMONY_PROFILES.keys.freeze

  PROFILE_KEY_INDEX = HARMONY_PROFILES.keys.each_with_object({}) do |key, index|
    index[key.to_s.downcase.tr("-", "_").to_sym] = key
  end.freeze

  module_function

  def normalize_profile(track)
    sym = track.to_s.downcase.tr("-", "_").to_sym
    sym = LEGACY_ALIASES.fetch(sym, sym)
    PROFILE_KEY_INDEX.fetch(sym, sym)
  end

  def harmony_profile?(track)
    HARMONY_PROFILES.key?(normalize_profile(track))
  end

  def profile_entry(track)
    HARMONY_PROFILES[normalize_profile(track)]
  end

  def profile_preset(track)
    entry = profile_entry(track)
    return unless entry
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
    return unless entry
    pads = entry[:chords].filter_map do |sym|
      chord_from_symbol(sym)
    rescue ArgumentError
      nil
    end
    pads.length >= 2 ? pads : nil
  end

  def drum_pattern_set(preset_key)
    p = DRUM_PRESETS[preset_key]
    return unless p
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
    if defined?(DillaMusicGems)
      # The coltrane-gem path has hung indefinitely on specific symbols
      # (Dm7b5, Cmaj9 — see README) with no clear pattern; rather than wait
      # for the next one to be discovered by a stuck render, bound it and
      # fall through to the built-in suffix parser below on timeout.
      gem_chord = begin
        Timeout.timeout(1.5) { DillaMusicGems.chord_from_symbol(sym) }
      rescue Timeout::Error
        warn "chord_from_symbol: DillaMusicGems hung on #{sym.inspect}, falling back" if $VERBOSE
        nil
      end
      return gem_chord if gem_chord
    end
    if sym.include?("/")
      upper, bass_note = sym.split("/", 2)
      ch = chord_from_symbol(upper.strip)
      bass_hz = note_hz(bass_note.strip, octave: 2)
      hz = ch[:hz].dup
      hz[hz.index(hz.min)] = bass_hz
      return ch.merge(name: sym, hz: hz.sort.uniq, bass_hz:)
    end
    low_register = sym.match?(/low\z/i)
    base = sym.sub(/low\z/i, "")
    suffix = CHORD_SUFFIXES.find { |sfx| base.match?(/\A[A-G][#b]?#{sfx}\z/i) }
    raise ArgumentError, "bad chord symbol: #{sym}" unless suffix

    root_name = base.match(/\A([A-G][#b]?)/i)[1]
    root_name = root_name[0].upcase + root_name[1..]
    quality = case suffix.downcase
              when "maj9low", "maj9" then "maj9"
              when "maj7" then "maj7"
              when "m11" then "m11"
              when "m9" then "m9"
              when "m7", "m7b5" then "m7"
              when "7b9", "7alt", "7" then "7"
              when "7sus4", "7sus" then "7"
              when "6" then "6"
              when "m" then "m9"
              else "maj9"
              end
    octave = low_register ? 2 : 3
    root_hz = note_hz(root_name, octave:)
    hz = build_voicing(root_hz, quality)
    { name: sym, hz: }
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
    voiced = hz.sort.last(voices)
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
      "pad_volume_pct" => env_i("PAD_VOL", l[:pad_volume_pct]),
    }
  end

  def pad_waveform
    w = (ENV["PAD_WAVE"] || DEFAULT_PAD_WAVE).to_s.downcase.to_sym
    PAD_WAVEFORMS.include?(w) ? w : DEFAULT_PAD_WAVE
  end

  def native_wave_for_pad
    case ENV["PAD_VOICE"]&.downcase
    when "rhodes", "blend" then :rhodes
    when "moog" then :moog
    when "prophet" then :prophet
    else
      { sine: :rhodes, triangle: :prophet, square: :organ, sawtooth: :moog }[pad_waveform]
    end
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
      drum_presets: DRUM_PRESETS.keys,
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

  RG69_CHORDS = CHORD_VOICINGS.transform_values { |hz| { hz: } }.freeze
  RG69_DRUM_PRESETS = DRUM_PRESETS
  RG69_LOFI = LOFI_DEFAULTS
  PRODUCER_TRACKS = HARMONY_PROFILES
end

DillaProducerDNA = DillaLofiMachine
