# frozen_string_literal: true
#
# Chord voicing tables and the artist-verified progression set.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

MODAL_MINOR_CHORDS = [
  { name: "Fm9",       hz: [174.61, 207.65, 261.63, 311.13, 392.00] },
  { name: "Dbmaj9",    hz: [138.59, 174.61, 207.65, 261.63, 311.13] },
  { name: "Bbm9",      hz: [116.54, 138.59, 174.61, 207.65, 261.63] },
  { name: "Eb7",       hz: [155.56, 196.00, 233.08, 277.18, 311.13] },
  { name: "Abmaj9low", hz: [103.83, 130.81, 155.56, 196.00, 233.08] },
  { name: "C7b9",      hz: [130.81, 138.59, 164.81, 196.00, 233.08] },
  { name: "Fm/C",      hz: [130.81, 174.61, 207.65, 261.63, 311.13] },
  # Was missing the 4th that actually makes a "sus" chord a sus chord.
  # Real Bb7sus4(add9): root, 4, 5, b7, 9.
  { name: "Bb7sus",    hz: [116.54, 155.56, 174.61, 207.65, 261.63] },
  { name: "G#m7",      hz: [103.83, 123.47, 155.56, 185.00, 233.08] },
  # Root was literally C (130.81), a semitone flat of its own name — this
  # spelled Cm7(b9), not C#m7. Real C#m7: root, b3, 5, b7, 9.
  { name: "C#m7",      hz: [138.59, 164.81, 207.65, 246.94, 311.13] },
  { name: "D#m7",      hz: [155.56, 185.00, 233.08, 277.18, 311.13] },
  { name: "Dm7",       hz: [146.83, 174.61, 220.00, 261.63, 329.63] },
  { name: "Gm7",       hz: [196.00, 233.08, 293.66, 349.23, 440.00] },
  { name: "Am7",       hz: [110.00, 130.81, 164.81, 196.00, 246.94] },
  # Had both the major AND minor 3rd sounding at once (F# and F). Real D9:
  # root, 3, 5, b7, 9.
  { name: "D7",        hz: [146.83, 185.00, 220.00, 261.63, 329.63] },
  { name: "Eb7",       hz: [155.56, 196.00, 233.08, 277.18, 311.13] },
  { name: "Ebmaj9",    hz: [155.56, 196.00, 233.08, 293.66, 349.23] },
  { name: "Gm9",       hz: [196.00, 233.08, 293.66, 349.23, 440.00] },
].freeze
# Real transcriptions researched directly (distinct from the Get Dis Money /
# Donuts-derived tables above): Slum Village "Fall in Love" & "Climax"
# (Fantastic Vol. 2, ChordU); D'Angelo "Untitled (How Does It Feel)"
# (Voodoo — same Soulquarians lineage Dilla recorded alongside); Flying
# Lotus "Never Catch Me" (danny fratina's published chord analysis) for the
# quartal/#11 extended-jazz color FlyLo is known for.
EXTENDED_TENSION_CHORDS = [
  { name: "Ebm7fil",    hz: [155.56, 185.00, 233.08, 277.18, 349.23] }, # Fall in Love
  { name: "Bbm7fil",    hz: [116.54, 138.59, 174.61, 207.65, 261.63] },
  { name: "Emaj7",      hz: [164.81, 207.65, 246.94, 311.13, 369.99] }, # Climax
  { name: "E7climax",   hz: [164.81, 207.65, 246.94, 293.66, 369.99] },
  { name: "Dadd9",      hz: [146.83, 185.00, 220.00, 329.63, 440.00] }, # Untitled (How Does It Feel)
  { name: "A7sus4",     hz: [110.00, 146.83, 164.81, 196.00, 246.94] },
  { name: "G6",         hz: [196.00, 246.94, 293.66, 329.63, 392.00] },
  { name: "C9",         hz: [130.81, 164.81, 196.00, 233.08, 293.66] },
  { name: "F#m9",       hz: [185.00, 220.00, 277.18, 329.63, 415.30] },
  { name: "B9",         hz: [123.47, 155.56, 185.00, 220.00, 277.18] },
  { name: "Asus9",      hz: [110.00, 146.83, 164.81, 220.00, 246.94] },
  { name: "Cm11nc",     hz: [130.81, 155.56, 196.00, 233.08, 349.23] }, # Never Catch Me
  { name: "AbMaj13s11", hz: [207.65, 261.63, 311.13, 392.00, 587.33] },
  { name: "A7nc",       hz: [110.00, 138.59, 164.81, 196.00, 246.94] },
  { name: "Dmaj9nc",    hz: [146.83, 185.00, 220.00, 277.18, 329.63] },
  { name: "DMaj7overG", hz: [98.00,  146.83, 185.00, 220.00, 277.18] },
].freeze
PAD_CHORD_LOOKUP = (
  PAD_CHORDS + EXTENDED_NINTH_CHORDS + MODAL_MINOR_CHORDS + EXTENDED_TENSION_CHORDS
).each_with_object({}) { |c, m| m[c[:name]] = c unless m[c[:name]] }.freeze
# ---------------------------------------------------------------------------
# ARTIST-VERIFIED progressions only (exact artist/sample harmony).
# Sources checked against public discussions + published transcriptions:
#   r/jdilla — Fall in Love = Gap Mangione "Diana in the Autumn Wind" sample
#   Ethan Hein — Get Dis Money / Herbie "Come Running To Me" slash loop
#   Hooktheory / RG-69 — Donuts "Time" Ab IV–iii–vi–ii
#   ChordU — Climax, Untitled (How Does It Feel)
# Non-verified invented loops stay in CHORD_PROGRESSIONS below but are blocked
# from stream/default when ARTIST_VERIFIED_ONLY=1 (default).
# ---------------------------------------------------------------------------
ARTIST_VERIFIED_PROGRESSIONS = {
  # Ahmad Jamal — his arrangement of Morton Gould's "Pavanne", recorded
  # 1955-10-25. Jamal supports the melody with a Dm7 vamp and then an Ebm7 vamp:
  # two minor sevenths a semitone apart, held long enough to stop being chords
  # and start being places.
  #
  # This is the harmony Miles took for "So What" four years later, and the
  # reason it is worth having here rather than as trivia: it is the origin of
  # the modal two-chord vamp, and this engine's whole "stay on one centre and
  # generate interest by other means" problem is the one Jamal solved first.
  # DillaHarmony already ships a :so_what voicing style; this is what it is named
  # after.
  minor_half_step_pair: {
    artist: "Ahmad Jamal", title: "Pavanne", composer: "Morton Gould",
    recorded: "1955-10-25",
    chords: %w[Dm7 Ebm7],
    sources: [
      "Stuart Nicholson, 'The Ahmad Jamal Live Performances 1958-62': Jamal " \
      "supports the melody with a Dm7 vamp followed by an Ebm7 vamp, the " \
      "harmonies that later underpin the A and B sections of So What",
      "Miles Davis, 1958: 'All my inspiration today comes from the Chicago " \
      "pianist Ahmad Jamal'",
    ],
  },
  # The same two chords as Miles arranged them: 32-bar AABA, Dm7 for 16, Ebm7
  # for 8, Dm7 for 8. Written 2:1:1 because chord_bars scales the proportion
  # rather than the bar count. Coltrane then took Pavanne's eight-bar secondary
  # theme over this form and called it "Impressions" (1961), so all three pieces
  # are one lineage and one pair of chords.
  dorian_two_chord_modal: {
    artist: "Miles Davis", title: "So What", album: "Kind of Blue",
    derived_from: "Ahmad Jamal — Pavanne (1955)",
    chords: %w[Dm7 Dm7 Ebm7 Dm7],
    sources: [
      "Kind of Blue (1959), 32-bar AABA: Dm7 x16, Ebm7 x8, Dm7 x8",
      "Coltrane's Impressions (1961) reuses the form and harmony",
    ],
  },
  # J Dilla — Donuts: "Time (The Donut of the Heart)" — Ab major IV–iii–vi–ii.
  db_major_minor_fall: {
    artist: "J Dilla", title: "Time (The Donut of the Heart)", album: "Donuts",
    chords: %w[Dbmaj7 Cm7 Fm7 Bbm7],
    sources: [
      "Hooktheory / Ab IV–iii–vi–ii (Dbmaj7–Cm7–Fm7–Bbm7)",
      "RG-69 researched Donuts symbols",
    ],
  },
  # Same harmonic cycle with 9ths (pad color variant of Time, not a different song).
  maj7_minor_cycle: {
    artist: "J Dilla", title: "Time (The Donut of the Heart)", album: "Donuts",
    chords: %w[Dbmaj9 Cm9 Fm9 Bbm9],
    sources: ["Same Time cycle with maj9/m9 extensions"],
  },
  # Slum Village — Fall in Love (prod. Dilla) samples Gap Mangione.
  # r/jdilla (bzaiif): "Gap Mangione - Diana in the Autumn Wind".
  # ChordU / engine: two-chord Ebm7–Bbm7 vamp (not the old fabricated Bbm–Ab–Fm).
  eb_minor_two_chord: {
    artist: "Slum Village", title: "Fall in Love", producer: "J Dilla",
    sample: "Gap Mangione — Diana in the Autumn Wind",
    chords: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
    sources: [
      "r/jdilla: chords for Fall in love? — sample ID Diana in the Autumn Wind",
      "ChordU Ebm7/Bbm7 loop transcription",
    ],
  },
  # Slum Village — Get Dis Money. Ethan Hein full transcription of Herbie sample.
  pedal_e_descent: {
    artist: "Slum Village", title: "Get Dis Money", producer: "J Dilla",
    sample: "Herbie Hancock — Come Running To Me (Sunlight, 2:08)",
    chords: %w[D/E Db/E C/E Bm/E Bbm/E Am/E],
    sources: [
      "Ethan Hein 2022 transcription https://ethanhein.com/wp/2022/get-dis-money/",
      "D/E = E9sus4; then Db/E C/E Bm/E Bbm/E Am/E over E pedal",
    ],
  },
  # Alias used historically in engine for the same GDM slash cycle.
  syncopated_slash_ninth: {
    artist: "Slum Village", title: "Get Dis Money", producer: "J Dilla",
    sample: "Herbie Hancock — Come Running To Me",
    chords: %w[E9sus4/D Db/E C/E Bm/E Bbm/E Am/E E9sus4],
    sources: ["Ethan Hein Get Dis Money (E9sus4/D naming of D/E)"],
  },
  # Slum Village — Climax (ChordU; was previously wrong-key Fm loop).
  e_major_third_rise: {
    artist: "Slum Village", title: "Climax", producer: "J Dilla",
    chords: %w[Emaj7 G#m7 C#m7 E7climax],
    sources: ["ChordU Climax transcription"],
  },
  major7_relative_minor_turn: {
    artist: "Slum Village", title: "Climax", producer: "J Dilla",
    chords: %w[Emaj7 G#m7 C#m7 E7climax],
    sources: ["ChordU Climax (alias)"],
  },
  # D'Angelo — Untitled (How Does It Feel), Voodoo (Soulquarians / Dilla era).
  d_add9_soul_arc: {
    artist: "D'Angelo", title: "Untitled (How Does It Feel)", album: "Voodoo",
    chords: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
    sources: ["ChordU / Voodoo published chord analysis"],
  },
  sus_add9_ballad: {
    artist: "D'Angelo", title: "Untitled (How Does It Feel)", album: "Voodoo",
    chords: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
    sources: ["ChordU Untitled (alias)"],
  },
  # Alternating minor-7 pair = Fall in Love / Diana vamp (explicit name).
  alternating_minor7_pair: {
    artist: "Slum Village", title: "Fall in Love", producer: "J Dilla",
    sample: "Gap Mangione — Diana in the Autumn Wind",
    chords: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
    sources: ["Same as eb_minor_two_chord"],
  },
}.freeze

# The strictly Dilla-produced subset (artist or producer: J Dilla) — the
# "original J Dilla progressions". Excludes the D'Angelo Voodoo entries.
DILLA_PRODUCED_TRACKS = ARTIST_VERIFIED_PROGRESSIONS.select do |_k, v|
  v[:artist] == "J Dilla" || v[:producer] == "J Dilla"
end.keys.freeze

def artist_verified_only?
  ENV.fetch("ARTIST_VERIFIED_ONLY", "1") != "0"
end

# Default on (2026-07-27 user request): stream/deep rotation uses only the
# original Dilla-produced progressions above. DILLA_PROGRESSIONS_ONLY=0
# restores the full curated rotation.
def dilla_progressions_only?
  ENV.fetch("DILLA_PROGRESSIONS_ONLY", "1") != "0"
end

# The Dilla core first, then everything else in the same key and mode.
#
# This returned the eight Dilla-produced progressions and stopped, because
# widening it meant key chaos across a 248-progression catalogue spanning every
# mode. KeyLock removed that objection — everything resolves to one tonic now —
# so the pool widens to what shares the scale as well as the root: 203 of 248 at
# a 0.80 root-fit against Bb Dorian/Aeolian plus the parallel major.
#
# Widened outward from the core rather than replacing it. Narrowing to Dilla's
# own was a deliberate choice (2026-07-27) and those eight stay, first and
# always. MODAL_ROTATION=0 restores the narrow pool exactly.
def stream_track_pool
  # STREAM_POOL names the rotation outright.
  #
  # The pool was DillaLofiMachine::STREAM_ROTATION and nothing else, so a stream
  # could only ever play the tracks that constant lists -- the sample-backed
  # ones in TRACK_SAMPLE_LOOPS were unreachable from the stream entirely, the
  # same fault as the demo's. Naming them is the only way to hear a stream built
  # on chopped records rather than on synthesised pads.
  named = ENV["STREAM_POOL"].to_s.split(",").map { |t| t.strip.downcase.tr("-", "_") }.reject(&:empty?)
  return named.map(&:to_sym) unless named.empty?

  pool = DillaLofiMachine::STREAM_ROTATION
  return pool unless dilla_progressions_only?

  dilla_only = DILLA_PRODUCED_TRACKS.map(&:to_s)
  core = pool.select { |t| dilla_only.include?(t) }.then { |p| p.empty? ? dilla_only : p }
  # Artist-verified entries are exempt from the modal fit test — they carry
  # sources and were chosen deliberately, so a heuristic tuned for unvetted
  # catalogue material should not silently drop them.
  ModalFamily.widen(core, CHORD_PROGRESSIONS, always: ARTIST_VERIFIED_PROGRESSIONS.keys)
end

# Every consumer of a verified progression comes through here, so this is where
# the rotation is brought to one tonal centre. KEY_LOCK=0 restores the
# original keys; KEY_LOCK_TONIC names a different target.
def artist_verified_chords(key)
  entry = ARTIST_VERIFIED_PROGRESSIONS[key&.to_sym]
  return nil unless entry

  KeyLock.lock(entry[:chords])
end
