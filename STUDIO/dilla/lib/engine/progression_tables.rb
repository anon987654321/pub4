# frozen_string_literal: true
#
# The progression catalogue and per-track presets.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Album / track progressions — verified first; rest are experimental / theory pack.
# --- extended progressions -------------------------------------------------
#
# Every one of the 218 progressions above tops out at 8 chords, and 138 of
# them are exactly 4. At chord_bars 2 a four-chord progression closes its
# circle every 8 bars, so a 32-bar render walks the same ground four times --
# which is the "loops too much, same over and over" complaint in its harmonic
# form rather than its arrangement form.
#
# These are 12 and 16 chords, so the cycle is 24-32 bars: the harmony resolves
# once across the whole beat instead of four times. Longer is not automatically
# better -- a long progression that merely wanders is worse than a short one
# that closes -- so each of these is built on a specific device that gives it
# direction over that distance:
#
#   a descending bass line, which carries a listener through changes that
#   would otherwise feel arbitrary (the reason ii-V chains and chromatic
#   descents show up in so much neo-soul);
#
#   or a delayed return to the tonic, where the first arrival is deliberately
#   weak and the real cadence is saved for the end.
#
# F# minor is over-represented because the reference set is: five of the nine
# local tracks in the Radio Bergen dossiers sit there, so the keys the pads
# reach for should too.
# Progressions organised by harmonic DEVICE rather than by mood.
#
# The device is the reusable part: once "backdoor" or "chromatic mediant" is in
# the vocabulary it applies in any key, and the engine already transposes. The
# existing tables are largely named for feel (warm_minor_vamp, neo_soul_pocket),
# which makes them hard to reach for deliberately when a specific harmonic move
# is wanted.
#
# Written mostly in C, F and Eb for readability; the key is arbitrary.
#
# Every symbol here was checked against chord_from_symbol before landing --
# the first draft had 21 that did not parse, because plain major is the EMPTY
# suffix in CHORD_SUFFIXES, not "maj", so CmajoverG is invalid and CoverG is
# right. test_device_progressions_all_resolve keeps that true.
DEVICE_PROGRESSIONS = {
  # Modal interchange / borrowed from the parallel minor
  borrowed_bVI_lift: %w[Cmaj9 Abmaj9 Fm9 Gsus4],
  borrowed_bVII_fall: %w[Cmaj9 Bbmaj9 Fm9 Cmaj9],
  borrowed_iv_ache: %w[Fmaj9 Fm9 Cmaj9 Am9],
  borrowed_bIII_step: %w[Cmaj9 Ebmaj9 Fmaj9 Gsus4],
  borrowed_bII_shadow: %w[Cm9 Dbmaj9 Cm9 Gm7],
  minor_plagal_rest: %w[Cmaj9 Fm6 Cmaj9 Cmaj9],
  parallel_minor_swap: %w[Ebmaj9 Ebm9 Abmaj9 Bbsus4],
  aeolian_borrow_turn: %w[Am9 Fmaj9 Cmaj9 Gsus4],
  dorian_borrow_bright: %w[Dm9 G13 Dm9 Bbmaj9],
  phrygian_borrow_step: %w[Em9 Fmaj9 Em9 Am9],
  mixo_borrow_seven: %w[Gmaj9 F13 Gmaj9 Dm9],
  lydian_borrow_two: %w[Fmaj9#11 Gmaj9 Fmaj9#11 Cmaj9],
  borrowed_dim_passing: %w[Cmaj9 C#dim7 Dm9 G13],
  minor_four_major_four: %w[Gmaj9 Cmaj9 Cm9 Gmaj9],
  bVII_bVI_bVII: %w[Am9 Gmaj9 Fmaj9 Gmaj9],
  picardy_release: %w[Cm9 Fm9 Gsus4 Cmaj9],
  borrowed_nine_sus: %w[Fmaj9 Bb9sus4 Fmaj9 Dm9],
  modal_mixture_pair: %w[Dmaj9 Dm9 Gmaj9 Gm9],
  ionian_to_dorian: %w[Cmaj9 Cm9 Fmaj9 Bb13],
  borrowed_augmented_lift: %w[Cmaj9 Caug Fmaj9 Fm6],

  # Chromatic mediants
  chromatic_mediant_up: %w[Cmaj9 Emaj9 Cmaj9 Abmaj9],
  chromatic_mediant_down: %w[Cmaj9 Abmaj9 Emaj9 Cmaj9],
  mediant_minor_pair: %w[Am9 Fm9 Am9 Dbmaj9],
  hexatonic_pole: %w[Cmaj9 Abm9 Cmaj9 Emaj9],
  mediant_ladder_up: %w[Fmaj9 Amaj9 Dbmaj9 Fmaj9],
  mediant_ladder_down: %w[Fmaj9 Dbmaj9 Amaj9 Fmaj9],
  third_relation_soul: %w[Ebmaj9 Gmaj9 Bmaj9 Ebmaj9],
  mediant_slash_drift: %w[Cmaj9 Emaj7overB Abmaj9 Cmaj9],
  minor_mediant_wash: %w[Dm9 Fm9 Abmaj9 Dm9],
  double_mediant_arc: %w[Amaj9 Fmaj9 Dbmaj9 Amaj9],
  mediant_with_pedal: %w[Cmaj9 AboverC Emaj9 Cmaj9],
  chromatic_third_cycle: %w[Bbmaj9 Dmaj9 Gbmaj9 Bbmaj9],
  mediant_dominant_mix: %w[Cmaj9 Ab13 Emaj9 G13],
  flat_six_major_turn: %w[Emaj9 Cmaj9 Amaj9 Emaj9],
  sharp_five_mediant: %w[Cmaj9 G#maj9 Cmaj9 Fmaj9],

  # Backdoor and tritone substitution
  backdoor_classic: %w[Cmaj9 Fm9 Bb13 Cmaj9],
  backdoor_extended: %w[Fmaj9 Bbm9 Eb13 Fmaj9],
  tritone_sub_turn_alt: %w[Dm9 Db13 Cmaj9 Cmaj9],
  tritone_two_five: %w[Am9 Ab13 Gmaj9 Gmaj9],
  sub_five_chain: %w[Cmaj9 B13 Bb13 A13],
  backdoor_minor: %w[Cm9 Fm9 Bb13 Cm9],
  tritone_pedal_pull: %w[Fmaj9 Gb13 Fmaj9 Dm9],
  double_backdoor: %w[Ebmaj9 Abm9 Db13 Ebmaj9],
  altered_dominant_turn: %w[Dm9 G7alt Cmaj9 Am9],
  alt_to_tonic_minor: %w[Dm7b5 G7alt Cm9 Cm9],
  sub_dominant_slide: %w[Cmaj9 Db13 Dm9 Db13],
  backdoor_with_nine: %w[Gmaj9 Cm9 F13 Gmaj9],
  tritone_mediant_mix: %w[Cmaj9 Gb13 Ebmaj9 Cmaj9],
  alt_chain_descent: %w[E7alt Eb7alt D7alt Db7alt],
  backdoor_gospel: %w[Fmaj9 Bbm9 Eb13 Fmaj9 Dm9 Gm9 C13 Fmaj9],

  # Pedal point
  tonic_pedal_wash: %w[Cmaj9 FoverC G13overC Cmaj9],
  dominant_pedal_hold: %w[CoverG Dm9overG G13 CoverG],
  bass_pedal_minor: %w[Am9 DmoverA Em9overA Am9],
  pedal_chromatic_top: %w[Cmaj9 C#dim7overC Dm9overC Cmaj9],
  fifth_pedal_soul: %w[Fmaj9overC Gm9overC Ab13overC Fmaj9overC],
  pedal_quartal_drift: %w[Dm11 Em11overD Fmaj9overD Dm11],
  low_pedal_ache: %w[Cm9 AboverC Fm9overC Cm9],
  pedal_lift_release: %w[Ebmaj9 AboverEb Bb13overEb Ebmaj9],
  inverted_pedal_high: %w[Cmaj9 Fmaj9 Gsus4 Cmaj9],
  organ_pedal_church: %w[GoverD Cmaj9overD D13 GoverD],
  pedal_two_chord: %w[Fm9 EboverF Fm9 EboverF],
  pedal_with_alt: %w[Cm9 G7altoverC Cm9 Fm9],
  tonic_pedal_mediant: %w[Amaj9 FoverA Dbmaj9overA Amaj9],
  pedal_sus_bloom: %w[Dsus4 Dmaj9 Dsus4 Dm9],
  bass_hold_upper_move: %w[Bbmaj9 EboverBb Fm9overBb Bbmaj9],

  # Dorian vamps (Dilla's home mode)
  dorian_two_chord_lift: %w[Fm9 Bb13],
  dorian_four_bar: %w[Dm9 G13 Dm9 G13],
  dorian_sixth_shine: %w[Cm9 Am7b5 Cm9 F13],
  dorian_quartal_vamp: %w[Gm11 C13 Gm11 C13],
  dorian_add_nine: %w[Em9 Aadd9 Em9 Aadd9],
  dorian_slash_walk: %w[Am9 DoverA Am9 Gmaj9],
  dorian_ostinato: %w[Bbm9 Eb13 Bbm9 Eb13],
  dorian_pedal_hold: %w[Fm11 Bb13overF Fm11 Bb13overF],
  dorian_with_maj_four: %w[Dm9 Gmaj9 Dm9 Bbmaj9],
  dorian_chromatic_step: %w[Cm9 C#dim7 Dm9 G13],
  dorian_thirteen_bloom: %w[Gm9 C13 Gm9 F13],
  dorian_minor_six: %w[Am9 Am6 Dm9 Am9],
  dorian_open_fourths: %w[Dm11 Em11 Dm11 Cmaj9],
  dorian_upper_triad: %w[Fm9 Abmaj9overF Fm9 Bb13],
  dorian_soul_turn: %w[Cm9 F13 Bbmaj9 Ebmaj9],

  # Constant structure / planing
  planing_maj9_whole: %w[Cmaj9 Dmaj9 Ebmaj9 Fmaj9],
  planing_m9_chromatic: %w[Cm9 Dbm9 Dm9 Ebm9],
  planing_quartal_up: %w[Dm11 Em11 Fm11 Gm11],
  planing_thirteen: %w[C13 D13 Eb13 F13],
  constant_structure_thirds: %w[Cmaj9 Ebmaj9 Gbmaj9 Amaj9],
  planing_sus_field: %w[Csus4 Dsus4 Fsus4 Gsus4],
  planing_down_step: %w[Gmaj9 Fmaj9 Ebmaj9 Dbmaj9],
  planing_add_nine: %w[Cadd9 Dadd9 Fadd9 Gadd9],
  parallel_six_nine: %w[C69 D69 F69 G69],
  planing_minor_eleven: %w[Am11 Bm11 Dm11 Em11],
  whole_tone_planing: %w[Cmaj9 Dmaj9 Emaj9 Gbmaj9],
  planing_alt_dominants: %w[C7alt D7alt F7alt G7alt],

  # Line cliches and voice-led descents
  minor_line_cliche_nine: %w[Cm9 Cmmaj7 Cm7 Cm6],
  major_line_cliche: %w[Cmaj7 Cmaj9 C69 Cmaj7],
  descending_bass_soul_slash: %w[Cmaj9 CoverB Am9 CoverG],
  chromatic_inner_fall: %w[Fmaj9 Fmaj7#5 F13 Fmaj9],
  walking_down_fourth: %w[Cmaj9 Bm9 Am9 Gmaj9],
  half_step_voice_lead: %w[Dm9 Dbmaj9 Cmaj9 Bmaj9],
  suspended_resolution_chain: %w[Csus4 Cmaj9 Fsus4 Fmaj9],
  inner_voice_rise: %w[Am9 Ammaj7 Am7 Am6],
  bass_descent_octave: %w[Cmaj9 CoverB CoverA CoverG],
  contrary_motion_pair: %w[Cmaj9 Em9 Gmaj9 Bm9],
  chromatic_upper_climb: %w[Fmaj9 Fmaj9#11 F13 Fmaj13],
  stepwise_minor_arc: %w[Am9 Bm9 Cmaj9 Dm9],

  # Deceptive and unexpected resolutions
  deceptive_to_bVI: %w[Dm9 G13 Abmaj9 Cmaj9],
  deceptive_minor_six: %w[Gm9 C13 Abmaj9 Fmaj9],
  interrupted_cadence: %w[Fmaj9 Bb13 Gm9 Fmaj9],
  false_relation_turn: %w[Cmaj9 Cm9 Abmaj9 Cmaj9],
  evaded_resolution: %w[Dm9 G13 Em9 Am9],
  surprise_major_third: %w[Am9 D13 F#maj9 Am9],
  unresolved_hang: %w[Cmaj9 D13 Fmaj9 D13],
  deceptive_chain_long: %w[Cmaj9 A13 Dm9 B13 Em9 C13 Fmaj9 G13],
  sidestep_resolution: %w[Fm9 Bb13 Bmaj9 Ebmaj9],
  dominant_to_dominant: %w[G13 C13 F13 Bb13],
  minor_deceptive_lift: %w[Cm9 G7alt Abmaj9 Cm9],
  wrong_key_landing: %w[Dm9 G13 Dbmaj9 Cmaj9],

  # Quartal and sus fields
  quartal_stack_open: %w[Dm11 Gm11 Cm11 Fm11],
  sus_field_drift: %w[C9sus4 F9sus4 Bb9sus4 Eb9sus4],
  quartal_pedal_bed: %w[Am11 Dm11 Am11 Em11],
  sus_to_maj_bloom: %w[Gsus4 Gmaj9 Csus4 Cmaj9],
  fourths_ladder: %w[Cm11 Fm11 Bbm11 Ebm11],
  quartal_mediant_shift: %w[Dm11 Fm11 Abm11 Dm11],
  sus_nine_hover: %w[F9sus Bb9sus F9sus Eb9sus],
  open_fifth_field: %w[Csus2 Fsus2 Gsus2 Csus2],
  quartal_over_pedal: %w[Dm11overG Em11overG Dm11overG Cmaj9overG],
  mccoy_fourths: %w[Fm11 Bbm11 Fm11 Cm11],
  sus_chromatic_pair: %w[Dbsus4 Dsus4 Dbsus4 Csus4],
  quartal_upper_structure: %w[Cm11 Ebmaj9overC Cm11 Fm11],

  # Gospel and church devices
  gospel_walk_up_ninths: %w[Fmaj9 Gm9 Am9 Bbmaj9],
  gospel_two_five_chain: %w[Am9 D13 Gm9 C13 Fmaj9 Fmaj9],
  church_plagal_amen: %w[Fmaj9 Bbmaj9 Fmaj9 Fmaj9],
  gospel_bVII_lift: %w[Cmaj9 Bbmaj9 Cmaj9 Fmaj9],
  gospel_dim_passing: %w[Fmaj9 F#dim7 Gm9 C13],
  shout_turnaround: %w[Ebmaj9 Cm9 Fm9 Bb13],
  gospel_slash_climb: %w[FoverA Bbmaj9 FoverC Fmaj9],
  hymn_suspension: %w[Cmaj9 Csus4 Cmaj9 Fmaj9],
  gospel_minor_walk: %w[Cm9 Dm7b5 Ebmaj9 Fm9],
  praise_break_cycle: %w[Abmaj9 Bbmaj9 Cm9 Abmaj9],
  gospel_six_two_five_dorian: %w[Am9 D13 Dm9 G13],
  amen_extended: %w[Bbmaj9 Ebmaj9 Bbmaj9 Fm9 Bb13 Ebmaj9],
}.freeze

EXTENDED_PROGRESSIONS = {
  # Stepwise descent from the tonic, twice, resolving the second time. The
  # first pass lands on the relative major and keeps moving; only the second
  # takes the C#7alt back home.
  fsharp_minor_sixteen: %w[
    F#m9 C#m9 Dmaj9 Amaj9 Bm9 F#m9 G#m7 C#7alt
    F#m9 Emaj9 Dmaj9 C#7alt Bm9 E7 Amaj9 C#7alt
  ],
  # The same key treated modally rather than functionally: no leading tone
  # until the very end, so it floats and then finally commits.
  fsharp_dorian_twelve: %w[
    F#m9 G#m7 Amaj9 Bm9 F#m9 Emaj9
    Dmaj9 C#m9 Bm11 Emaj9 Amaj9 C#7alt
  ],
  # Descending chromatic bass under sustained upper voices -- the device
  # behind most of what reads as "lush" in this idiom. Root moves
  # D-C#-C-B-Bb-A across the first half.
  chromatic_descent_sixteen: %w[
    Dm9 C#7alt Cmaj9 Bm9 Bbmaj9 Am9 Abdim Gm9
    Cmaj9 Fmaj9 Bbmaj9 Em9 A7alt Dm9 Gm9 A7alt
  ],
  # Gospel plagal motion: the IV is the centre of gravity, not the V. Slow,
  # warm and unhurried -- the closest thing here to a hymn.
  gospel_plagal_sixteen: %w[
    Ebmaj9 Abmaj9 Ebmaj9 Cm9 Fm9 Bb7 Ebmaj9 Abmaj9
    Gm7 Cm9 Fm9 Bb7 Ebmaj9 Dbmaj9 Abmaj9 Ebmaj9
  ],
  # Root movement by thirds rather than fifths, so each change is a
  # chromatic mediant sharing two tones with the last. Distant keys arrive
  # without a modulation ever announcing itself.
  mediant_wander_twelve: %w[
    Cmaj9 Em9 Abmaj9 Cm9 Ebmaj9 Gm9
    Bmaj9 D#m9 F#maj9 Bbm9 Dbmaj9 G7alt
  ],
  # Reggae-leaning: minor tonic with the flat-seventh and flat-sixth doing
  # the work, no dominant at all until the last bar. Slow changes, wide
  # spacing, nothing hurried.
  roots_minor_twelve: %w[
    Am9 G6 Fmaj9 G6 Am9 Em9
    Fmaj9 Cmaj9 Dm9 G6 Am9 E7alt
  ],
  # Two ii-V chains a whole step apart, then a long walk home. The harmonic
  # rhythm is deliberately even so the melody can be the irregular element.
  two_key_ii_v_sixteen: %w[
    Dm9 G7 Cmaj9 Cmaj9 Em9 A7 Dmaj9 Dmaj9
    Bm9 E7 Amaj9 F#m9 Bm9 E7alt Amaj9 A7alt
  ],
  # Suspended and quartal throughout: no third in most of these, so the mode
  # stays ambiguous and the pads read as texture rather than as function.
  quartal_suspension_twelve: %w[
    Dsus4 Gsus4 Csus4 Fmaj9 Bbsus4 Ebmaj9
    Absus4 Dbmaj9 Gbmaj9 Bsus4 Emaj9 Asus4
  ],
}.freeze

CHORD_PROGRESSIONS = {
  # Transcribed from a D'Angelo reference track via learn_source!'s chroma
  # analysis (progression_symbols in project/learnings/last_learn.json):
  # Fmaj9 Dm11 Gm11 Am11 Gsus4 C7#11 Dm9 Gm9. The extended/sus voicings
  # (m11, sus4, 7#11) aren't in PAD_CHORD_LOOKUP's registered set, so this
  # substitutes the nearest registered chord in the same root+quality
  # family (m11->m9, sus4->m7, 7#11->7#9) rather than silently dropping
  # unmatched entries, which is what CHORD_PROGRESSIONS.compact does.
  transcribed_soul_nine: ["Fmaj9", "Dm9", "Gm9", "Am9", "Gm7", "C7#9 Hendrix", "Dm9", "Gm9"],
  # --- Artist-verified (see ARTIST_VERIFIED_PROGRESSIONS) ---
  db_major_minor_fall: %w[Dbmaj7 Cm7 Fm7 Bbm7],
  maj7_minor_cycle: %w[Dbmaj9 Cm9 Fm9 Bbm9],
  eb_minor_two_chord: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
  pedal_e_descent: %w[D/E Db/E C/E Bm/E Bbm/E Am/E],
  syncopated_slash_ninth: %w[E9sus4/D Db/E C/E Bm/E Bbm/E Am/E E9sus4],
  e_major_third_rise: %w[Emaj7 G#m7 C#m7 E7climax],
  major7_relative_minor_turn: %w[Emaj7 G#m7 C#m7 E7climax],
  d_add9_soul_arc: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
  sus_add9_ballad: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
  alternating_minor7_pair: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
  # Two minor sevenths a semitone apart, held. Jamal 1955; Miles 1959; Coltrane
  # 1961. Both are exempt from the modal fit test — see the note on
  # ModalFamily.widen — because a deliberate two-centre vamp fails a diatonic
  # test by construction, and that vamp is the reason these records matter.
  minor_half_step_pair: %w[Dm7 Ebm7],
  dorian_two_chord_modal: %w[Dm7 Dm7 Ebm7 Dm7],
  # --- Experimental / theory (blocked when ARTIST_VERIFIED_ONLY=1) ---
  soul: %w[Fm9 Bbm9 Ebmaj9 Dbmaj9],
  # Smoother minor turn — same key as timeless, less harsh dominant clutter.
  chromatic_minor_descent: %w[Fm9 Dbmaj9 Cm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9 Bb7sus],
  borrowed_dominant_turn: %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low],
  # Fm soul arc — i→iv→bVII→bIII→bVI→v→IVsus→i (voice-led, resolves home).
  voice_led_minor_arc: %w[Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9 Cm9 Bb7sus Fm9],
  # Measured Donuts / timeless engine loop — i–IV–iii–vi–ii–V–bVI–IV.
  timeless_authentic: %w[Fm9 Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9],
  players_measured: %w[Dm7 Eb7 Gm7 D7 Eb7 Gm7 Am7],
  # F minor, eight bars, one chord each — written for a slow vocal rather than
  # for a loop. players_measured next door is seven chords with Eb7 and Gm7 each
  # appearing twice and no cadence, so it circles; under a rapper it never
  # arrives anywhere and the verse has nothing to land on.
  #
  # This one is an arc. bVI carries #11 instead of a plain major 7 so the lift at
  # bar 2 opens without brightening — the raised fourth is the only altered tone
  # and it keeps the mode ambiguous between F minor and Db lydian. Bar 4's Eb7sus
  # is the backdoor left hanging: the third is withheld, so bar 5's Abmaj9 reads
  # as arrival rather than as another passing chord. Then it darkens fast —
  # Gm7b5 is the half-diminished ii, C7b9 the real dominant — and resolves home.
  # A singer gets one bright bar (5) and one point of maximum tension (7); those
  # are the two places a line wants to break.
  #
  # Every symbol is in CHORD_SUFFIXES (m9 mmaj7 maj13#11 m11 maj13 m7b5 7alt). No
  # slash chords: SUFFIX_MATCHERS is /\A[A-G][#b]?SUFFIX\z/ and would not match.
  #
  # Two things carry it, and neither is the chord spelling.
  #
  # The bass walks down by step and stays there: F F Db C Bb Ab G, then the leap
  # to C. An earlier draft of this ran F Db Bb Eb Ab G C, which is the same
  # harmony and much worse to hear -- the ear tracks the lowest voice, and a bass
  # that leaps every bar reads as eight separate chords instead of one motion.
  #
  # Bars 1-2 are a line cliche on a stationary root: Fm9 to Fmmaj7 raises the
  # seventh Eb to E natural while everything else holds, so the tension is an
  # inner voice moving, not a chord change. It buys two bars of harmonic stillness
  # for a verse to open over, which a progression that changes root every bar
  # cannot give.
  #
  # The cadence is 7alt rather than 7b9. Both are dominants; the altered chord
  # keeps b9 and adds #9 and b13, so it lands as colour rather than as a
  # functional pull, and the loop turns over instead of resolving shut. Dilla
  # suspends far more often than he cadences.
  lydian_lift_backdoor_turn: %w[Fm9 Fmmaj7 Dbmaj13#11 Cm11 Bbm9 Abmaj13 Gm7b5 C7alt],
  # Hooktheory Donuts "Time" — Ab major IV–iii–vi–ii–V with turnaround.
  fourth_third_sixth_second_turn: %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Bbm9 Ebmaj9],
  # Full Donuts minor cycle — borrowed dominants + slash colors.
  minor_dominant_slash_cycle: %w[Fm9 Bbm9 Eb7 Abmaj9low Dbmaj9 Fm/C C7b9 Bb7sus],
  # Prior engine map (kept for A/B).
  minor_ninth_cycle: %w[Fm9 Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9],
  # Librosa chroma on sub-heavy full mix — bass harmonic field, not stem truth.
  measured_chroma_field: %w[Dbmaj9 C#m7 G#m7 D#m7 Fm9 Bbm9 Abmaj9low],
  measured_dominant_field: %w[Dm7 Eb7 Gm7 D7 Eb7 Gm7 Am7],
  jazz: %w[Dm9 Gm9 C7b9 Fmaj9],
  # Circle-of-fifths sequence with seventh/ninth extensions: Bach-informed
  # functional motion, voiced through the same drifting analog pad engine.
  baroque: %w[Am9 Dm9 G7 Cmaj9 Fmaj9 Bm7b5 E7b9 Am9],
  # Chromatic-mediant field — thirds motion, voice-led back to Fm home.
  chromatic_mediant: %w[Dm9 Fm9 AbMaj13s11 Bbm9 Ebmaj9 Cm9 Dbmaj9 Fm9],
  neo_soul: %w[Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9 Cm9 C7b9 Fm9],

  # Written in the keys of the three sampled loops, so the generated harmony
  # sits where the sample already is and HARMONIC_KEEP has little or nothing to
  # transpose. A progression a semitone from its bed is the one thing no amount
  # of mixing repairs.
  #
  # These lean on m7b5, 7b9, 11ths and 13ths deliberately: those qualities were
  # collapsing to plain m7 and dominant 7 until the voicer was fixed, so
  # progressions written before then had to avoid the vocabulary that makes
  # neo-soul sound like neo-soul.

  # C minor -- kembara_rindu (fit 0.71).
  cm_rhodes_cycle: %w[Cm9 Fm9 Bbmaj9 Ebmaj9],
  cm_chromatic_fall: %w[Cm9 Bbm9 Abmaj9 G7b9],
  cm_halfdim_turn: %w[Cm9 Dm7b5 G7b9 Cm9],
  # Two chords for the whole cycle: the hypnosis approach, where the interest
  # has to come from the drums and the sample rather than from movement.
  cm_two_chord: %w[Cm9 Fm11],

  # G minor -- semua_untuk_mu (fit 0.836, the cleanest key reading of the three).
  gm_pedal_rise: %w[Gm9 Cm9 Ebmaj9 F13],
  gm_halfdim_turn: %w[Gm9 Am7b5 D7b9 Gm9],
  gm_modal_wash: %w[Gm11 Fmaj9 Ebmaj13 Dm9],

  # D major -- dmaj_open (fit 0.697). Major rather than minor on purpose: every
  # other progression here is minor, and the sample is not.
  dmaj_glide: %w[Dmaj9 Bm9 Em11 A13],
  dmaj_mediant: %w[Dmaj9 F#m9 Bm9 Gmaj13],
  tritone: %w[Cm9 Gbmaj9 Bbm9 Fm9],
  # (syncopated_slash_ninth / e_major_third_rise / untitled / eb_minor_two_chord: artist-verified block above)
  chromatic_planing: %w[Fm9 Bbm9 Fm9 Bbm9],
  ascending_minor_stack: %w[Am9 Dm9 Gm9 Cm9],
  minor_soul_loop: %w[Bbm9 Ebmaj9 Abmaj9 Fm9],
  suspended_minor_turn: %w[Dm9 Gm9 Cm9 Fmaj9],
  major_relative_minor_cycle: %w[Fmaj9 Em9 Am9 Dm9],
  dominant_minor_resolve: %w[Em9 Am9 Dm9 G7],
  syncopated_slash_alt: %w[E9sus4/D C/E Bbm/E Am/E Db/E Bm/E E9sus4],
  minor_cycle_descent: %w[Gm9 Cm9 Fm9 Bbm9],
  minor_stepwise_cycle: %w[Am9 Dm9 Gm9 Cm9],
  minor_major_ninth_pair: %w[Fm9 Bbm9 Ebmaj9 Abmaj9],
  minor_stepwise_ascent: %w[Dm9 Gm9 Cm9 Fmaj9],
  suspended_minor_close: %w[Cm9 Fm9 Bbm9 Ebmaj9],
  # Tritone-sub modulation after main loop.
  chromatic_mediant_drift: %w[Dm9 Cm11nc AbMaj13s11 Gm7 Eb7 A7nc Dmaj9nc DMaj7overG],
  modal_quartal_ladder: %w[Cm9 Fmaj9 Bbmaj9 Ebmaj9 Abmaj7 Dm9 Bb7sus Cm9],
  minor_two_five_chain: %w[Dm9 Gm9 C7b9 Fmaj9 Bbm9 Eb9 Abmaj9 Dm9],
  circle_fifths_descent: %w[Am9 Dm9 G7 Cmaj9 Fmaj9 Bm7b5 E7b9 Am9],
  walking_bass_descent: %w[Dm9 Dm/C Bbmaj9 A7 Dm9 Gm9 Cmaj9 Fmaj9],
  # --- Expansion pack (voice-led / modal / form variety) ---
  # Bright Lydian-leaning major cycle (common-tone + stepwise top voices).
  lydian_glass_cycle: %w[Fmaj9 Am9 Gmaj9 Em9 Fmaj9 Dm9 Cmaj9 G7],
  # Pedal C with changing upper structure (electronium-style color without root thrash).
  pedal_upper_structures: %w[Cm9 C7sus Ab/C F/C Bbmaj9/C Gm7/C Dbmaj9/C Cm9],
  # Brazilian major9 ii–V turn with soft 7b9 spice.
  bossa_major9_turn: %w[Fmaj9 Em7b5 A7b9 Dm9 Gm9 C7sus Fmaj9 D7],
  # Phrygian-flavored rise that still resolves (E minor home).
  phrygian_gold_arc: %w[Em9 Fmaj9 Gmaj9 Am9 Fmaj7 G7sus Bm7b5 Em9],
  # Two-chord luminous pad showcase (long holds).
  two_chord_luminous: %w[Dbmaj9 Fm9],
  # Mixolydian sus pocket — short chords, lead-readable.
  mixo_sus_loop: %w[Dmaj9 Cmaj9 Gmaj9 Dmaj9 F#m9 Em9 A7sus Dmaj9],
  # Chromatic-mediant family with shared E common tone (cleaner than raw planing).
  common_tone_drift: %w[Em9 Cmaj9 Am9 Fmaj9 Em9 Gmaj9 Bm9 Em9],
  # Three-tonic lite (major-third stations) — short spiral, home to Fm.
  third_cycle_triads: %w[Fm9 Abmaj9 Bmaj9 Fm9 Dbmaj9 Emaj9 Abmaj9 Fm9],
  # Quartal/open drone over D — atmosphere + lead space.
  drone_quartal_wash: %w[Dm9 G/D C/D Am9 Dm9 Fmaj9/D G/D Dm9],
  # 3/4 relative-major lift waltz (distinct from jazz_ballad_waltz).
  waltz_relative_lift: %w[Cm9 Abmaj9 Bb7 Ebmaj9 Fm9 Bb7 Ebmaj9 G7],
  # Slow plagal gospel stack.
  half_time_gospel_plagal: %w[Bbmaj9 Ebmaj9 Abmaj9 F7sus Bbmaj9 Ebmaj9 F7sus Bbmaj9],
  # Double-time pocket stress-test (short cycle).
  double_time_pocket: %w[Em9 Am9 D7 Gmaj9 Em9 Am9 D7 Gmaj9],
  # Whole-tone bridge colors then settle home (Fm).
  whole_tone_bridge: %w[C7 D7 E7 F#7 Fm9 Dbmaj9 Ebmaj9 Fm9],
  # Upper-structure slash colors over Bb bass.
  upper_triad_tower: %w[Bbmaj9 D/Bb F/Bb G/Bb Bbmaj9 Eb/Bb F/Bb Bbmaj9],
  # Softest lullaby minor-add9 family.
  minor_add9_lullaby: %w[Gm9 Ebmaj9 Cm9 D7sus Gm9 Ebmaj9 Fmaj9 Gm9],
  # Dominant chain of fifths home to Ab/Db/Cm.
  dominant_chain_home: %w[C7 F7 Bb7 Eb7 Abmaj9 Dbmaj9 Cm9 F7],
  # --- Composer/producer route expansions ---
  gospel_backdoor: %w[Dbmaj9 Fm9 Gbmaj9 Cbmaj9 Dbmaj9 Abmaj9 Bbm9 Eb7],
  minor_iv_lift: %w[Dbmaj9 Fm9 Gbmaj9 B7sus Dbmaj9 Abmaj9 Gbmaj9 Dbmaj9],
  common_tone_sideways: %w[Dbmaj9 Emaj7 Bmaj9 Dbmaj9 Fm9 Abmaj9 Dbmaj9],
  detroit_suspension: %w[Fm9 Abmaj9low Dbmaj9 G7sus C7b9 Fm9 Bbm9 Eb7],
  minor_ninth_two_chord: %w[Fm9 Dbmaj9 Fm9 Dbmaj9 Fm9 Bbm9 Fm9 Dbmaj9],
  fugue_conversation_arc: %w[Fm9 Dbmaj9 Cm9 Fm9 Gbmaj9 Dbmaj9 Bbm9 Eb7],
  # --- Generic Fantastic-era soul templates (2026-07-28). Deliberately named for
  # their harmonic function, not for any song. minor_soul_loop was NOT added: it
  # duplicates :minor_major_ninth_pair note-for-note and that name is already
  # taken here by a different rotation.
  warm_minor_arc:  %w[Fm9 Dbmaj9 Abmaj9 Ebmaj9],
  iv_v_i_minor:    %w[Fm9 Bbm9 Cmaj9 Am9],
  # Slash chords with a descending bass -- exercises the :bass_hz pedal path.
  stepwise_bass:   %w[Cm9/Bb Fm7/Ab Bbm7/Gb Ebmaj9],
  modal_fourth:    %w[Fm7 Bb7 Ebmaj7 Abmaj7],
  suspended_blues: %w[Fm9 Bb7sus Ebmaj9 A7b9],
  # Static C pedal under moving upper structures.
  pedal_drone:     %w[Fm/C Bbm/C Abmaj7/C G7sus/C],
  eight_bar_soul_arc: %w[Fm9 Bbm9 Ebmaj9 Abmaj9 Dbmaj9 Cm7 Bb7sus Fm9],

  # ==========================================================================
  # Generic harmonic templates (2026-07-28). Named for the harmonic device they
  # demonstrate -- never for a song, artist or record. Each entry was checked
  # three ways before landing: every symbol resolves via resolve_pad_chord_symbol,
  # nothing duplicates an existing progression exactly or as a rotation, and no
  # chord is missing its own root/3rd/7th. That last check matters because 13,
  # m11 and 9 voicings currently drop core tones (C13 comes back with no C,
  # Cm11 with a C# where the root should be), so those qualities were
  # substituted out here rather than shipped broken.
  # ==========================================================================
  # --- minor cycles / neo-soul ---
  minor_ninth_descent:      %w[Cm9 Bbm9 Abmaj9 Gm7],
  minor_fourth_ladder:      %w[Am9 Dm9 Gm9 Cmaj9],
  minor_plagal_return:      %w[Dm9 Gm9 Dm9 Am9],
  minor_sixth_glow:         %w[Fm9 Fm6 Bbm9 Ebmaj9],
  minor_dorian_vamp:        %w[Dm9 G13 Dm9 G13],
  minor_aeolian_fall:       %w[Am9 Gmaj9 Fmaj9 Em9],
  # The second chord was Cmaj7 -- C E G B, a MAJOR third -- which is the one
  # note a minor line cliché must not contain. The device is a top voice
  # walking C-B-Bb-A over a held minor triad; with a natural third in bar 2
  # the middle of the phrase turns major and the walk stops reading as a line
  # at all. It was almost certainly spelled that way because CmMaj7 did not
  # voice: it mapped through to a shape with neither the minor third nor the
  # major seventh until the CHORD_TEMPLATES fix on 2026-07-29.
  minor_line_cliche:        %w[Cm9 CmMaj7 Cm7 Cm6],
  minor_third_lift:         %w[Fm9 Abmaj9 Bbm9 Dbmaj9],
  minor_tritone_pivot:      %w[Cm9 Gbmaj9 Fm9 Bbm9],
  minor_half_step_sigh:     %w[Bbm9 Am9 Abmaj9 Gm7],
  # --- gospel / plagal ---
  gospel_four_one:          %w[Ebmaj9 Bb7 Ebmaj9 Fm9],
  gospel_walk_up:           %w[Cmaj9 Dm9 Em9 Fmaj9],
  gospel_amen_turn:         %w[Fmaj9 Bb7 Fmaj9 Cmaj9],
  gospel_six_two_five:      %w[Am9 Dm9 G13 Cmaj9],
  gospel_flat_seven_lift:   %w[Fmaj9 Ebmaj9 Fmaj9 Bb7],
  # --- modal ---
  dorian_two_chord:         %w[Gm9 Cmaj9 Gm9 Cmaj9],
  phrygian_flat_two:        %w[Em9 Fmaj9 Em9 Fmaj9],
  lydian_bright_pair:       %w[Cmaj9 Dmaj9 Cmaj9 Gmaj9],
  mixolydian_rock:          %w[Gmaj9 Fmaj9 Cmaj9 Gmaj9],
  aeolian_stepdown:         %w[Cm9 Bb7 Abmaj9 Gm7],
  locrian_shadow:           %w[Bm7b5 Em9 Am9 Dm9],
  # --- quartal / open ---
  quartal_stack_rise:       %w[Dm9 Gm11 Cm9 Fm11],
  quartal_open_pair:        %w[Am9 Dm9 Am9 Em9],
  quartal_fourths_arc:      %w[Em9 Am9 Dm9 Gm11],
  # --- descending bass (slash) ---
  descending_bass_soul:     %w[Cmaj9 Cmaj9/B Am9 Am9/G],
  descending_bass_minor:    %w[Dm9 Dm9/C Bb7 Am9],
  descending_bass_gospel:   %w[Fmaj9 Fmaj9/E Dm9 Dm9/C],
  stepwise_fall_four:       %w[Ebmaj9 Ebmaj9/D Cm9 Cm9/Bb],
  chromatic_bass_walk:      %w[Cm9 Cm9/B Cm9/Bb Cm9/A],
  # --- pedal points ---
  pedal_tonic_shift:        %w[Cmaj9 Fmaj9/C Bbmaj9/C Cmaj9],
  pedal_dominant_hold:      %w[Gm9/G C9/G Fmaj9/G Gm9/G],
  pedal_minor_drone:        %w[Am9 Dm9/A Gmaj9/A Am9],
  pedal_fifth_wash:         %w[Fmaj9/C Ebmaj9/C Dbmaj9/C Cm9],
  # --- dominant motion / turnarounds ---
  dominant_cycle_four:      %w[E7 A7 D7 G13],
  two_five_one_major:       %w[Dm9 G13 Cmaj9 Cmaj9],
  two_five_one_minor:       %w[Dm7b5 G7b9 Cm9 Cm9],
  backdoor_resolve:         %w[Fm9 Bb7 Cmaj9 Cmaj9],
  tritone_sub_turn:         %w[Dm9 Db9 Cmaj9 Cmaj9],
  altered_dominant_push:    %w[Gm9 C7alt Fmaj9 Fmaj9],
  rhythm_changes_head:      %w[Bb7 Gm9 Cm9 F13],
  sus_dominant_float:       %w[G7 G13 Cmaj9 Cmaj9],
  # --- bossa / brazilian ---
  bossa_minor_two_five:     %w[Fm9 Bb7b9 Ebmaj9 Ebmaj9],
  bossa_major_stroll:       %w[Dmaj9 Bm9 Em9 A9],
  bossa_chromatic_down:     %w[Gmaj9 Gbmaj9 Fmaj9 Emaj9],
  # --- thirds / major_third_cycle_full-ish ---
  major_third_cycle:        %w[Cmaj9 Emaj9 Abmaj9 Cmaj9],
  minor_third_cycle:        %w[Cm9 Ebm9 Gbm9 Am9],
  chromatic_mediant_pair:   %w[Cmaj9 Abmaj9 Cmaj9 Emaj9],
  # --- borrowed / modal interchange ---
  borrowed_flat_six:        %w[Cmaj9 Abmaj9 Fm9 Cmaj9],
  borrowed_minor_four:      %w[Fmaj9 Fm9 Cmaj9 Cmaj9],
  neapolitan_lean:          %w[Cm9 Dbmaj9 G7b9 Cm9],
  # --- two-chord vamps ---
  two_chord_minor_vamp:     %w[Fm9 Bbm9],
  two_chord_major_vamp:     %w[Cmaj9 Fmaj9],
  two_chord_sus_vamp:       %w[Am9 D7],
  two_chord_mediant_vamp:   %w[Ebmaj9 Gm9],
  # --- blues ---
  minor_blues_head:         %w[Cm9 Fm9 Cm9 G7b9],
  jazz_blues_turn:          %w[F13 Bb9 F13 C9],
  slow_blues_soul:          %w[Bb9 Eb7 Bb9 F13],
  # --- ballad / waltz ---
  ballad_major_arc:         %w[Fmaj9 Dm9 Gm9 C9],
  ballad_minor_arc:         %w[Cm9 Abmaj9 Fm9 G7b9],
  waltz_minor_turn:         %w[Am9 Dm9 E7b9 Am9],
  # --- ambient / wash ---
  ambient_major_drift:      %w[Dmaj9 Amaj9 Emaj9 Bmaj9],
  ambient_minor_drift:      %w[Em9 Bm9 Gmaj9 Dmaj9],
  suspended_air:            %w[C7 F7 Bb7sus Eb7],
  # --- longer arcs (8) ---
  eight_bar_minor_journey:  %w[Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9 Dm7b5 G7b9 Cm9],
  eight_bar_major_journey:  %w[Fmaj9 Bb7 Em7b5 A7b9 Dm9 Gm9 C9 Fmaj9],
  eight_bar_modal_drift:    %w[Dm9 Em9 Fmaj9 Gm9 Am9 Bb7 Cmaj9 Dm9],
  eight_bar_gospel_climb:   %w[Bb7 Cm9 Dm9 Ebmaj9 F13 Gm9 Cm9 Bb7],
  eight_bar_pedal_arc:      %w[Am9 Dm9/A Fmaj9/A Em9/A Am9 Gmaj9/A Fmaj9/A Am9],
  eight_bar_descending:     %w[Cmaj9 Cmaj9/B Am9 Am9/G Fmaj9 Fmaj9/E Dm9 G13],
  # --- cadential devices ---
  andalusian_fall:          %w[Am9 Gmaj9 Fmaj9 E7b9],
  deceptive_cadence:        %w[Dm9 G13 Am9 Fmaj9],
  picardy_lift:             %w[Am9 Dm9 E7b9 Amaj9],
  half_cadence_hold:        %w[Cmaj9 Am9 Dm9 G7],
  plagal_soft_close:        %w[Cmaj9 Fm9 Cmaj9 Cmaj9],
  # --- secondary dominants ---
  secondary_five_of_two:    %w[Cmaj9 A7b9 Dm9 G13],
  secondary_five_of_four:   %w[Cmaj9 C7 Fmaj9 Fm9],
  secondary_five_of_six:    %w[Cmaj9 E7b9 Am9 Dm9],
  secondary_chain_down:     %w[E7 A7 D7 G7],
  # --- half-diminished chains ---
  half_dim_descent:         %w[Dm7b5 Cm7b5 Bm7b5 Bbm7b5],
  half_dim_to_minor:        %w[Bm7b5 E7b9 Am9 Am9],
  half_dim_pair:            %w[Em7b5 A7alt Dm9 Gm9],
  # --- planing / parallel ---
  parallel_major_planing:   %w[Cmaj9 Dmaj9 Ebmaj9 Fmaj9],
  parallel_minor_planing:   %w[Cm9 Dm9 Ebm9 Fm9],
  parallel_sus_planing:     %w[C7 D7 Eb7 F7],
  whole_tone_climb:         %w[C9 D9 E9 Gb9],
  # --- upper structure triads over pedal ---
  upper_structure_c:        %w[Cmaj9 Dmaj9/C Ebmaj9/C Fmaj9/C],
  upper_structure_f:        %w[Fmaj9 Gmaj9/F Abmaj9/F Bbmaj9/F],
  upper_structure_minor:    %w[Am9 Bbmaj9/A Cmaj9/A Dm9/A],
  # --- contrary / inner motion ---
  inner_voice_climb:        %w[Cm9 Cm9 Cmaj9 C9],
  inner_voice_fall:         %w[Fmaj9 Fmaj7 F6 Fm6],
  static_top_reharm:        %w[Cmaj9 Am9 Fmaj9 Dm9],
  # --- montuno / latin ---
  montuno_major:            %w[Fmaj9 Bb7 C9 Fmaj9],
  # --- disco / house four ---
  four_on_floor_minor:      %w[Am9 Fmaj9 Cmaj9 Gmaj9],
  four_on_floor_major:      %w[Cmaj9 Gmaj9 Am9 Fmaj9],
  disco_minor_lift:         %w[Dm9 Gm9 Bb7 Cmaj9],
  house_sus_pump:           %w[Am9 D7 Gmaj9 Cmaj9],
  # --- afrobeat / one-chord ---
  one_chord_dorian:         %w[Gm9 Gm11],
  one_chord_mixolydian:     %w[C9 C9],
  afro_two_chord:           %w[Em9 Am9],
  # --- riff / ostinato ---
  ostinato_minor_pair:      %w[Cm9 Abmaj9],
  ostinato_fourth_pair:     %w[Dm9 Gm9],
  ostinato_tritone_pair:    %w[Fm9 Bmaj9],
  # --- extended jazz arcs ---
  circle_of_fifths_full:    %w[Cmaj9 Fmaj9 Bm7b5 E7b9 Am9 Dm9 G13 Cmaj9],
  turnaround_chromatic:     %w[Cmaj9 Eb7 Dm9 Db7],
  third_cycle_arc:      %w[Cmaj9 Eb7 Abmaj9 B7 Emaj9 G7 Cmaj9 Cmaj9],
  minor_line_descent_long:  %w[Am9 Am9/G Fmaj9 Fmaj9/E Dm9 Dm9/C Bm7b5 E7b9],
  # --- soul / rnb specifics ---
  rnb_minor_seven_walk:     %w[Dm7 Em7 Fmaj7 Gm7],
  rnb_sus_resolve:          %w[Gm9 C7 Fmaj9 Fmaj9],
  quiet_storm_arc:          %w[Ebmaj9 Cm9 Fm9 Bb9],
  slow_jam_minor:           %w[Bbm9 Ebm9 Abmaj9 Dbmaj9],
  slow_jam_major:           %w[Abmaj9 Dbmaj9 Ebmaj9 Abmaj9],
  # --- boom bap / sample flavoured ---
  boom_bap_minor_loop:      %w[Gm9 Cm9 Gm9 D7b9],
  boom_bap_major_loop:      %w[Ebmaj9 Abmaj9 Ebmaj9 Bb9],
  dusty_two_chord:          %w[Bbm9 Ebmaj9],
  dusty_three_chord:        %w[Fm9 Dbmaj9 Ebmaj9],
  crate_minor_turn:         %w[Cm9 Fm9 Bb9 Ebmaj9],
  # --- suspended / open colour ---
  sus_ladder_up:            %w[C7 Eb7 F7 Ab7],
  sus_minor_pair:           %w[Am9 Dm9],
  open_fifth_drift:         %w[Cmaj9 Gmaj9 Dmaj9 Amaj9],
  # --- darker / tension ---
  altered_tension_arc:      %w[Cm9 F7alt Bbm9 Eb7alt],
  diminished_passing:       %w[Cmaj9 Dm9 Ebm9 Em9],
  chromatic_dominant_fall:  %w[G13 Gb13 F13 E9],
  minor_major_shadow:       %w[Cm9 Cmaj7 Fm9 Bb9],
  # --- 8-bar extended ---
  eight_bar_rnb_arc:        %w[Ebmaj9 Cm9 Fm9 Bb9 Ebmaj9 Abmaj9 Fm9 Bb9],
  eight_bar_dorian_ride:    %w[Gm9 C9 Gm9 C9 Ebmaj9 Fmaj9 Gm9 Gm9],
  eight_bar_soul_climb:     %w[Fm9 Gm7b5 Abmaj9 Bbm9 Cm9 Dbmaj9 Eb7 Fm9],
  eight_bar_cycle_home:     %w[Am9 D7b9 Gm9 C9 Fmaj9 Bm7b5 E7b9 Am9],
  eight_bar_pedal_dark:     %w[Cm9 Dbmaj9/C Ebmaj9/C Fm9/C Cm9 Abmaj9/C Bbmaj9/C Cm9],
  eight_bar_bright_arc:     %w[Dmaj9 Bm9 Gmaj9 Amaj9 Dmaj9 Em9 Amaj9 Dmaj9],
  # Root motion transcribed from a 92 BPM Ableton set: an Operator bassline
  # walking C - Eb - F - G, i-bIII-iv-V in C minor, with an E natural passing
  # through bar 1 as the blues third. The E is a bass inflection, not a chord
  # tone, so it is not voiced here.
  minor_blues_step_up: %w[Cm9 Ebmaj9 Fm9 G7b9],

  # --- Written against the corrected voicer (2026-07-29) ---
  #
  # A census of this table found 72% of every chord symbol in it was some
  # kind of 9th: 743 ninths against 19 thirteenths, 5 elevenths and 6 triads.
  # That is why so much of the catalogue sounds like one harmonic colour --
  # not too few entries, too few qualities across them.
  #
  # Two things had to be true before writing more. First, m7b5, mMaj7, m6 and
  # 7#5 had to actually voice as themselves; until today m7b5 built a plain
  # minor 7, so every half-diminished ii below would have been a lie. Second,
  # the qualities had to survive the whole path, which is why none of these
  # lean on 7b9 or on the 9th of an m9 -- both still lose a note to the
  # four-voice cap, and a progression should not be written against a chord
  # the engine cannot yet play.
  #
  # These are built, not transcribed. No claim is made that any record plays
  # them.

  # The minor ii-V that the half-diminished fix makes possible at all: the ii
  # is genuinely half-diminished and the V genuinely has a raised fifth, so
  # the pull to Cm is in the chords rather than in the bass alone.
  minor_two_five_true: %w[Dm7b5 G7#5 Cm9 Cm6],

  # Chromatic mediants without the 9th monoculture -- 13ths and a sus give
  # each arrival a different upper structure rather than the same stacked 9.
  mediant_thirteenths: %w[Cmaj13 Abmaj13 Emaj13 Cmaj13 F7sus Bb13 Ebmaj13 Cmaj13],

  # Half-diminished used as colour rather than function: the same shape moved
  # in whole steps, so the ear hears one chord travelling instead of four.
  half_dim_planing: %w[Dm7b5 Em7b5 F#m7b5 Am7b5],

  # Quartal over a pedal, resolving to a 6 rather than a 9 -- a plainer, older
  # sound than the maj9 this table reaches for by default.
  quartal_pedal_to_six: %w[Am11 Dm11 Gm11 Cmaj13 Am11 Dm11 F7sus C6],

  # Modal interchange: the bIII and bVI are borrowed, and the #5 dominant is
  # what makes the borrow sound deliberate rather than accidental.
  borrowed_bright_to_dark: %w[Cmaj9 Ebmaj13 Abmaj9 G7#5 Cmaj9 Fm6 Cmaj9 G7alt],

  # Descending bass under a static-ish top, ending on a minor 6 so the last
  # chord is neither major nor a minor 7 -- the ambiguity is the point.
  descending_bass_minor_six: %w[Cm9 Cm9/Bb Abmaj13 G7#5 Cm9 Fm6 Dm7b5 Cm6],

  # Two chords, held long: a suspended dominant that never resolves against a
  # 13th. Written for the slow FlyLo presets (flylo_massage, flylo_flamagra)
  # where four changes in a bar would crowd the space they leave.
  sus_thirteen_hypnosis: %w[F7sus Ebmaj13],

  # ==========================================================================
  # Devices the table did not have (2026-07-30). Named for the shape the ear
  # hears rather than the textbook term -- the textbook term is in the comment,
  # which is where it belongs, because nobody choosing a progression to render
  # is thinking "I would like a chromaticised descending tetrachord ostinato".
  #
  # Three of these could not have been written before today: dim, dim7, aug and
  # maj7#5 had no template and no suffix, so every symbol using one resolved to
  # nil and was dropped on the floor. The symmetrical chords are the pivots --
  # the notes that let harmony change key without asking permission -- and the
  # table had 227 progressions and not one of them.
  # ==========================================================================

  # :andalusian_fall already holds the bare i-bVII-bVI-V descent. This is the
  # mode it implies, stated outright: the second time down, the bVI is replaced
  # by the bII, the note that makes Phrygian Phrygian, so the fall lands a
  # semitone above home instead of a whole tone. Flamenco, and half of Turkish
  # and Arab-Andalusian song, live in the gap between those two versions.
  phrygian_dominant_descent: %w[Am9 Gmaj9 Fmaj9 E7b9 Am9 Fmaj9 Bbmaj9 E7b9],
  # The same descent written as a ground bass: D-C#-C-B-Bb-A, a semitone at a
  # time under held upper voices. Purcell, Bach's Crucifixus, "Hotel
  # California", every Baroque lament -- the oldest device in this file, and the
  # reason a chromatic bass reads as grief rather than as chromaticism.
  lament_ground: %w[Dm9 Dm9/C# Dm9/C Dm9/B Bbmaj9 Gm9 A7b9 Dm9],
  # C major and Ab minor share exactly one note and no key. The "hexatonic
  # pole" -- the most distant pair triadic harmony can reach while still moving
  # every voice by a single step. It does not modulate and it does not resolve;
  # it just opens a door onto a room that should not be there.
  hexatonic_pole_shiver: %w[Cmaj9 Abm9 Cmaj9 Abm9],
  # The full ring that pole sits on: major, its parallel minor, down a major
  # third, again, again, home. Six stations, every move a single voice by a
  # semitone, and after six you are back where you started having passed
  # through three keys. A staircase that closes on itself.
  hexatonic_cycle_ring: %w[Cmaj9 Cm9 Abmaj9 Abm9 Emaj9 Em9 Cmaj9 Cm9],
  # One root, seven chords, each a shade brighter than the last: half-diminished,
  # minor, minor eleventh, suspended, dominant, major, then the raised fourth on
  # top. The modal brightness order (locrian through lydian) heard as a single
  # sunrise rather than as seven separate scales, because nothing moves but the
  # light.
  dawn_ladder: %w[Cm7b5 Cm9 Cm11 C7sus C7 Cmaj9 Cmaj7#11],
  # The diminished seventh as a stepping stone: I, the chord a semitone above
  # it that belongs to no key at all, then ii-V home. Ragtime, stride, and
  # every gospel pianist's way of getting from one chord to the next one up.
  dim_stepping_stone: %w[Cmaj9 C#dim7 Dm9 G13],
  # A sixth chord and the diminished seventh a semitone below it, traded back
  # and forth. Barry Harris taught this as one eight-note scale rather than two
  # chords, and that is what it sounds like: harmony that moves without ever
  # leaving.
  sixth_diminished_wheel: %w[C6 Bdim7 C6 Fmaj9 C6 Bdim7 Dm9 G13],
  # The augmented triad divides the octave into three equal parts, so it
  # belongs to no key and every key -- one chord that can turn the music
  # anywhere. Used here as a hinge between C major and its flat submediant.
  augmented_hinge: %w[Cmaj9 Caug Fmaj9 Fm9 Cmaj9 Abmaj9 Caug Cmaj9],
  # Lydian augmented: a major seventh with both the fourth and the fifth raised.
  # Two notes out of the key, no dominant anywhere, and it still sounds settled
  # -- the chord that made mid-century film harmony sound like weather.
  lydian_augmented_haze: %w[Cmaj9 Cmaj7#5 Fmaj7#11 Dm9 Gmaj9 Cmaj7#5 Am9 Cmaj9],
  # :third_cycle_arc cuts the octave into three. This cuts it into four --
  # minor thirds, the diminished axis -- each station reached by its own
  # dominant. Four keys in eight bars and no two of them adjacent, so the ear
  # gives up tracking the key and starts hearing the motion itself.
  four_station_orbit: %w[Cmaj9 Eb7 Ebmaj9 Gb7 Gbmaj9 A7 Amaj9 G7],
  # Half-diminished into an altered dominant that never lands. A hundred and
  # fifty years of unresolved longing rendered as four bars that loop.
  longing_unresolved: %w[Fm7b5 E7b9 Am9 Fm7b5 E7b9 Am9 Dm9 E7b9],
  # The Neapolitan (bII) walked all the way to its other use: as a flat-sixth
  # dominant, the tritone substitute, which is the same chord heard from the
  # other side. The door and the door frame.
  neapolitan_door: %w[Cm9 Dbmaj9 Abmaj9 G7alt Cm9 Fm9 Db13 Cm9],
  # A chain of fifths where every dominant is replaced by the chord a tritone
  # away, so the roots fall by semitone instead of by fifth while the voices
  # keep the same pull. The long way down that arrives at the same place.
  sub_ladder_down: %w[Dm9 Db9 Cmaj9 B9 Bbmaj9 A7alt Abmaj9 G13],
  # One shape sliding: the same major-ninth voicing walked up four steps and
  # back down, no key, no function, only parallel motion. Debussy's planing --
  # harmony used as colour rather than as grammar.
  parallel_ninth_tide: %w[Ebmaj9 Fmaj9 Gbmaj9 Abmaj9 Gbmaj9 Fmaj9 Ebmaj9 Dbmaj9],
  # Two major sevenths a fifth apart, rocking, and then the slow minor walk
  # home. Nothing in it is unusual; the tempo and the space are the whole idea.
  slow_pendulum_major: %w[Gmaj9 Dmaj9 Gmaj9 Bm9 Em9 Am9 Dmaj9 Gmaj9],
  # A tonic that never moves and upper structures that do all the travelling.
  # Water that looks still because only the surface is moving.
  still_water_pedal: %w[Cmaj9 G7sus/C Cmaj9 Dm9/C Cmaj9 Fmaj9/C Cmaj9 G7sus/C],
  # Bitonal pedal: a C minor bass with triads a tritone and a minor third above
  # it laid on top. Two keys sounding at once and neither of them winning.
  two_moons_pedal: %w[Cm9 Gbmaj9/C Cm9 Abmaj9/C Cm9 Ebmaj9/C Cm9 Gbmaj9/C],
  # A minor arc that ends on the major third of its own tonic -- the Picardy
  # third, which for two hundred years was simply how a minor piece was allowed
  # to stop. The window opening on the last bar.
  picardy_window: %w[Am9 Dm9 Fmaj9 Em9 Am9 Dm9 E7b9 Amaj9],
  # Every dominant suspended, resolving only into the next suspension, all the
  # way round the circle of fourths. Bells, not cadences.
  bell_chain_of_fifths: %w[Am9 D7sus Gmaj9 C7sus Fmaj9 Bb7sus Ebmaj9 Ab7sus],
  # bVII-IV-I twice over: the plagal cadence applied to itself, so the music
  # keeps arriving home from one step further out. No leading tone anywhere.
  double_plagal_open: %w[Bb7 Fmaj9 Cmaj9 Cmaj9 Bb7 Fmaj9 Gmaj9 Cmaj9],
  # Dorian with the window open: the minor tonic and the major fourth that only
  # Dorian has, plus the relative major leaning in. Modal, but not static.
  dorian_open_window: %w[Dm9 G13 Cmaj9 Am9 Dm9 Em9 G13 Dm9],
}.merge(EXTENDED_PROGRESSIONS).merge(DEVICE_PROGRESSIONS).freeze

# Per-track production presets (BPM from jdillabasslines Vol. 2).
TRACK_PRESETS = {
  # Recreation of a 92 BPM Ableton Live 9.7 set (4_seven), transcribed from the
  # .als rather than approximated by ear. What the set actually contains:
  #   - a 4-bar frozen audio loop on an audio track (16 beats = 10.43s @92)
  #   - an Operator FM bass, 2-bar phrase, C-E-C-G / Eb / F / G
  #   - two Drum Racks: a kick oneshot and a DMX analog clap, 2-bar pattern
  #   - returns: Ambience Medium reverb, Dotted Eighth Note delay
  # The bass line is the only unambiguous harmony in the set (the sample carries
  # the rest), so the progression is its root motion: i-bIII-iv-V in C minor.
  # Straight sixteenths, not Dilla-lean: the set has no groove pool applied.
  four_seven: {
    bpm: 92, progression: :minor_blues_step_up, chord_bars: 1, phrase_bars: 8,
    # feel:, not drum_preset: -- dilla picks grids through DRUM_PATTERN_SETS,
    # which merges in DillaLofiMachine::DRUM_PRESETS, so :four_seven there is
    # reachable as a feel and carries the transcribed kick/clap grid verbatim.
    swing: 52, feel: :four_seven, voicing: :rootless,
    intro_bars: 2,
    timing: { snare: -6..2, hat_up: 2..8, bass: 4..12, kick_anchor: 0..2, pad: 0..6 },
  },
  # Two of the hand-cut loops, which had no preset and so were unreachable.
  #
  # TRACK_SAMPLE_LOOPS_BUILTIN holds four measured loops, but a loop only reaches
  # a render when a TRACK name resolves to it (sample_loop_entry looks the track
  # up in that table), and only four_seven -> kembara_rindu had a preset. So
  # semua_untuk_mu and lo_borges -- each cut, keyed and argued for by hand in the
  # note above its entry -- appeared in nothing the engine renders on its own:
  # not the medley, not the stream rotation, only a hand-typed TRACK=<slug>.
  # (rauingar is deliberately out of the rotation -- see
  # SAMPLE_LOOPS_OUT_OF_ROTATION.)
  #
  # BPMs are each loop's own measured tempo, not a choice: a bed at a different
  # tempo to the arrangement has to be stretched, and these were cut to loop.
  # Progressions sit with the material rather than against it -- semua_untuk_mu
  # is a sustained G-minor passage with no onsets at all, so it gets a two-chord
  # bed and long chords rather than a moving cycle; lo_borges reads D major and
  # is the cleanest-looping of the four, so it takes the add9 arc.
  semua_untuk_mu: {
    bpm: 96, progression: :minor_ninth_two_chord, chord_bars: 2, phrase_bars: 16,
    swing: 57, feel: :timeless, stereo_pan: true, intro_bars: 4,
    timing: { snare: -18..-6, hat_up: 12..26, bass: 16..34, kick_anchor: 0..4, pad: 2..14 },
  },
  lo_borges: {
    bpm: 114, progression: :d_add9_soul_arc, chord_bars: 1, phrase_bars: 8,
    swing: 54, feel: :loose_pocket, stereo_pan: true,
    timing: { snare: -12..-4, hat_up: 8..18, bass: 10..24, kick_anchor: 0..3, pad: -4..6 },
  },

  # The fifth hand-cut loop, added the same day as this preset, so it never had
  # the gap the two above sat in -- test_every_hand_cut_sample_loop_is_reachable_
  # as_a_track_preset failed the moment the rack entry landed without it, which
  # is the check working exactly as its comment says it should.
  #
  # 84 is the loop's own measured tempo, not a choice, for the reason given
  # above. The progression and feel are taken from the existing preset nearest
  # that tempo -- sheger_04 at 82, :neo_soul and :timeless -- by the same rule
  # the eight chops follow, so no new musical judgement is smuggled in with the
  # wiring. The loop reads A minor and neo_soul is a minor cycle, so they are
  # not fighting; KEY_LOCK moves both to one tonic anyway.
  arat_swost_wolet: {
    bpm: 84, progression: :neo_soul, chord_bars: 2, phrase_bars: 16,
    swing: 56, feel: :timeless, stereo_pan: true,
    timing: { snare: -16..-6, hat_up: 10..22, bass: 14..30, kick_anchor: 0..4, pad: 0..12 },
  },

  # Sheger, chopped eight ways. Same problem the loops above had and the same
  # fix: the chopper registers its output in TRACK_SAMPLE_LOOPS, but a loop only
  # renders when a TRACK resolves to it, and none of these had a track. All
  # eight sat in the rack reachable only by hand.
  #
  # Every bpm here is the chop's own measured tempo from samples/chopped/
  # loops.json, not a preference -- these were cut to loop at it. Progression
  # and feel are each taken from the existing preset nearest that tempo, so no
  # new musical judgement is smuggled in with the wiring: 122 from
  # tresillo_house, 113 from amapiano_offbeat and lo_borges, 92 from
  # pedal_e_descent, 82 from neo_soul, 74 from the mediant and neapolitan
  # generators, 93 from players. The eight land on eight different progressions
  # across eight tempos and eight key centres, which is what makes them worth
  # having in the medley rather than one bed heard eight times.
  sheger_01: { bpm: 122, progression: :double_plagal_open, chord_bars: 1, phrase_bars: 8,
               swing: 52, feel: :tresillo_house },
  sheger_02: { bpm: 113, progression: :still_water_pedal, chord_bars: 2, phrase_bars: 16,
               swing: 52, feel: :amapiano_offbeat, stereo_pan: true },
  sheger_03: { bpm: 92, progression: :pedal_e_descent, chord_bars: 1, phrase_bars: 8,
               swing: 54, feel: :syncopated_slash_ninth, stereo_pan: true },
  sheger_04: { bpm: 82, progression: :neo_soul, chord_bars: 2, phrase_bars: 16,
               swing: 58, feel: :timeless, stereo_pan: true },
  sheger_05: { bpm: 74, progression: :chromatic_mediant, chord_bars: 2, phrase_bars: 16,
               swing: 60, feel: :organic, stereo_pan: true },
  sheger_06: { bpm: 93, progression: :players_measured, chord_bars: 2, phrase_bars: 16,
               swing: 58, feel: :timeless, stereo_pan: true },
  # neapolitan_door, not :neapolitan. There is a generate_neapolitan_progression
  # but no :neapolitan route in GENERATED_STYLE_ROUTES, so the symbol resolves to
  # nothing and the render falls back to the default progression without saying
  # so -- this preset was written as :neapolitan first and rendered
  # pedal_e_descent. generated_neapolitan above has the same symbol and the same
  # silent fallback.
  sheger_07: { bpm: 74, progression: :neapolitan_door, chord_bars: 2, phrase_bars: 16,
               swing: 56, feel: :organic },
  sheger_08: { bpm: 113, progression: :d_add9_soul_arc, chord_bars: 1, phrase_bars: 8,
               swing: 54, feel: :loose_pocket, stereo_pan: true },

  baroque: {
    bpm: 104, progression: :baroque, chord_bars: 1, phrase_bars: 8, swing: 53,
    feel: :chromatic_planing,
    timing: { snare: -14..-5, hat_up: 8..18, bass: 10..24, kick_anchor: 0..3, pad: -6..4 },
  },
  chromatic_mediant: {
    bpm: 84, progression: :chromatic_mediant, chord_bars: 2, phrase_bars: 16, swing: 61,
    feel: :loose_pocket, stereo_pan: true, sidechain: true, voicing: :quartal, intro_bars: 8,
    timing: { snare: -30..-13, hat_up: 18..38, bass: 26..48, kick_anchor: 0..7, pad: 8..24 },
  },
  neo_soul: {
    bpm: 84, progression: :neo_soul, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :timeless, stereo_pan: true,
    timing: { snare: -20..-8, hat_up: 14..30, bass: 18..38, kick_anchor: 0..5, pad: 2..16 },
  },
  syncopated_slash_ninth: {
    bpm: 90, progression: :syncopated_slash_ninth, chord_bars: 1, phrase_bars: 7,
    swing: 54, feel: :syncopated_slash_ninth, stereo_pan: true, quintuplet: true,
    timing: { snare: -24..-10, hat_up: 20..36, bass: 28..48, kick_anchor: 0..3 },
  },
  chromatic_planing: {
    bpm: 96, progression: :chromatic_planing, chord_bars: 2, phrase_bars: 2,
    swing: 56, feel: :chromatic_planing,
    timing: { bass: 10..22, pad: -8..4, kick_sync: 6..16 },
  },
  ascending_minor_stack: { bpm: 95, progression: :ascending_minor_stack, chord_bars: 2, swing: 58 },
  minor_soul_loop: { bpm: 90, progression: :minor_soul_loop, chord_bars: 2, phrase_bars: 8, swing: 55 },
  suspended_minor_turn: { bpm: 97, progression: :suspended_minor_turn, chord_bars: 2, swing: 57 },
  major_relative_minor_cycle: { bpm: 93, progression: :major_relative_minor_cycle, chord_bars: 2, swing: 58 },
  dominant_minor_resolve: { bpm: 92, progression: :dominant_minor_resolve, chord_bars: 2, swing: 56 },
  syncopated_slash_alt: { bpm: 102, progression: :syncopated_slash_alt, chord_bars: 1, phrase_bars: 7, swing: 54, feel: :syncopated_slash_ninth },
  minor_cycle_descent: { bpm: 94, progression: :minor_cycle_descent, chord_bars: 2, swing: 58 },
  minor_stepwise_cycle: { bpm: 91, progression: :minor_stepwise_cycle, chord_bars: 2, swing: 62,
                 timing: { bass: 8..28, kick_sync: 2..18 } },
  major7_relative_minor_turn: { bpm: 88, progression: :major7_relative_minor_turn, chord_bars: 2, swing: 57, quintuplet: true },
  minor_major_ninth_pair: { bpm: 95, progression: :minor_major_ninth_pair, chord_bars: 2, swing: 58 },
  minor_stepwise_ascent: { bpm: 93, progression: :minor_stepwise_ascent, chord_bars: 4, swing: 55 },
  alternating_minor7_pair: { bpm: 88, progression: :alternating_minor7_pair, chord_bars: 2, swing: 58, quintuplet: true },
  sus_add9_ballad: { bpm: 92, progression: :sus_add9_ballad, chord_bars: 2, phrase_bars: 16, swing: 56,
                    feel: :timeless, stereo_pan: true },
  chromatic_mediant_drift: { bpm: 86, progression: :chromatic_mediant_drift, chord_bars: 2, phrase_bars: 32, swing: 54,
                     feel: :flylo_abstract, stereo_pan: true, sidechain: true, voicing: :quartal, intro_bars: 8,
                     half_time_bars: (32..47),
                     timing: { snare: -28..-12, hat_up: 18..36, bass: 24..44, kick_anchor: 0..6, pad: 6..20 } },
  suspended_minor_close: { bpm: 91, progression: :suspended_minor_close, chord_bars: 2, swing: 56 },
  timeless: {
    bpm: 86, progression: :fourth_third_sixth_second_turn, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 },
  },
  db_major_minor_fall: {
    bpm: 94, progression: :db_major_minor_fall, chord_bars: 2, phrase_bars: 8, swing: 54,
    feel: :timeless, quintuplet: true, voicing: :rootless,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 },
  },
  pedal_e_descent: {
    bpm: 92, progression: :pedal_e_descent, chord_bars: 1, phrase_bars: 6, swing: 54,
    feel: :syncopated_slash_ninth, stereo_pan: true, quintuplet: true, voicing: :rootless,
    timing: { snare: -24..-10, hat_up: 20..36, bass: 28..48, kick_anchor: 0..3 },
  },
  eb_minor_two_chord: {
    bpm: 91, progression: :eb_minor_two_chord, chord_bars: 2, phrase_bars: 8, swing: 57,
    feel: :dilla_slight, voicing: :rootless, quintuplet: true,
    timing: { snare: -22..-10, hat_up: 14..28, bass: 22..38, kick_anchor: 0..4 },
  },
  e_major_third_rise: {
    bpm: 88, progression: :e_major_third_rise, chord_bars: 2, phrase_bars: 8, swing: 57,
    feel: :timeless, quintuplet: true, voicing: :rootless,
  },
  d_add9_soul_arc: {
    bpm: 92, progression: :d_add9_soul_arc, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, stereo_pan: true, voicing: :rootless,
  },
  timeless_authentic: {
    bpm: 86, progression: :timeless_authentic, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 },
  },
  chromatic_minor_descent: {
    bpm: 86, progression: :chromatic_minor_descent, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -22..-10, hat_up: 14..28, bass: 22..38, kick_anchor: 0..4 },
  },
  jazz: { bpm: 88, progression: :jazz, chord_bars: 4, swing: 60 },
  # Not a lookup — dilla_progression detects :generated and calls
  # generate_progression (functional-harmony random walk) instead.
  # GEN_ROOT/GEN_MODE/GEN_LENGTH/GEN_SEED env vars configure it.
  generated: {
    bpm: 90, progression: :generated, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :organic, stereo_pan: true,
  },
  # progression: matches a GENERATED_STYLES entry directly — dilla_progression
  # detects this and routes to the matching generate_*_progression call.
  generated_planing: {
    bpm: 86, progression: :planing, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :organic, stereo_pan: true,
  },
  generated_mediant: {
    bpm: 78, progression: :chromatic_mediant, chord_bars: 2, phrase_bars: 16, swing: 60,
    feel: :organic, stereo_pan: true,
  },
  generated_polytonal: {
    bpm: 92, progression: :polytonal, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :organic, stereo_pan: true,
  },
  generated_negative: {
    bpm: 84, progression: :negative_harmony, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :organic, stereo_pan: true,
  },
  generated_neapolitan: {
    bpm: 80, progression: :neapolitan, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :organic, stereo_pan: true,
  },
  generated_techno: {
    bpm: 80, progression: :chromatic_mediant, chord_bars: 2, phrase_bars: 16, swing: 0,
    feel: :techno_house, stereo_pan: true,
  },
  # generate_coltrane_changes/generate_modal_interchange (GENERATED_STYLE_ROUTES
  # above) were reachable only via a raw GEN_STYLE=major_third_cycle_full|modal_interchange
  # env override with no discoverable named preset -- both are real, working,
  # theory-grounded generators (major-third symmetric substitution; borrowed
  # chords from the parallel mode) that just had no entry here.
  generated_coltrane: {
    bpm: 88, progression: :major_third_cycle_full, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :organic, stereo_pan: true,
  },
  generated_modal_interchange: {
    bpm: 84, progression: :modal_interchange, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :organic, stereo_pan: true,
  },
  generated_tritone_sub: {
    bpm: 86, progression: :tritone_sub, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :organic, stereo_pan: true,
  },
  # Hybrid: base feel stays Dilla-character (:syncopated_slash_ninth, same
  # pocket family as pedal_e_descent) so DRUM_STYLE_ALTERNATE genuinely
  # alternates -- CONCRETE_SOUL_MIX turns that on, flipping every other
  # phrase_bars-block into :techno_house's real four-on-the-floor
  # DRUM_PATTERN_SETS entry (straight kicks, dense 16th hats). Swing at
  # this engine's floor (50 -- SWING is clamped 50..66 everywhere in this
  # file, so "straighter than dilla" tops out here, not true 0 swing) so
  # neither phrase type feels like it's fighting the other's pocket. Carries
  # the full harmonic engine most techno never touches: tritone-sub-capable
  # functional progression, theory-scored voice-leading, fugue-conversation
  # ghost answers, rotating drum archetypes, room print. CONCRETE_SOUL_MIX
  # (see below) then forces the mix harder.
  concrete_soul: {
    bpm: 138, progression: :tritone_sub, chord_bars: 4, phrase_bars: 16, swing: 50,
    feel: :syncopated_slash_ninth, voicing: :rootless, stereo_pan: true,
  },
  fourth_third_sixth_second_turn: {
    bpm: 86, progression: :fourth_third_sixth_second_turn, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 },
  },
  voice_led_minor_arc: {
    bpm: 86, progression: :voice_led_minor_arc, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14 },
  },
  borrowed_dominant_turn: {
    bpm: 90, progression: :borrowed_dominant_turn, chord_bars: 2, phrase_bars: 8, swing: 54,
    feel: :timeless, voicing: :spread,
    timing: { snare: -22..-10, hat_up: 14..28, bass: 22..38, kick_anchor: 0..4 },
  },
  soul: {
    bpm: 84, progression: :soul, chord_bars: 4, phrase_bars: 16, swing: 58,
    feel: :timeless, voicing: :spread,
    timing: { snare: -20..-8, hat_up: 14..28, bass: 20..36, kick_anchor: 0..5 },
  },
  players: {
    bpm: 93, progression: :players_measured, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :timeless, voicing: :spread,
    timing: { snare: -20..-8, hat_up: 12..26, bass: 18..34, kick_anchor: 0..5 },
  },
  gospel_backdoor: {
    bpm: 86, progression: :gospel_backdoor, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :rootless,
    timing: { snare: -24..-9, hat_up: 14..30, bass: 20..40, kick_anchor: 0..4, pad: 4..16 },
  },
  minor_iv_lift: {
    bpm: 88, progression: :minor_iv_lift, chord_bars: 2, phrase_bars: 16, swing: 57,
    feel: :loose_pocket, quintuplet: true, voicing: :bill_evans,
    timing: { snare: -23..-8, hat_up: 18..34, bass: 22..42, kick_anchor: 0..5, pad: 2..14 },
  },
  common_tone_sideways: {
    bpm: 84, progression: :common_tone_sideways, chord_bars: 2, phrase_bars: 16, swing: 55,
    feel: :organic, stereo_pan: true, voicing: :rootless,
    timing: { snare: -18..-6, hat_up: 12..28, bass: 18..36, kick_anchor: 0..4, pad: -2..10 },
  },
  detroit_suspension: {
    bpm: 91, progression: :detroit_suspension, chord_bars: 1, phrase_bars: 8, swing: 56,
    feel: :syncopated_slash_ninth, quintuplet: true, voicing: :kenny_barron,
    timing: { snare: -26..-10, hat_up: 20..38, bass: 26..48, kick_anchor: 0..4 },
  },
  minor_ninth_two_chord: {
    bpm: 90, progression: :minor_ninth_two_chord, chord_bars: 2, phrase_bars: 8, swing: 57,
    feel: :timeless, quintuplet: true, voicing: :rootless,
    timing: { snare: -24..-10, hat_up: 16..32, bass: 24..44, kick_anchor: 0..4, pad: 3..15 },
  },
  fugue_conversation_arc: {
    bpm: 86, progression: :fugue_conversation_arc, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..30, bass: 22..42, kick_anchor: 0..5, pad: 2..14 },
  },

  # ==========================================================================
  # One track per dance feel (2026-07-30). A DRUM_PATTERN_SETS entry that no
  # preset names is only reachable by setting FEEL by hand, and a progression
  # that no preset names is only reachable by setting PROGRESSION by hand;
  # these pair each new grid with a new harmony so both arrive by TRACK=name,
  # show up in the medley, and can be listened to instead of read.
  #
  # The tempos are the tradition's own, not the file's usual 84-96 -- a two-step
  # at 90 is not a two-step -- and the swing is deliberately low across all of
  # them. The Dilla lean and a dance floor want opposite things from the same
  # sixteenth: one wants it late and human, the other wants it exactly where the
  # foot already is.
  # ==========================================================================
  two_step: {
    bpm: 134, progression: :dorian_open_window, chord_bars: 2, phrase_bars: 8, swing: 56,
    feel: :two_step, stereo_pan: true, voicing: :rootless,
    timing: { snare: -8..0, hat_up: 6..16, bass: 4..12, kick_anchor: 0..2, pad: 0..8 },
  },
  broken_beat: {
    bpm: 128, progression: :sub_ladder_down, chord_bars: 2, phrase_bars: 8, swing: 58,
    feel: :broken_beat, stereo_pan: true, voicing: :quartal,
    timing: { snare: -12..-2, hat_up: 8..20, bass: 6..18, kick_anchor: 0..4, pad: -4..8 },
  },
  amapiano_offbeat: {
    bpm: 112, progression: :still_water_pedal, chord_bars: 4, phrase_bars: 8, swing: 52,
    feel: :amapiano_offbeat, stereo_pan: true, sidechain: true, voicing: :spread,
    timing: { snare: -6..2, hat_up: 4..12, bass: 2..10, kick_anchor: 0..2, pad: 0..10 },
  },
  dembow: {
    bpm: 96, progression: :phrygian_dominant_descent, chord_bars: 2, phrase_bars: 8, swing: 50,
    feel: :dembow, stereo_pan: true, voicing: :close,
    timing: { snare: -4..2, hat_up: 2..10, bass: 0..8, kick_anchor: 0..2, pad: 0..6 },
  },
  tresillo_house: {
    bpm: 122, progression: :double_plagal_open, chord_bars: 2, phrase_bars: 8, swing: 52,
    feel: :tresillo_house, stereo_pan: true, sidechain: true, voicing: :quartal,
    timing: { snare: -6..0, hat_up: 4..12, bass: 2..10, kick_anchor: 0..2, pad: 0..8 },
  },
  disco_boogie: {
    bpm: 118, progression: :bell_chain_of_fifths, chord_bars: 2, phrase_bars: 8, swing: 50,
    feel: :disco_boogie, stereo_pan: true, sidechain: true, voicing: :drop2,
    timing: { snare: -4..2, hat_up: 2..8, bass: 0..6, kick_anchor: 0..2, pad: 0..6 },
  },
  batucada: {
    bpm: 104, progression: :picardy_window, chord_bars: 2, phrase_bars: 8, swing: 54,
    feel: :batucada, stereo_pan: true, voicing: :bill_evans,
    timing: { snare: -10..-2, hat_up: 6..14, bass: 4..14, kick_anchor: 0..3, pad: 0..10 },
  },
  footwork_triplet: {
    bpm: 160, progression: :hexatonic_cycle_ring, chord_bars: 4, phrase_bars: 8, swing: 50,
    feel: :footwork_triplet, stereo_pan: true, voicing: :cluster,
    timing: { snare: -4..2, hat_up: 2..8, bass: 0..6, kick_anchor: 0..2, pad: 0..6 },
  },
  afrobeats_pocket: {
    bpm: 104, progression: :parallel_ninth_tide, chord_bars: 2, phrase_bars: 8, swing: 55,
    feel: :afrobeats_pocket, stereo_pan: true, voicing: :spread,
    timing: { snare: -8..0, hat_up: 6..14, bass: 4..14, kick_anchor: 0..3, pad: 0..10 },
  },
}.freeze
