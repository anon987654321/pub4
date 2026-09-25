# frozen_string_literal: true

# Time: the groove score, the producer DNA presets that carry each lineage's
# grid and swing, the groove engine and the rhythm macros.

# Transient-aware pocket scoring — velocity spread, ghost density, timing bias.
module DillaGrooveScore
  module_function

  def analyze(events, meta: nil)
    return { score: 70, breakdown: {} } unless events.is_a?(Hash)

    kicks_n = events[:kick]&.length || 0
    snares = events[:snare] || []
    ghosts = events[:ghost] || []
    hats_n = events[:hat]&.length || 0
    meta ||= events[:_groove_meta] || {}

    ghost_vels = ghosts.map { |e| e[1].to_f }
    ghost_var = variance(ghost_vels)
    ghost_density = ghosts.length.to_f / [kicks_n, 1].max

    snare_vels = snares.map { |e| e[1].to_f }
    backbeat_ratio = snares.empty? ? 0.0 : snare_vels.count { |v| v >= 0.5 } / snares.length.to_f

    hat_ratio = hats_n.to_f / [kicks_n, 1].max

    snare_early = Array(meta[:snare_early_ms])
    snare_early_avg = snare_early.empty? ? 0.0 : snare_early.sum / snare_early.length
    hat_late = Array(meta[:hat_late_ms])
    hat_late_avg = hat_late.empty? ? 0.0 : hat_late.sum / hat_late.length

    density_pts = [kicks_n * 0.5, 20].min + [ghosts.length * 0.3, 15].min
    score = 60.0 + density_pts
    score += [ghost_var * 100, 10].min
    score += 6 if ghost_density.between?(0.2, 0.85)
    score += 5 if backbeat_ratio >= 0.55
    score += [snare_early_avg.abs * 0.35, 10].min if snare_early_avg.negative?
    score += [hat_late_avg * 0.25, 8].min if hat_late_avg.positive?
    score -= 4 if hat_ratio > 14
    score += 3 if hat_ratio.between?(2.5, 10.0)

    breakdown = {
      kicks: kicks_n, ghosts: ghosts.length, hats: hats_n,
      ghost_var: ghost_var.round(3), ghost_density: ghost_density.round(3),
      backbeat_ratio: backbeat_ratio.round(3),
      snare_early_avg_ms: snare_early_avg.round(2),
      hat_late_avg_ms: hat_late_avg.round(2)
    }

    { score: score.round.clamp(40, 98), breakdown: }
  end

  def variance(values)
    return 0.0 if values.length < 2
    mean = values.sum / values.length
    values.sum { |v| (v - mean)**2 } / values.length
  end

  # Pocket-evolution hints for stream_evolve_pocket! — driven by last render's drum grid.
  def evolve_recommendations(analysis)
    breakdown = analysis[:breakdown] || {}
    score = analysis[:score] || 70
    recs = { score: }

    gd = breakdown[:ghost_density].to_f
    if gd < 0.2
      recs[:ghost_tier] = :accent
      recs[:ghost_boost_nudge] = 0.1
    elsif gd > 0.85
      recs[:ghost_tier] = :whisper
      recs[:ghost_boost_nudge] = -0.06
    else
      recs[:ghost_tier] = :pocket
    end

    recs[:velocity_spread_nudge] = 0.04 if breakdown[:ghost_var].to_f < 0.002
    recs[:snare_early] = true if breakdown[:snare_early_avg_ms].to_f > -4
    recs[:hats_late] = true if breakdown[:hat_late_avg_ms].to_f < 4

    if score < 72
      recs[:swing_delta] = 2.5
      recs[:jitter_ticks] = 4
      recs[:groove_pool] = %w[donuts madvillainy fantastic_vol2]
    elsif score < 78
      recs[:swing_delta] = 1.2
      recs[:jitter_ticks] = 3
      recs[:groove_pool] = %w[donuts fantastic_vol2 endtroducing]
    else
      recs[:swing_delta] = 0.5
      recs[:jitter_ticks] = 3
      recs[:groove_pool] = %w[donuts fantastic_vol2 madvillainy cosmogramma]
    end

    recs[:markov_ghosts] = score < 80
    recs
  end
end

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
    # Suspended shapes: the 4th replaces the 3rd. Absent until now, so the
    # "7sus" suffix had nothing to build from and fell through the
    # fetch-default to "maj9" -- giving a chord with a major third, the exact
    # note a suspension removes.
    "sus" => [0, 5, 7],
    "sus4" => [0, 5, 7, 10],
    "sus2" => [0, 2, 7],

    # The same class of bug as 7sus above, found 2026-07-29 by counting the
    # table's vocabulary: 72% of every chord symbol in CHORD_PROGRESSIONS is
    # some kind of 9th, and the three qualities that would break that monotony
    # were all being flattened on the way to a voicing.
    #
    #   m7b5 mapped to quality "m7"  -> [0,3,7,10], a natural 5th. Every
    #        half-diminished chord in the engine was a plain minor 7, so the
    #        ii of every minor ii-V had no tension in it at all.
    #   7b9  mapped to "7"           -> the b9 discarded.
    #   7alt mapped to "7"           -> every alteration discarded; "alt"
    #        rendered identically to an unaltered dominant.
    #
    # These are the chords that make a progression sound like it is going
    # somewhere, which is why adding more entries to CHORD_PROGRESSIONS would
    # not have helped: the entries were already there and the voicer was
    # throwing the interesting notes away.
    "m7b5" => [0, 3, 6, 10],
    "7b9" => [0, 4, 7, 10, 1],
    "7#5" => [0, 4, 8, 10],
    "7alt" => [0, 4, 8, 10, 1],
    "7#11" => [0, 4, 7, 10, 6],
    "13" => [0, 4, 7, 10, 9],
    "maj13" => [0, 4, 7, 11, 9],
    "maj13#11" => [0, 4, 11, 9, 6],
    "maj7#11" => [0, 4, 7, 11, 6],
    "mmaj7" => [0, 3, 7, 11],
    "m6" => [0, 3, 7, 9],
    # A bare "9" is a dominant with the ninth on top, and "add9" is a triad
    # with it -- neither had a suffix or a template, so B9, C9 and Dadd9 were
    # dropped from their progressions rather than voiced.
    "9" => [0, 4, 7, 10, 2],
    "add9" => [0, 4, 7, 2],
    "sus9" => [0, 2, 5, 7],
    # E9sus4 — the chord Get Dis Money opens on, and it did not parse.
    #
    # ARTIST_VERIFIED_PROGRESSIONS names it twice: pedal_e_descent's source note
    # says "D/E = E9sus4", and the syncopated_slash_ninth alias spells the
    # progression as E9sus4/D … E9sus4 outright. Both were unparseable, so
    # progression_for's filter_map silently dropped them and that alias rendered
    # 5 of its 7 chords — losing exactly the ninth it is named for. A sus4 with
    # the b7 and the 9 on top, no third; that suspended colour over the E pedal
    # is what the Herbie Hancock sample is doing.
    "9sus4" => [0, 5, 7, 10, 2],
    "9sus" => [0, 5, 7, 10, 2],
    # Symmetrical shapes — no template, no suffix, so every one of them raised
    # ArgumentError, which progression_for's rescue swallowed. That is how
    # chromatic_descent_sixteen lost the Abdim out of its D-C#-C-B-Bb-A-Ab-G
    # bass walk: the walk is the whole progression, and it was rendering with a
    # hole where the seventh step goes.
    #
    # A diminished chord divides the octave in equal minor thirds and an
    # augmented one in equal major thirds, which is why they can pivot to four
    # (or three) keys at once and why they are the standard connective tissue
    # between two chords that have nothing else in common.
    "dim" => [0, 3, 6],
    "dim7" => [0, 3, 6, 9],
    "aug" => [0, 4, 8],
    "maj7#5" => [0, 4, 8, 11],
    # The remaining neo-soul and altered-dominant colours. Without templates
    # these fell through quality_for_suffix to maj9, so a written 7#9 rendered
    # as a major ninth -- the opposite chord.
    #
    # Spelling follows this table's own extension convention (see
    # voice_extensions): an interval SMALLER than one already listed is an
    # upper extension and gets raised an octave, so "3" after "10" is a #9 at
    # 15, not a minor third. Written that way, 7#9 voices [0,4,7,10,15] and
    # 7b13 voices [0,4,7,10,20]. Order inside each array is therefore load
    # bearing -- sorting one of these ascending would collapse its tension
    # into a semitone cluster against the root.
    "7#9" => [0, 4, 7, 10, 3],
    "7b13" => [0, 4, 7, 10, 8],
    # Two tensions on a dominant means five notes plus a fifth, and
    # build_voicing only carries five: its trim keeps the root and then the
    # HIGHEST four, so the sixth-note versions of these came out
    # [0,7,10,3,8] -- the third gone, which is half the tritone that makes a
    # dominant a dominant. The fifth is the note a piano player drops first
    # for exactly this reason, so it is dropped here instead and the trim
    # never fires. Order still matters: an interval smaller than one already
    # listed is an upper extension (see voice_extensions), so b9-then-13
    # stacks 13 then 21, while 13-then-b9 stacks 21 then 25 and the b9 ends
    # up two octaves out.
    "13b9" => [0, 4, 10, 1, 9],
    "13#11" => [0, 4, 10, 6, 9],
    "7#9#11" => [0, 4, 10, 3, 6],
    "7#9b13" => [0, 4, 10, 3, 8],
    "maj7#9" => [0, 4, 7, 11, 3],
    "maj9#11" => [0, 4, 11, 2, 6],
    "m9b5" => [0, 3, 6, 10, 2],
    "m11b5" => [0, 3, 6, 10, 5],
    "m13" => [0, 3, 7, 10, 9],
    "m7#5" => [0, 3, 8, 10],
    "add#11" => [0, 4, 7, 6],
    # Spelled "69", not "6/9". uncached_chord_from_symbol short-circuits on
    # any symbol containing "/" into slash_chord_from_symbol before the suffix
    # matcher is ever consulted, so "C6/9" is read as a C6 triad over a bass
    # note called "9" and raises KeyError. A suffix with a slash in it can
    # never be reached here.
    "69" => [0, 4, 7, 9, 2],
  }.freeze

  NOTE_PC = {
    "C" => 0, "B#" => 0, "Db" => 1, "C#" => 1, "D" => 2, "Eb" => 3, "D#" => 3,
    "E" => 4, "Fb" => 4, "F" => 5, "Gb" => 6, "F#" => 6, "G" => 7, "Ab" => 8,
    "G#" => 8, "A" => 9, "Bb" => 10, "A#" => 10, "B" => 11, "Cb" => 11,
  }.freeze

  DILLA_TIMING = {
    snare: -22..-10, ghost: -12..10, hat_down: -2..4, hat_up: 12..24,
    kick_anchor: 4..10, kick_sync: 8..18, bass: 24..38, pad: 4..14,
  }.freeze

  WONKY_TIMING = {
    snare: -26..-12, ghost: -8..14, hat_down: 4..10, hat_up: 16..32,
    kick_anchor: 2..8, kick_sync: 6..16, bass: 22..42, pad: 6..18,
  }.freeze

  MADLIB_TIMING = {
    snare: -20..-8, ghost: -6..16, hat_down: 0..8, hat_up: 10..22,
    kick_anchor: 3..9, kick_sync: 7..16, bass: 20..36, pad: 2..12,
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
    # Same defect the Eb7 note below describes, in the entry directly above it:
    # 311.13 was Eb4, the root doubled where the b7 goes, leaving an Eb triad
    # with a ninth on it. gem_chord_sane?'s own docstring cites "Eb9 with no b7
    # at all" as the gem's failure -- and the hand-written voicing that exists
    # to bypass the gem had it too. 277.18 is Db4.
    "Eb9" => [155.56, 196.00, 233.08, 277.18, 349.23],
    # 311.13 was Eb4 -- the root doubled an octave up where the b7 belongs, so
    # this was a bare Eb triad, not a dominant. 277.18 is Db4.
    "Eb7" => [155.56, 196.00, 233.08, 277.18],
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
    # DillaMusicGems (major_third_cycle_full gem) hangs on this exact symbol too, cold or
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
    # 207.65 is Ab3, a MINOR seventh -- this was a Bb7, not Bbmaj7. 220.0 is A3.
    "Bbmaj7" => [116.54, 146.83, 174.61, 220.00, 293.66],
    # 138.59 is Db3 (minor third) and 207.65 is Ab3 (minor seventh): this entry
    # spelled Bbm9 under the name Bbmaj9. D3 is 146.83, A3 is 220.0.
    "Bbmaj9" => [116.54, 146.83, 174.61, 220.00, 261.63],
    "Abmaj7" => [207.65, 261.63, 311.13, 392.00, 466.16],
  }.freeze

  # The whitelist the parser matches against. Every entry needs a template in
  # CHORD_TEMPLATES or an entry in QUALITY_ALIASES, or quality_for_suffix
  # silently voices it as maj9 -- test_chord_suffixes_all_have_a_template pins
  # that. "sus4" and "sus" were listed in CHORD_TEMPLATES but not here, and
  # this list is what the parser consults, so `Dsus4` raised and got
  # filter_map'd away: quartal_suspension_twelve lost all four of the
  # suspensions it is named for. Bare "sus4" resolves to the template carrying
  # the b7, matching the 7sus4/7sus aliases.
  #
  # The trailing "" makes a BARE major triad ("F", "D") parse at all. Without
  # it chord_from_symbol raised ArgumentError on any plain triad, and because
  # callers rescue that to nil every bare-triad chord was dropped by
  # filter_map -- upper_triad_tower collapsed from 8 chords to 3,
  # drone_quartal_wash 8 to 5. It must stay last so it only matches when
  # nothing else does.
  #
  # Entries are matched whole (\A[A-G][#b]?<sfx>\z), so ordering does NOT
  # decide between them today. Longest-first is kept as house style so the
  # list still reads correctly if that anchoring is ever relaxed.
  CHORD_SUFFIXES = %w[
    maj13#11 maj9#11 maj7#11 maj13 maj9low maj9 maj7#9 maj7#5 maj7
    m11b5 m7b5 mmaj7 m9b5 m13 m11 m9 m7#5 m7 m6
    9sus4 9sus 7sus4 7sus 7#9b13 7#9#11 7#11 7#9 7alt 7#5 7b13 7b9
    13#11 13b9 13 7
    dim7 dim aug add#11 add9 sus9 sus4 sus2 sus 69 9 6 m
  ].freeze + [""].freeze

# Compiled once. The interpolated form was rebuilt on every iteration of every
# call (no /o on an interpolated literal), so a bare "C" — which walks the whole
# list to the trailing "" — cost 97us before this change set and 198us after it,
# since the four new suffixes sit ahead of the common ones. Precompiled: 8us.
SUFFIX_MATCHERS = CHORD_SUFFIXES.map { |sfx| [sfx, /\A[A-G][#b]?#{sfx}\z/i] }.freeze

  PAD_WAVEFORMS = %i[sine square sawtooth triangle].freeze

  # 16-step MPC grids: kicks/snares/hats/ghosts/claps/perc + swing/humanize.
  DRUM_PRESETS = {
    # Eleven hits a bar, and the eleven are the point.
    #
    # Every other Dilla-named preset here fires nineteen to twenty-five: hats on
    # all eight eighths, a clap doubling the snare on the same two steps, ghosts
    # and perc over the top. That is a busy pattern, and busy is the one thing
    # these records are not -- a Donuts beat is frequently a kick, a backbeat
    # and air. Density is why the kit did not read as hip-hop; the microtiming
    # was already right.
    #
    # KICK on the downbeat and the sixteenth before the second backbeat. Two,
    # not five. The gap between them is what the bass and the sample fill.
    #
    # SNARE on 4 and 12 and nothing else, and no clap doubled onto it -- two
    # samples on one step is a slap, not a backbeat. This is the layer that
    # drags: GROOVE_FEEL puts it four ticks late at 96 PPQ.
    #
    # HATS on six of the eight eighths, deliberately leaving 4 and 12 open so
    # the snare arrives into space rather than into a hat. This is also the
    # steady reference the snare is late AGAINST -- Charnas's conflict needs
    # something keeping straight time or there is nothing to conflict with, and
    # a bar where everything drags is slow.
    #
    # ONE GHOST, before the second backbeat, where a drummer's left hand goes.
    #
    # Swing 58 and humanize 5: further than the 55 and 2 the older presets use,
    # because this is modelled on hand-played pads with quantize off rather than
    # on a grid with a swing percentage applied to it.
    dillatime: {
      swing: 58, humanize: 5, bpm: 90, mode: :dilla_time,
      kicks: [0, 11], snares: [4, 12], hats: [0, 2, 6, 8, 10, 14],
      ghosts: [7], claps: [], perc: [],
    },
    dilla_slight: {
      swing: 55, humanize: 2, bpm: 95, mode: :dilla_time,
      kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 10], claps: [4, 12], perc: [3, 11],
    },
    # Transcribed from a 92 BPM Ableton set (4_seven): two Drum Racks, one
    # kick one DMX analog clap, both playing an identical 2-bar pattern. Kick
    # on the downbeat, the 16th right after it, and beat 3; clap on the plain
    # backbeat. Straight -- the set has no groove pool or shuffle on it, so the
    # swing here is minimal rather than the usual Dilla lean.
    four_seven: {
      swing: 52, humanize: 2, bpm: 92, mode: :straight_sixteenth,
      kicks: [0, 2, 8], snares: [4, 12], hats: [],
      ghosts: [], claps: [4, 12], perc: [],
    },
    dilla_drunk: {
      swing: 56, humanize: 4, bpm: 92, mode: :dilla_time,
      kicks: [0, 3, 6, 10, 13], snares: [4, 7, 12],
      hats: [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15],
      ghosts: [5, 14], claps: [12], perc: [2, 10, 15],
    },
    madlib_dusty: {
      swing: 56, humanize: 3, bpm: 93, mode: :dilla_time,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [1, 3, 5, 7, 9, 11, 13, 15],
      ghosts: [6, 14], claps: [4, 12], perc: [6, 14],
    },
    # Backbeat restored. This shipped with snares on [2, 6, 10, 15] -- no hit on
    # 4 or 12 anywhere -- which is the same fault the style constructions below
    # were first written with, and it is why this one did not read as hip-hop.
    # The abstraction stays in the kick and the near-continuous hats; the extra
    # snares moved to ghosts, where an off-backbeat hit belongs.
    wonky_abstract: {
      swing: 53, humanize: 4, bpm: 84, mode: :straight_sixteenth,
      kicks: [0, 5, 8, 13], snares: [4, 12],
      hats: [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15],
      ghosts: [2, 6, 10, 15], claps: [4, 12], perc: [1, 8],
    },
    mpc3000: {
      swing: 55, humanize: 2, bpm: 90, mode: :dilla_time,
      kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 9], claps: [4, 12], perc: [3, 11],
    },
    sp303: {
      swing: 54, humanize: 2, bpm: 96, mode: :dilla_time,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [1, 3, 5, 7, 9, 11, 13, 15],
      ghosts: [], claps: [], perc: [6, 14],
    },
    sp1200: {
      swing: 53, humanize: 1, bpm: 90, mode: :dilla_time,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [2, 10], claps: [4, 12], perc: [],
    },
    boom_808: {
      swing: 50, humanize: 1, bpm: 90, mode: :straight_sixteenth,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: (0..15).to_a,
      ghosts: [], claps: [4, 12], perc: [],
    },
    # Industrial techno: a four-on-floor anchor with displaced kicks, ghost
    # claps, ratcheted hats and off-grid percussion. The extra movement is
    # supplied by the synced eclectic/DFAM layers; this grid stays legible.
    # 128 BPM because the kick follows a techno tempo -- the operator's "kick-wise
    # maybe we could follow more of a techno tempo" -- and industrial is its own
    # album rather than hip-hop pads at hip-hop speed with a techno kit on them.
    industrial_techno: {
      swing: 50, humanize: 1, bpm: 128, mode: :straight_sixteenth,
      kicks: [0, 3, 4, 7, 8, 11, 12, 14], snares: [4, 12], hats: (0..15).to_a,
      ghosts: [2, 6, 10, 15], claps: [4, 12], perc: [1, 5, 9, 13, 15],
    },
    # The floor and nothing else. HATE/Detroit catalogue rows overlay this
    # name so a nine-second techno piece cannot wander into boom_808.
    techno_floor: {
      swing: 50, humanize: 1, bpm: 128, mode: :straight_sixteenth,
      kicks: [0, 4, 8, 12], snares: [4, 12], hats: [2, 6, 10, 14],
      ghosts: [], claps: [4, 12], perc: [6, 14],
    },
    # Transcribed from a D'Angelo reference track via learn_source! (onset
    # detection on the demucs drums.wav stem, step_grid in project/learnings/
    # last_learn.json) -- not hand-tuned, this is what the analysis measured.
    transcribed_soul_nine: {
      swing: 55, humanize: 3, bpm: 80, mode: :dilla_time,
      kicks: [0, 2, 3, 6, 7, 8, 9, 10, 12, 13, 14, 15], snares: [0, 2, 9], hats: [0, 4, 9],
      ghosts: [5, 11], claps: [2, 9], perc: [1, 7],
    },

    # ---- style constructions -------------------------------------------------
    # Everything below is BUILT to a described feel, not measured from a
    # recording. four_seven and transcribed_soul_nine above are transcriptions and are
    # the only two that can claim to be what a record actually plays; these are
    # arrangements in the manner of, and should not be cited as anyone's part.
    #
    # ONE RULE, learned the hard way: the backbeat stays on 4 and 12.
    #
    # The first version of this table put dilla_lopsided on snares [5, 13] and
    # wonky_cosmogramma on [5, 13] too, reasoning that an unusual feel needs an
    # unusual grid. That is wrong, and every transcription in this file says so:
    # dilla_slight, four_seven and wonky_camel are all [4, 12], as conventional
    # as a drum machine preset. What makes those records sound the way they do
    # is MICROTIMING_MS -- the snare arriving 10-28ms early, hats 12-32ms late,
    # kick almost on the grid -- measured in milliseconds, not in 16ths. Moving
    # the backbeat does not produce a drunk hip-hop beat, it produces a beat
    # that is not hip-hop. Character belongs in the kick placement, the ghosts,
    # and the swing; the backbeat is the thing the listener sets their clock by.
    #
    # humanize also stays in the references' 2-4 range. At 6 it stopped reading
    # as feel and started reading as an unsteady drummer.

    # Donuts-era Dilla: no hats at all. Half that record keeps time with the
    # sample's own noise and lets the kit be only kick and snare, which is why
    # those beats breathe where a hat pattern would tick.
    dilla_donuts: {
      swing: 55, humanize: 3, bpm: 88, mode: :dilla_time,
      kicks: [0, 7, 10], snares: [4, 12], hats: [],
      ghosts: [14], claps: [], perc: [],
    },
    # Slum Village pocket: swung, and the ghosts carry the groove rather than
    # the backbeat. Kick answers the snare on the "and" of 2 rather than
    # crowding it.
    dilla_fantastic: {
      swing: 56, humanize: 3, bpm: 94, mode: :dilla_time,
      kicks: [0, 6, 10, 11], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [7, 15], claps: [12], perc: [6],
    },
    # The lopsided one. Grid is ordinary on purpose -- kick on 1, the "and" of
    # 2, and beat 3; snare on the backbeat. Everything that makes it lean lives
    # in swing 66 against dilla_time, where MICROTIMING_MS pulls the snare early
    # and pushes the hats late while the kick sits near the grid. Three voices
    # disagreeing by milliseconds, which is the actual mechanism, rather than
    # three voices disagreeing about which 16th they are on, which is a
    # different pattern.
    dilla_lopsided: {
      swing: 56, humanize: 4, bpm: 90, mode: :dilla_time,
      kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [7, 15], claps: [4, 12], perc: [11],
    },

    # The Camel grid, moved here so every pattern lives in one table. dilla.rb
    # holds the same steps in POLY_TEMPORAL_DRUM_GRID for the dual-bus overlay.
    wonky_camel: {
      swing: 54, humanize: 3, bpm: 86, mode: :dilla_time,
      kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
      ghosts: [7], claps: [4, 12], perc: [],
    },
    # Cosmogramma: the HATS carry the cross-rhythm -- 3-step spacing across a
    # 16-step bar, so the last gap is 1 instead of 3 and the figure leans. The
    # kick and snare stay square underneath, which is what stops it sounding
    # like a mistake instead of a device.
    #
    # This is a cross-rhythm inside the bar, NOT a polymeter, and the note here
    # used to claim otherwise -- that the hats "only agree with the downbeat
    # once every three bars". They agree with it in every bar: the pool below
    # holds one entry, so drum_pattern_pick returns the identical list each time
    # and step 0 is in all of them. Nothing rotated it. Left as it is because
    # this is what the preset has always sounded like; the polymeter the old
    # note described is now real and reachable as POLYMETER_HATS=3, which lands
    # the 3-cycle on the global step and takes 3 bars to come back round.
    wonky_cosmogramma: {
      swing: 52, humanize: 4, bpm: 78, mode: :straight_sixteenth,
      kicks: [0, 6, 11], snares: [4, 12],
      hats: [0, 3, 6, 9, 12, 15], ghosts: [2, 14], claps: [4, 12], perc: [10],
    },
    # Half-time and mostly empty. The snare on 8 is beat 3, which IS the
    # backbeat when the bar is felt at half speed -- the one legitimate way the
    # snare leaves 4 and 12. Space is the instrument; this only works under
    # something that fills it.
    wonky_zodiac: {
      swing: 56, humanize: 3, bpm: 72, mode: :straight_sixteenth,
      kicks: [0, 11], snares: [8], hats: [4, 12],
      ghosts: [15], claps: [8], perc: [6],
    },
    # Loose and ambient, also half-time: snare on 8, kick answering it late.
    # No clap, hats sparse. Meant to sit under a drone rather than drive.
    wonky_massage: {
      swing: 58, humanize: 4, bpm: 68, mode: :straight_sixteenth,
      kicks: [0, 10], snares: [8], hats: [3, 7, 11, 15],
      ghosts: [5], claps: [], perc: [13],
    },

    # Broken-beat neo-soul. The break is in the ghosts and the kick, which
    # syncopate hard around a backbeat that never moves -- displacing the snare
    # itself was the first version's mistake and made it stop being a groove.
    hiatus_broken: {
      swing: 55, humanize: 4, bpm: 86, mode: :dilla_time,
      kicks: [0, 6, 8, 14], snares: [4, 12],
      hats: [0, 2, 3, 5, 6, 8, 10, 11, 13, 14], ghosts: [2, 7, 9, 15],
      claps: [4, 12], perc: [3, 11],
    },
    # Late-snare pocket. Nothing clever in the grid at all -- the entire feel is
    # in the snare arriving after you expect it, which is timing, not placement.
    questlove_pocket: {
      swing: 56, humanize: 3, bpm: 84, mode: :dilla_time,
      kicks: [0, 10], snares: [4, 12], hats: [0, 4, 8, 12],
      ghosts: [6, 14], claps: [], perc: [],
    },
    # Very sparse: a beat that sounds like someone else's beat heard through a
    # wall. Only the second backbeat is played -- leaving 4 silent is a choice
    # about what to omit, which is different from putting the snare somewhere
    # else, and the ear still counts the bar from 12.
    knxwledge_haze: {
      swing: 54, humanize: 4, bpm: 82, mode: :dilla_time,
      kicks: [0, 6, 10], snares: [12], hats: [2, 10],
      ghosts: [7], claps: [12], perc: [14],
    },

    # --- Five more in the Flying Lotus manner (BUILT, not transcribed) ---
    #
    # The five that were already here cluster in one place: sparse, 68-86 BPM,
    # kick-and-space. That is one Wonky and not the only one. These cover
    # territory the table had nothing for -- stuttered sub, live-drummer
    # density, half-time, a kick that refuses the downbeat, and warped tape.
    #
    # All keep the backbeat on [4, 12] except where omitting a hit is the
    # stated idea, for the reason argued at the top of this section: moving the
    # backbeat does not make a beat drunk, it makes it not hip-hop. Character
    # here is in kick placement, ghost density and swing. The millisecond layer
    # is WONKY_TIMING, which attaches to a track profile rather than to a drum
    # preset -- these presets deliberately carry no `timing:` key, because
    # DRUM_PRESETS entries are never consulted for it and a key that is silently
    # ignored is worse than none.

    # Stuttered sub: the kick doubles on consecutive 16ths so the low end
    # trips rather than lands. Hats stay plainly straight -- the whole event is
    # in the kick, and giving the hats a pattern too would bury it.
    wonky_burst: {
      swing: 54, humanize: 3, bpm: 82, mode: :straight_sixteenth,
      kicks: [0, 1, 6, 10, 11], snares: [4, 12],
      hats: [0, 2, 4, 6, 8, 10, 12, 14], ghosts: [7, 15], claps: [12], perc: [3],
    },

    # A live drummer's density, not a sampler's: hats on all sixteen as a ride
    # wash with ghosts filling every remaining gap, faster than anything else
    # in this table. Swing near 50 because a player pushing this hard plays
    # closer to straight, and the humanize does the rest.
    wonky_deantoni: {
      swing: 55, humanize: 4, bpm: 96, mode: :straight_sixteenth,
      kicks: [0, 3, 8, 11], snares: [4, 12],
      hats: (0..15).to_a, ghosts: [2, 6, 7, 10, 14, 15], claps: [], perc: [5, 13],
    },

    # Half-time: one backbeat in the bar at 8 instead of two at 4 and 12, so
    # the bar reads as half the tempo it is counted at. Hats sit only on the
    # offbeats, which leaves the downbeats to the sub.
    wonky_flamagra: {
      swing: 53, humanize: 3, bpm: 74, mode: :straight_sixteenth,
      kicks: [0, 3, 9], snares: [8], hats: [2, 6, 10, 14],
      ghosts: [12], claps: [8], perc: [15],
    },

    # After the downbeat the kick never lands on a beat again -- 7, 9 and 14
    # are all "e" and "a" positions. The backbeat is untouched, so the bar
    # stays legible while the low end argues with it.
    wonky_offbeat_kick: {
      swing: 54, humanize: 3, bpm: 80, mode: :dilla_time,
      kicks: [0, 7, 9, 14], snares: [4, 12],
      hats: [0, 2, 4, 6, 8, 10, 12, 14], ghosts: [3, 11], claps: [4, 12], perc: [6],
    },

    # Warped tape: heavy swing, and every hat on the "e" so the whole hat line
    # sits behind the beat it belongs to. Slowest of the five; the drag is the
    # point.
    wonky_warp: {
      swing: 54, humanize: 4, bpm: 70, mode: :dilla_time,
      kicks: [0, 6, 10, 13], snares: [4, 12], hats: [1, 5, 9, 13],
      ghosts: [2, 14], claps: [], perc: [8],
    },
  # ---- pack imports --------------------------------------------------------
  # A third provenance category, and the distinction is the point: these are
  # neither transcriptions of records (four_seven, transcribed_soul_nine) nor
  # constructions written to a description (everything above), but grids
  # extracted from MIDI supplied in a pack the operator licensed. Regenerate
  # with `ruby dilla.rb import-midi <dir>`.
  #
  # A different idiom from the rest of this table and worth having for that:
  # half-time, with the snare on 8 rather than 4 and 12, sparse kick clusters
  # and near-continuous 16th hats. Swing stays near straight because this
  # pocket does not want a lean -- the interest is in the kick placement.
  pack_729_1: {
    swing: 52, humanize: 2, bpm: 140, mode: :straight_sixteenth,
    kicks: [0, 2, 12, 13, 14], snares: [8], hats: [0, 4, 7, 8, 12, 14, 15],
    ghosts: [14, 15], claps: [8], perc: [4, 12],
  },
  pack_729_2: {
    swing: 52, humanize: 2, bpm: 140, mode: :straight_sixteenth,
    kicks: [0, 2, 4, 10, 14], snares: [8], hats: [0, 4, 6, 7, 8, 11, 12, 13, 15],
    ghosts: [2, 4, 14], claps: [8], perc: [12, 14],
  },
  pack_729_3: {
    swing: 52, humanize: 2, bpm: 140, mode: :straight_sixteenth,
    kicks: [0, 4, 6, 12, 14], snares: [8], hats: [0, 4, 8, 10, 11, 12, 13, 14, 15],
    ghosts: [12, 13, 15], claps: [8], perc: [4, 12],
  },
  pack_729_4: {
    swing: 52, humanize: 2, bpm: 140, mode: :straight_sixteenth,
    kicks: [0, 2, 4, 6, 8, 10], snares: [8], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [4, 5, 6, 7, 12, 13, 14, 15], claps: [8], perc: [12, 14],
  },
  pack_729_5: {
    swing: 52, humanize: 2, bpm: 140, mode: :straight_sixteenth,
    kicks: [0, 1, 2, 4, 6], snares: [8], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [6, 12, 13, 14, 15], claps: [8], perc: [4, 12],
  },
  pack_729_6: {
    swing: 52, humanize: 2, bpm: 140, mode: :straight_sixteenth,
    kicks: [0, 4, 14], snares: [8], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [6, 12], claps: [8], perc: [12, 14],
  },

  # ---- push pads -------------------------------------------------------------
  # Simple beats of the kind you get tapping pads: straight, sparse, no swing,
  # nothing clever. A deliberate counterweight to the rest of this table, which
  # is otherwise entirely devoted to making drums lean, drift and misbehave.
  # Sometimes the sample is the idea and the kit only has to keep time under it,
  # and there was nothing here that would do that.
  #
  # humanize 1 rather than 0: dead-flat machine timing is its own effect, and a
  # single tick of movement is the difference between simple and sterile.

# The Camel grid as MEASURED, not as simplified.
#
# project/learnings/wonky_drums/wonky_camel.json holds what a previous session
# got from a separated drum stem: kicks [0,3,6,10,13], ghost snares [7,15,10],
# perc [3,9,11], hat ghosts [1,3,5,9,11,13]. The shipped wonky_camel uses
# [0,6,10] / [7] / nothing, because the dense version "sounded wrong".
#
# That judgement was made before WONKY_TOP_DIRT existed. Accounts of how these
# drums are built say the extra hits are meant to be dirty and half-buried --
# phased, flanged, crushed -- not clean kit hits. A dense grid of clean hits
# is busy; the same grid through the dirt may be the texture. Kept as a
# separate preset so the two can be compared rather than one replacing the
# other on a hunch.
wonky_camel_measured: {
  swing: 54, humanize: 3, bpm: 86, mode: :dilla_time,
  kicks: [0, 3, 6, 10, 13], snares: [4, 12],
  hats: [0, 2, 4, 6, 8, 10, 12, 14],
  ghosts: [7, 10, 15], claps: [4, 12], perc: [3, 9, 11],
},

# Built from euclid rather than written by hand. The snare stays on 4 and 12
# in every one: Euclid sets density and placement of the kick, hats and perc,
# while the bar still turns where the ear expects.
euclid_tresillo: {
  swing: 55, humanize: 3, bpm: 88, mode: :dilla_time,
  kicks: [0, 3, 6], snares: [4, 12], hats: [0, 3, 5, 7, 10, 12, 14],
  ghosts: [9, 14], claps: [4, 12], perc: [0, 6],
},
euclid_cinquillo: {
  swing: 54, humanize: 3, bpm: 84, mode: :dilla_time,
  kicks: [0, 2, 3, 5, 6], snares: [4, 12], hats: [0, 3, 6, 9, 12],
  ghosts: [7, 15], claps: [4, 12], perc: [2, 10],
},
euclid_sparse: {
  swing: 53, humanize: 3, bpm: 80, mode: :straight_sixteenth,
  kicks: [0, 3, 6, 9, 12], snares: [8], hats: [0, 6, 12],
  ghosts: [14], claps: [8], perc: [3, 9],
},

  push_four: {
    swing: 50, humanize: 1, bpm: 90, mode: :straight_sixteenth,
    kicks: [0, 8], snares: [4, 12], hats: [0, 4, 8, 12],
    ghosts: [], claps: [4, 12], perc: [],
  },
  push_eight: {
    swing: 50, humanize: 1, bpm: 90, mode: :straight_sixteenth,
    kicks: [0, 6, 8], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [], claps: [4, 12], perc: [],
  },
  push_halftime: {
    swing: 50, humanize: 1, bpm: 84, mode: :straight_sixteenth,
    kicks: [0, 10], snares: [8], hats: [0, 4, 8, 12],
    ghosts: [], claps: [8], perc: [],
  },
  push_sparse: {
    swing: 50, humanize: 1, bpm: 88, mode: :straight_sixteenth,
    kicks: [0], snares: [8], hats: [4, 12],
    ghosts: [], claps: [8], perc: [],
  },

  # ---- expansion pack (constructed, backbeat-faithful) ---------------------
  # More distinct pockets without inventing "new" hip-hop by moving the snare.
  # Character is kick placement, ghost density, swing, and hat pattern only.

  # Classic boom-bap: kick on 1 + "and" of 2 + 3, busy hats, light ghosts.
  boom_bap: {
    swing: 55, humanize: 2, bpm: 92, mode: :dilla_time,
    kicks: [0, 6, 8], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [2, 10], claps: [4, 12], perc: [],
  },
  # Late kick answer after the backbeat — soul shuffle without relocating snare.
  soul_shuffle: {
    swing: 56, humanize: 3, bpm: 88, mode: :dilla_time,
    kicks: [0, 7, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [5, 13], claps: [12], perc: [3],
  },
  # Head-nod pocket: room for the sample; hats only on downbeats + backbeats.
  head_nod: {
    swing: 54, humanize: 2, bpm: 86, mode: :dilla_time,
    kicks: [0, 10], snares: [4, 12], hats: [0, 4, 8, 12],
    ghosts: [6, 14], claps: [], perc: [],
  },
  # Busy neo-soul: open hats implied via perc accents, dense ghosts.
  neo_busy: {
    swing: 55, humanize: 3, bpm: 90, mode: :dilla_time,
    kicks: [0, 3, 6, 10], snares: [4, 12],
    hats: [0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14],
    ghosts: [7, 11, 15], claps: [4, 12], perc: [2, 10],
  },
  # Crates: kick clusters on the last 16ths into the next bar.
  crate_dig: {
    swing: 54, humanize: 3, bpm: 94, mode: :dilla_time,
    kicks: [0, 6, 12, 13, 14], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [7, 15], claps: [4, 12], perc: [3],
  },
  # UK garage-ish: kick on 1 + snare backbeat + skippy hats (still 4/12 snare).
  uk_skip: {
    swing: 52, humanize: 2, bpm: 130, mode: :straight_sixteenth,
    kicks: [0, 6, 10], snares: [4, 12], hats: [0, 2, 3, 6, 8, 10, 11, 14],
    ghosts: [7], claps: [4, 12], perc: [5, 13],
  },
  # Trap half-time feel at hip-hop tempo: one strong snare on 8, hats 1/3.
  trap_half: {
    swing: 50, humanize: 1, bpm: 70, mode: :straight_sixteenth,
    kicks: [0, 7, 10], snares: [8], hats: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    ghosts: [], claps: [8], perc: [12],
  },
  # Afrobeat clave under a square backbeat — kick follows 3-2 tresillo.
  afro_clave: {
    swing: 52, humanize: 2, bpm: 100, mode: :straight_sixteenth,
    kicks: [0, 3, 6, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [7, 14], claps: [4, 12], perc: [0, 3, 6, 10],
  },
  # Samba-ish continuous 16ths with surdo-like kick accents.
  samba_pulse: {
    swing: 50, humanize: 2, bpm: 104, mode: :straight_sixteenth,
    kicks: [0, 7, 8, 14], snares: [4, 12], hats: (0..15).to_a,
    ghosts: [2, 6, 10, 14], claps: [], perc: [3, 5, 11, 13],
  },
  # Reggaeton dembow skeleton — snare still 4/12 so hip-hop clock holds.
  dembow_lite: {
    swing: 50, humanize: 1, bpm: 96, mode: :straight_sixteenth,
    kicks: [0, 6, 10], snares: [4, 12], hats: [0, 4, 8, 12],
    ghosts: [7, 14], claps: [4, 12], perc: [3, 11],
  },
  # Broken beat: kick stutters around an immovable backbeat.
  broken_kick: {
    swing: 54, humanize: 3, bpm: 84, mode: :dilla_time,
    kicks: [0, 1, 5, 8, 11, 14], snares: [4, 12],
    hats: [0, 2, 4, 6, 8, 10, 12, 14], ghosts: [3, 7, 9, 15], claps: [12], perc: [6],
  },
  # Jazz brush: sparse kick, soft ghost snare wash, light hats.
  jazz_brush: {
    swing: 56, humanize: 3, bpm: 78, mode: :dilla_time,
    kicks: [0, 10], snares: [4, 12], hats: [2, 6, 10, 14],
    ghosts: [1, 3, 5, 7, 9, 11, 13, 15], claps: [], perc: [],
  },
  # Footwork-adjacent double-time hats at mid tempo — kick still sparse.
  footwork_lite: {
    swing: 50, humanize: 2, bpm: 110, mode: :straight_sixteenth,
    kicks: [0, 8], snares: [4, 12], hats: (0..15).to_a,
    ghosts: [6, 14], claps: [4, 12], perc: [2, 10],
  },
  # Dilla "air" — almost no hats, kick answers late, room for vinyl.
  air_pocket: {
    swing: 55, humanize: 3, bpm: 88, mode: :dilla_time,
    kicks: [0, 11], snares: [4, 12], hats: [8],
    ghosts: [6, 14], claps: [], perc: [],
  },
  # SP-era chop pocket: kick on every beat, hats straight, snare backbeat.
  sp_chop: {
    swing: 53, humanize: 2, bpm: 96, mode: :dilla_time,
    kicks: [0, 4, 8, 12], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [3, 11], claps: [4, 12], perc: [6, 14],
  },
  # Gospel pocket: kick anticipates the snare ("and" of 1 into 2).
  gospel_pocket: {
    swing: 55, humanize: 2, bpm: 82, mode: :dilla_time,
    kicks: [0, 3, 8, 11], snares: [4, 12], hats: [0, 4, 8, 12],
    ghosts: [6, 14], claps: [4, 12], perc: [],
  },
  # Euclid 5-on-16 kick under standard backbeat.
  euclid_five: {
    swing: 54, humanize: 3, bpm: 86, mode: :dilla_time,
    kicks: [0, 3, 6, 10, 13], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [7, 15], claps: [4, 12], perc: [1, 9],
  },
  # Euclid 7-on-16 kick — denser low end, hats stay plain.
  euclid_seven: {
    swing: 53, humanize: 3, bpm: 88, mode: :dilla_time,
    kicks: [0, 2, 5, 7, 9, 12, 14], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [6, 10], claps: [4, 12], perc: [3, 11],
  },
  # Half-time soul: snare on 8 only (legitimate half-time backbeat).
  half_soul: {
    swing: 55, humanize: 3, bpm: 76, mode: :dilla_time,
    kicks: [0, 6, 11], snares: [8], hats: [0, 4, 8, 12],
    ghosts: [3, 14], claps: [8], perc: [],
  },
  # Machine four-on-floor for techno beds under soul pads.
  four_floor_soul: {
    swing: 50, humanize: 1, bpm: 118, mode: :straight_sixteenth,
    kicks: [0, 4, 8, 12], snares: [4, 12], hats: [2, 6, 10, 14],
    ghosts: [], claps: [4, 12], perc: [0, 8],
  },
  # Ghost-heavy MPC — almost all motion is soft hits.
  ghost_cloud: {
    swing: 56, humanize: 4, bpm: 90, mode: :dilla_time,
    kicks: [0, 10], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [1, 3, 5, 7, 9, 11, 13, 15], claps: [], perc: [6, 14],
  },
  # Push-and-pull: kick on the "a" of 2, snare locked.
  push_pull: {
    swing: 55, humanize: 3, bpm: 92, mode: :dilla_time,
    kicks: [0, 7, 8, 14], snares: [4, 12], hats: [0, 2, 4, 6, 8, 10, 12, 14],
    ghosts: [5, 13], claps: [4, 12], perc: [3],
  },
}.freeze

  LOFI_DEFAULTS = {
    bit_depth: 12, vinyl: 0.40, pad_lowpass_hz: 3200, master_lowpass_hz: 2800,
    pad_attack_ms: 800, pad_release_ms: 2000, pad_volume_pct: 40,
    filter_cutoff_hz: 12_000
  }.freeze

  DEFAULT_DRUM_PRESET = :dilla_slight
  DEFAULT_PAD_WAVE = :sine
  DEFAULT_PROFILE = :pedal_e_descent

  # Semantic harmony profiles — chord chemistry + groove family, no song names.
  BASE_HARMONY_PROFILES = {
    # Slum Village / Dilla — Get Dis Money (Ethan Hein exact E-pedal slash cycle).
    pedal_e_descent: {
      producer: :dilla, key: "E pedal", bpm: 92, swing: 54,
      chord_bars: 1, phrase_bars: 6, feel: :mpc3000, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[D/E Db/E C/E Bm/E Bbm/E Am/E], timing: DILLA_TIMING,
    },
    # Donuts "Time" researched core — IV–iii–vi–ii in Ab (clean 7ths).
    db_major_minor_fall: {
      producer: :dilla, key: "Ab / Fm", bpm: 90, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :timeless, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Dbmaj7 Cm7 Fm7 Bbm7], timing: DILLA_TIMING,
    },
    # Fall in Love = Diana in the Autumn Wind sample (Ebm7–Bbm7).
    eb_minor_two_chord: {
      producer: :dilla, key: "Eb minor", bpm: 91, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Ebm7fil Bbm7fil], timing: DILLA_TIMING,
    },
    e_major_third_rise: {
      producer: :dilla, key: "E major", bpm: 88, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :timeless, voicing: :rootless,
      drum_preset: :dilla_slight, chords: %w[Emaj7 G#m7 C#m7 E7climax], timing: DILLA_TIMING,
    },
    d_add9_soul_arc: {
      producer: :dilla, key: "D major", bpm: 92, swing: 56,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :rootless,
      drum_preset: :dilla_slight, chords: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9], timing: DILLA_TIMING,
    },
    # Classic Fm soul loop — i–iv–bVII–bVI (NOT artist-verified; experimental).
    soul: {
      producer: :dilla, key: "F minor", bpm: 88, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :timeless, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Fm9 Bbm9 Ebmaj9 Dbmaj9], timing: DILLA_TIMING,
    },
    # Same Time cycle with ninths.
    maj7_minor_cycle: {
      producer: :dilla, key: "Ab / Fm", bpm: 94, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :timeless, voicing: :rootless, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Dbmaj9 Cm9 Fm9 Bbm9], timing: DILLA_TIMING,
    },
    # Hooktheory Donuts "Time" — full IV–iii–vi–ii–V turnaround (8 bars).
    fourth_third_sixth_second_turn: {
      producer: :dilla, key: "Ab / Fm", bpm: 86, swing: 56,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight,
      chords: %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Bbm9 Ebmaj9], timing: DILLA_TIMING,
    },
    # Measured Fm engine loop — i–IV–iii–vi–ii–V–bVI–IV.
    timeless_authentic: {
      producer: :dilla, key: "F minor", bpm: 86, swing: 56,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight,
      chords: %w[Fm9 Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9], timing: DILLA_TIMING,
    },
    minor_iv_loop: {
      producer: :dilla, key: "F minor", bpm: 91, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Bbm Ab Fm7 Fm], timing: DILLA_TIMING,
    },
    major_lifting: {
      producer: :dilla, key: "E major", bpm: 96, swing: 53,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Emaj7 G#m7 G#m7 G#maj7], timing: DILLA_TIMING,
    },
    slash_ninth_cycle: {
      producer: :dilla, key: "C# minor", bpm: 90, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[C#m9 G#m9 A#7 C#maj9], timing: DILLA_TIMING,
    },
    two_chord_hypnosis: {
      producer: :dilla, key: "Eb minor", bpm: 92, swing: 57,
      chord_bars: 4, phrase_bars: 8, feel: :dilla_drunk, voicing: :spread,
      drum_preset: :dilla_drunk, chords: %w[Ebm7 Bbm7], timing: DILLA_TIMING,
    },
    relative_major_turn: {
      producer: :dilla, key: "G major", bpm: 88, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Cmaj9 Bm7 Am7 D7], timing: DILLA_TIMING,
    },
    minor_turnaround: {
      producer: :dilla, key: "G major", bpm: 90, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Bm7 Bm7 Cmaj9 Em7], timing: DILLA_TIMING,
    },
    warm_minor_arc: {
      producer: :dilla, key: "Bb / Dm", bpm: 86, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :madlib_dusty, voicing: :spread,
      drum_preset: :madlib_dusty, chords: %w[Dm7 Cm7 Fmaj9 Gm7], timing: DILLA_TIMING,
    },
    quartal_west_coast: {
      producer: :wonky, key: "C major", bpm: 86, swing: 54,
      chord_bars: 2, phrase_bars: 32, feel: :wonky_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true, intro_bars: 8,
      drum_preset: :wonky_abstract, chords: %w[Cmaj9 Am9 Fmaj9 G6], timing: WONKY_TIMING,
    },
    # Chromatic mediant drift profile.
    chromatic_mediant_drift: {
      producer: :wonky, key: "D minor", bpm: 86, swing: 54,
      chord_bars: 2, phrase_bars: 32, feel: :wonky_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true, intro_bars: 8,
      drum_preset: :wonky_abstract,
      chords: %w[Dm9 Cm11nc AbMaj13s11 Gm7 Eb7 A7nc Dmaj9nc DMaj7overG],
      timing: WONKY_TIMING,
    },
    slow_ballad_wash: {
      producer: :wonky, key: "G major", bpm: 81, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :wonky_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :wonky_abstract, chords: %w[G6 Em9 Cmaj9 Dmaj9], timing: WONKY_TIMING,
    },
    minor_triad_walk: {
      producer: :madlib, key: "D minor", bpm: 96, swing: 58,
      chord_bars: 2, phrase_bars: 8, feel: :sp303, voicing: :spread,
      drum_preset: :sp303, chords: %w[Dm Gm Am], timing: MADLIB_TIMING,
    },
    neo_soul_pocket: {
      producer: :dilla, key: "Dm", bpm: 93, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Dm7 Eb7 Gm7 Am7], timing: DILLA_TIMING,
    },
    neo_soul: {
      producer: :dilla, key: "F minor", bpm: 84, swing: 58,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread, stereo_pan: true,
      drum_preset: :dilla_slight,
      chords: %w[Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9 Cm9 C7b9 Fm9], timing: DILLA_TIMING,
    },
    dorian_iv_loop: {
      producer: :dilla, key: "G dorian", bpm: 90, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Gm9 Cmaj9 Fmaj9 Bbmaj7], timing: DILLA_TIMING,
    },
    backdoor_resolve: {
      producer: :dilla, key: "C minor", bpm: 88, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :rootless,
      drum_preset: :mpc3000, chords: %w[Fm7 Bb7 Ebmaj7 Abmaj7], timing: DILLA_TIMING,
    },
    iv_borrow_minor: {
      producer: :dilla, key: "A minor", bpm: 89, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :drop2,
      drum_preset: :dilla_slight, chords: %w[Am9 Dm9 Fmaj9 Em7], timing: DILLA_TIMING,
    },
    bvi_bvii_minor: {
      producer: :dilla, key: "E minor", bpm: 91, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_drunk, voicing: :spread,
      drum_preset: :dilla_drunk, chords: %w[Em7 Cmaj7 Dmaj7 Em7], timing: DILLA_TIMING,
    },
    ii_v_i_major: {
      producer: :dilla, key: "Bb major", bpm: 92, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :drop2,
      drum_preset: :mpc3000, chords: %w[Cm9 F7 Bbmaj9 Gm7], timing: DILLA_TIMING,
    },
    ii_v_i_minor: {
      producer: :dilla, key: "D minor", bpm: 90, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :rootless,
      drum_preset: :dilla_slight, chords: %w[Gm7 A7 Dm9 Cm7], timing: DILLA_TIMING,
    },
    gospel_bIII: {
      producer: :dilla, key: "F major", bpm: 94, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Fmaj9 Abmaj7 Bbmaj7 Fmaj9], timing: DILLA_TIMING,
    },
    flat_seven_lift: {
      producer: :dilla, key: "C major", bpm: 93, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :kenny_barron,
      drum_preset: :mpc3000, chords: %w[Cmaj9 Bbmaj7 Fmaj9 G6], timing: DILLA_TIMING,
    },
    warm_minor_vamp: {
      producer: :dilla, key: "F# minor", bpm: 87, swing: 58,
      chord_bars: 2, phrase_bars: 16, feel: :madlib_dusty, voicing: :bill_evans,
      drum_preset: :madlib_dusty, chords: %w[F#m9 Bm7 Emaj7 C#m7], timing: MADLIB_TIMING,
    },
    modern_quartal_stack: {
      producer: :wonky, key: "Eb major", bpm: 82, swing: 52,
      chord_bars: 2, phrase_bars: 16, feel: :wonky_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true,
      drum_preset: :wonky_abstract, chords: %w[Ebmaj9 Cm9 Abmaj9 Bb6], timing: WONKY_TIMING,
    },
    funk_sixteenth_turn: {
      producer: :dilla, key: "G minor", bpm: 88, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Gm9 Cm7 Fmaj9 Bbmaj7], timing: DILLA_TIMING,
    },
    church_sus: {
      producer: :dilla, key: "Db major", bpm: 86, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Dbmaj9 Gbmaj7 Ab6 Dbmaj9], timing: DILLA_TIMING,
    },
    minMaj_color: {
      producer: :madlib, key: "C minor", bpm: 85, swing: 57,
      chord_bars: 2, phrase_bars: 8, feel: :sp303, voicing: :cluster,
      drum_preset: :sp303, chords: %w[Cm7 Abmaj7 G7 Ebmaj7], timing: MADLIB_TIMING,
    },
    dominant_turn: {
      producer: :dilla, key: "A minor", bpm: 92, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :drop3,
      drum_preset: :dilla_slight, chords: %w[Am9 D7 Gmaj7 E7], timing: DILLA_TIMING,
    },
    deceptive_turn: {
      producer: :dilla, key: "E minor", bpm: 89, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :rootless,
      drum_preset: :mpc3000, chords: %w[Em9 B7 Cmaj9 Am9], timing: DILLA_TIMING,
    },
    plagal_jazz: {
      producer: :dilla, key: "F major", bpm: 90, swing: 53,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Fmaj9 Bbmaj7 Cmaj9 Fmaj9], timing: DILLA_TIMING,
    },
    slash_neo_soul: {
      producer: :dilla, key: "Bb major", bpm: 91, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :so_what,
      drum_preset: :dilla_slight, chords: %w[Dm7/F Fmaj9/A Gm7/Bb Cmaj9/E], timing: DILLA_TIMING,
    },
    suspended_ballad: {
      producer: :wonky, key: "D major", bpm: 78, swing: 55,
      chord_bars: 4, phrase_bars: 16, feel: :wonky_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :wonky_abstract, chords: %w[Dmaj9 Am9 Gmaj9], timing: WONKY_TIMING,
    },
    minor_line_cliche: {
      producer: :dilla, key: "A minor", bpm: 88, swing: 54,
      chord_bars: 1, phrase_bars: 8, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Am Am/G Fmaj7 E7], timing: DILLA_TIMING,
    },
    stark_minor_pair: {
      producer: :dilla, key: "F minor", bpm: 95, swing: 58,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_drunk, voicing: :drop2,
      drum_preset: :dilla_drunk, chords: %w[Fm7 Abmaj7 Bbm7 Fm7], timing: DILLA_TIMING,
    },
    piano_soul_turn: {
      producer: :dilla, key: "Eb major", bpm: 84, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :madlib_dusty, voicing: :kenny_barron,
      drum_preset: :madlib_dusty, chords: %w[Ebmaj9 Cm9 Fm7 Bb7], timing: MADLIB_TIMING,
    },
    jazz_ballad_waltz: {
      producer: :wonky, key: "Ab major", bpm: 72, swing: 52,
      chord_bars: 2, phrase_bars: 16, feel: :wonky_abstract, voicing: :bill_evans,
      stereo_pan: true,
      drum_preset: :wonky_abstract, chords: %w[Abmaj9 Fm7 Bbm7 Eb7], timing: WONKY_TIMING,
    },
    turnaround_ii_v: {
      producer: :dilla, key: "G major", bpm: 91, swing: 55,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :drop2,
      drum_preset: :dilla_slight, chords: %w[Am7 D7 Gmaj9 Bm7], timing: DILLA_TIMING,
    },
    modal_safe: {
      producer: :dilla, key: "D Mixolydian", bpm: 89, swing: 54,
      chord_bars: 2, phrase_bars: 8, feel: :mpc3000, voicing: :quartal,
      drum_preset: :mpc3000, chords: %w[Dmaj9 Cmaj9 Gmaj9 A7], timing: DILLA_TIMING,
    },
    neo_iv_cycle: {
      producer: :dilla, key: "C minor", bpm: 90, swing: 56,
      chord_bars: 2, phrase_bars: 8, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight, chords: %w[Cm9 Fm7 Bbmaj7 Ebmaj9], timing: DILLA_TIMING,
    },
    # Raymond Scott Electronium × Dilla — Common "The Light" neo-soul cycle.
    electronium_loop: {
      producer: :dilla, key: "F minor", bpm: 86, swing: 57,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread, quintuplet: true,
      drum_preset: :dilla_slight, chords: %w[Fm9 Dbmaj9 Eb9 Bbm9 Cm7b5 Fm9 C7alt Fm9],
      timing: DILLA_TIMING,
    },
    electronium_classic: {
      producer: :dilla, key: "F minor", bpm: 86, swing: 57,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread,
      drum_preset: :mpc3000, chords: %w[Fm7 Dbmaj7 Eb7 Bbm7 Cm7b5 Fm7 C7 Fm7],
      timing: DILLA_TIMING,
    },
    # Aydin Esen — quartal modal wash (Bill Evans / Turkish jazz lineage).
    modal_quartal_ladder: {
      producer: :dilla, key: "C minor", bpm: 82, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :quartal,
      drum_preset: :dilla_slight,
      chords: %w[Cm9 Fmaj9 Bbmaj9 Ebmaj9 Abmaj7 Dm9 Bb7sus Cm9], timing: DILLA_TIMING,
    },
    # Aydin Esen — ii–V chains with altered dominants and rich extensions.
    minor_two_five_chain: {
      producer: :dilla, key: "Bb major", bpm: 88, swing: 53,
      chord_bars: 2, phrase_bars: 16, feel: :mpc3000, voicing: :bill_evans,
      drum_preset: :mpc3000,
      chords: %w[Dm9 Gm9 C7b9 Fmaj9 Bbm9 Eb9 Abmaj9 Dm9], timing: DILLA_TIMING,
    },
    # Bach — circle-of-fifths descent (functional voice-leading).
    circle_fifths_descent: {
      producer: :dilla, key: "A minor", bpm: 76, swing: 52,
      chord_bars: 1, phrase_bars: 8, feel: :mpc3000, voicing: :drop2,
      drum_preset: :mpc3000,
      chords: %w[Am9 Dm9 G7 Cmaj9 Fmaj9 Bm7b5 E7b9 Am9], timing: DILLA_TIMING,
    },
    # Bach — descending bass (passacaglia motion) in neo-soul voicings.
    walking_bass_descent: {
      producer: :dilla, key: "D minor", bpm: 80, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :kenny_barron,
      drum_preset: :dilla_slight,
      chords: %w[Dm9 Dm/C Bbmaj9 A7 Dm9 Gm9 Cmaj9 Fmaj9], timing: DILLA_TIMING,
    },
    # --- Expansion pack ---
    # Informed by functional voice-leading (common tones, stepwise outer voices),
    # Donuts-era harmonic economy (short loops, borrowed color, human pocket),
    # and analog pad craft (Prophet/Moog sustain, Crane-Song-style soft saturation).
    # "Good progression" criteria: home-away-home, ≤2–3 shared tones between
    # neighbors when possible, one surprise per 4 bars, return by bar 8–16.
    lydian_glass_cycle: {
      producer: :dilla, key: "F Lydian-leaning", bpm: 88, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :wonky_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :wonky_abstract,
      chords: %w[Fmaj9 Am9 Gmaj9 Em9 Fmaj9 Dm9 Cmaj9 G7], timing: WONKY_TIMING,
    },
    pedal_upper_structures: {
      producer: :dilla, key: "C pedal", bpm: 84, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread,
      drum_preset: :dilla_slight,
      chords: %w[Cm9 C7sus Ab/C F/C Bbmaj9/C Gm7/C Dbmaj9/C Cm9], timing: DILLA_TIMING,
    },
    bossa_major9_turn: {
      producer: :dilla, key: "F major", bpm: 92, swing: 56,
      chord_bars: 2, phrase_bars: 16, feel: :dilla_slight, voicing: :bill_evans,
      drum_preset: :dilla_slight,
      chords: %w[Fmaj9 Em7b5 A7b9 Dm9 Gm9 C7sus Fmaj9 D7], timing: DILLA_TIMING,
    },
    phrygian_gold_arc: {
      producer: :dilla, key: "E minor / Phrygian color", bpm: 90, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :mpc3000, voicing: :spread,
      drum_preset: :mpc3000,
      chords: %w[Em9 Fmaj9 Gmaj9 Am9 Fmaj7 G7sus Bm7b5 Em9], timing: DILLA_TIMING,
    },
    two_chord_luminous: {
      producer: :dilla, key: "Db / Fm", bpm: 78, swing: 54,
      chord_bars: 4, phrase_bars: 16, feel: :wonky_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :wonky_abstract,
      chords: %w[Dbmaj9 Fm9], timing: WONKY_TIMING,
    },
    mixo_sus_loop: {
      producer: :dilla, key: "D Mixolydian", bpm: 96, swing: 53,
      chord_bars: 1, phrase_bars: 8, feel: :mpc3000, voicing: :quartal,
      drum_preset: :mpc3000,
      chords: %w[Dmaj9 Cmaj9 Gmaj9 Dmaj9 F#m9 Em9 A7sus Dmaj9], timing: DILLA_TIMING,
    },
    common_tone_drift: {
      producer: :wonky, key: "E common-tone field", bpm: 86, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :wonky_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true,
      drum_preset: :wonky_abstract,
      chords: %w[Em9 Cmaj9 Am9 Fmaj9 Em9 Gmaj9 Bm9 Em9], timing: WONKY_TIMING,
    },
    third_cycle_triads: {
      producer: :dilla, key: "F minor stations", bpm: 82, swing: 54,
      chord_bars: 2, phrase_bars: 16, feel: :timeless, voicing: :spread,
      drum_preset: :dilla_slight,
      chords: %w[Fm9 Abmaj9 Bmaj9 Fm9 Dbmaj9 Emaj9 Abmaj9 Fm9], timing: DILLA_TIMING,
    },
    drone_quartal_wash: {
      producer: :wonky, key: "D drone", bpm: 80, swing: 52,
      chord_bars: 4, phrase_bars: 16, feel: :wonky_abstract, voicing: :quartal,
      stereo_pan: true, sidechain: true,
      drum_preset: :wonky_abstract,
      chords: %w[Dm9 G/D C/D Am9 Dm9 Fmaj9/D G/D Dm9], timing: WONKY_TIMING,
    },
    waltz_relative_lift: {
      producer: :dilla, key: "C minor → Eb", bpm: 72, swing: 52,
      chord_bars: 2, phrase_bars: 16, feel: :wonky_abstract, voicing: :bill_evans,
      stereo_pan: true,
      drum_preset: :wonky_abstract,
      chords: %w[Cm9 Abmaj9 Bb7 Ebmaj9 Fm9 Bb7 Ebmaj9 G7], timing: WONKY_TIMING,
    },
    half_time_gospel_plagal: {
      producer: :dilla, key: "Bb major", bpm: 74, swing: 54,
      chord_bars: 4, phrase_bars: 16, feel: :dilla_slight, voicing: :spread,
      drum_preset: :dilla_slight,
      chords: %w[Bbmaj9 Ebmaj9 Abmaj9 F7sus Bbmaj9 Ebmaj9 F7sus Bbmaj9], timing: DILLA_TIMING,
    },
    double_time_pocket: {
      producer: :dilla, key: "E minor", bpm: 108, swing: 56,
      chord_bars: 1, phrase_bars: 8, feel: :dilla_drunk, voicing: :spread,
      drum_preset: :dilla_drunk,
      chords: %w[Em9 Am9 D7 Gmaj9 Em9 Am9 D7 Gmaj9], timing: DILLA_TIMING,
    },
    whole_tone_bridge: {
      producer: :wonky, key: "whole-tone → F minor", bpm: 88, swing: 54,
      chord_bars: 1, phrase_bars: 8, feel: :wonky_abstract, voicing: :cluster,
      drum_preset: :wonky_abstract,
      chords: %w[C7 D7 E7 F#7 Fm9 Dbmaj9 Ebmaj9 Fm9], timing: WONKY_TIMING,
    },
    upper_triad_tower: {
      producer: :dilla, key: "Bb tower", bpm: 90, swing: 55,
      chord_bars: 2, phrase_bars: 16, feel: :mpc3000, voicing: :so_what,
      drum_preset: :mpc3000,
      chords: %w[Bbmaj9 D/Bb F/Bb G/Bb Bbmaj9 Eb/Bb F/Bb Bbmaj9], timing: DILLA_TIMING,
    },
    minor_add9_lullaby: {
      producer: :dilla, key: "G minor", bpm: 70, swing: 53,
      chord_bars: 4, phrase_bars: 16, feel: :wonky_abstract, voicing: :spread,
      stereo_pan: true, sidechain: true,
      drum_preset: :wonky_abstract,
      chords: %w[Gm9 Ebmaj9 Cm9 D7sus Gm9 Ebmaj9 Fmaj9 Gm9], timing: WONKY_TIMING,
    },
    dominant_chain_home: {
      producer: :dilla, key: "circle of fifths 7ths", bpm: 94, swing: 54,
      chord_bars: 1, phrase_bars: 8, feel: :mpc3000, voicing: :drop2,
      drum_preset: :mpc3000,
      chords: %w[C7 F7 Bb7 Eb7 Abmaj9 Dbmaj9 Cm9 F7], timing: DILLA_TIMING,
    },
  }.freeze

  # Additive entries merged in rather than hand-typed here so the sourcing stays
  # in one place: dilla_reference.yml (documented Slum Village / Flying Lotus
  # track analysis) and free_midi_chords.yml (mood-tagged progressions converted
  # from ldrolez/free-midi-chords, MIT). Existing named profiles above are never
  # overwritten by these.
  def self.load_documented_progressions
    paths = [
      File.expand_path("../data/dilla_reference.yml", __dir__),
      File.expand_path("../free_midi_chords.yml", __dir__),
    ].select { |candidate| File.file?(candidate) }
    return {} if paths.empty?

    entries = paths.each_with_object({}) do |candidate, acc|
      acc.merge!(YAML.safe_load_file(candidate)["documented_progressions"] || {})
    end
    entries.each_with_object({}) do |(key, e), out|
      producer = e["producer"].to_sym
      wonky = producer == :wonky
      out[key.to_sym] = {
        producer:, key: e["key"], bpm: e["bpm"], swing: e["swing"],
        chord_bars: e["chord_bars"], phrase_bars: e["phrase_bars"],
        voicing: e["voicing"].to_sym,
        feel: wonky ? :wonky_abstract : :timeless,
        drum_preset: wonky ? :wonky_abstract : :dilla_slight,
        chords: e["chords"],
        timing: wonky ? WONKY_TIMING : DILLA_TIMING
      }
    end
  rescue StandardError, Psych::Exception => e
    warn "documented progressions not loaded (#{e.message})"
    {}
  end

  HARMONY_PROFILES = BASE_HARMONY_PROFILES.merge(load_documented_progressions).freeze

  # Old track ids → semantic profile (backward compat only).
  LEGACY_ALIASES = {
    timeless: :db_major_minor_fall,
    players: :neo_soul_pocket,
    neo_soul: :neo_soul,
    slash_ninth_cycle: :pedal_e_descent,
    thelonious: :two_chord_hypnosis,
    selfish: :relative_major_turn,
    look_of_love: :minor_turnaround,
    so_far_to_go: :warm_minor_arc,
    wonky_camel: :chromatic_mediant_drift,
    wonky_roberta: :slow_ballad_wash,
    madlib_accordion: :minor_triad_walk,
    long_soul: :maj7_minor_cycle,
    golden: :neo_soul,
  }.freeze

  # Full stream rotation — verified Dilla/SV/D'Angelo songs first, then the
  # broader curated harmony pack so stream/demo cycles progressions + colors.
  STREAM_ROTATION = %w[
    pedal_e_descent db_major_minor_fall eb_minor_two_chord e_major_third_rise d_add9_soul_arc
    maj7_minor_cycle
    neo_soul_pocket warm_minor_vamp warm_minor_arc minor_turnaround
    quartal_west_coast slash_ninth_cycle dorian_iv_loop gospel_bIII
    minor_iv_loop two_chord_hypnosis relative_major_turn
    electronium_loop fourth_third_sixth_second_turn
    chromatic_mediant_drift lydian_glass_cycle pedal_upper_structures
    bossa_major9_turn phrygian_gold_arc mixo_sus_loop common_tone_drift
    modern_quartal_stack minMaj_color church_sus jazz_ballad_waltz
    two_chord_luminous third_cycle_triads drone_quartal_wash waltz_relative_lift
    half_time_gospel_plagal double_time_pocket whole_tone_bridge upper_triad_tower
    minor_add9_lullaby dominant_chain_home
    minor_two_five_chain modal_quartal_ladder circle_fifths_descent walking_bass_descent
    backdoor_resolve bvi_bvii_minor deceptive_turn dominant_turn stark_minor_pair
    electronium_classic ii_v_i_major ii_v_i_minor iv_borrow_minor piano_soul_turn
    major_lifting minor_line_cliche minor_triad_walk modal_safe neo_iv_cycle
    neo_soul plagal_jazz slash_neo_soul slow_ballad_wash soul flat_seven_lift
    suspended_ballad timeless_authentic turnaround_ii_v funk_sixteenth_turn
  ].freeze
  # HARMONY_PROFILES also carries a handful of *_documented entries (sourced
  # from dilla_reference.yml) -- literal reference transcriptions, not
  # deliberately excluded here so stream/demo rotation stays generative
  # rather than replaying citation-grade transcriptions verbatim.

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
    # The drum kit only supplies tempo and swing when the harmony profile has
    # not stated its own. It used to overwrite them unconditionally, which is
    # backwards for the documented entries out of dilla_reference.yml: tempo and
    # swing are most of what a transcription exists to preserve, and
    # slum_village_players_documented (91 BPM, 56% swing) and
    # wonky_camel_documented (86, 54) both rendered at the generic kit's 95 with
    # the kit's swing. The transcriptions were present and loading correctly the
    # whole time; they were being played at someone else's tempo.
    preset[:swing] = drum[:swing] if drum && !ENV["SWING"] && !entry[:swing]
    preset[:bpm] = drum[:bpm] if drum && !ENV["BPM"] && !entry[:bpm]
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

  # Root / third / seventh a symbol must actually contain. Fifths are fair game
  # to drop when thinning a voicing -- a rootless 9-3-13-b7 with no fifth is a
  # normal jazz voicing, not a broken one -- but the third and seventh are what
  # make the chord that chord.
  #
  # The named extension counts too. A "9" chord whose ninth is missing or
  # altered is a different chord: the gem answered Am9 as A C E G Bb, a MINOR
  # ninth, and every m9 in the engine that is not hardcoded in CHORD_VOICINGS
  # came back the same way -- Bm9, C#m9, Dm9, Em9, F#m9, G#m9, Gm9, eight of
  # eight. Root, b3 and b7 were all present, so the old three-tone check passed
  # it and the pad played a semitone cluster at the top. Whatever names the
  # chord has to be verified, or this check only catches the errors nobody was
  # going to make.
  CORE_TONES = {
    "maj7" => [0, 4, 11], "maj9" => [0, 4, 11, 2], "maj9low" => [0, 4, 11, 2],
    "m7" => [0, 3, 10], "m9" => [0, 3, 10, 2], "m11" => [0, 3, 10, 5], "m7b5" => [0, 3, 6, 10],
    "7" => [0, 4, 10], "7b9" => [0, 4, 10, 1], "7alt" => [0, 4, 10],
    "7sus" => [0, 5, 10], "7sus4" => [0, 5, 10],
    "6" => [0, 4], "m" => [0, 3], "" => [0, 4],
    # Absent entirely until now, and the table failed OPEN -- an unlisted
    # suffix returned "sane" without looking at a single note. That is how
    # Bb13 reached a render as Eb F G Ab Bb: no third at all, an eleventh
    # standing where the third belongs, five adjacent scale tones.
    "13" => [0, 4, 10, 9], "maj13" => [0, 4, 11, 9], "maj13#11" => [0, 4, 11, 9],
    "7#11" => [0, 4, 10, 6], "maj7#11" => [0, 4, 11, 6],
    "9" => [0, 4, 10, 2], "add9" => [0, 4, 2], "sus9" => [0, 5, 2],
    "7#5" => [0, 4, 10, 8], "sus2" => [0, 2, 7],
    "m6" => [0, 3, 9], "mmaj7" => [0, 3, 11], "sus" => [0, 5, 7], "sus4" => [0, 5, 10],
    "min" => [0, 3], "maj" => [0, 4],
    # No third by definition — the 4th, the b7 and the 9 are what must survive.
    "9sus4" => [0, 5, 10, 2], "9sus" => [0, 5, 10, 2],
    # A symmetrical chord is nothing but its symmetry: a diminished triad with
    # a natural fifth in it, or an augmented one, is a minor or major
    # triad wearing the wrong name.
    "dim" => [0, 3, 6], "dim7" => [0, 3, 6, 9], "aug" => [0, 4, 8],
    "maj7#5" => [0, 4, 8, 11],
  }.freeze

  # The major_third_cycle_full gem hands back confidently wrong voicings for several
  # suffixes: "Bbmaj9" comes back as Bb Db F Ab C -- a MINOR ninth -- "C7sus"
  # as C E G B, a maj7 carrying the exact third the suspension exists to
  # remove, and "Eb9" with no b7 at all. Nothing downstream noticed because a
  # chord came back and it had the right root name. Verify the gem's answer
  # contains the tones the symbol asks for, and fall through to the built-in
  # suffix parser when it does not.
  def gem_chord_sane?(sym, chord)
    return false unless chord.is_a?(Hash) && chord[:hz].is_a?(Array) && chord[:hz].any?
    m = sym.to_s.match(/\A([A-G][#b]?)(.*)\z/) or return true
    # A slash symbol is not this method's business -- the branch below builds it
    # from its two halves -- and the gem answers nil or hangs on all of them.
    return true if m[2].include?("/")

    # Fail CLOSED. An unlisted suffix used to return "sane" without looking at
    # a note, which is the opposite of what a sanity check is for; the built-in
    # suffix parser below has a template for every suffix in CHORD_SUFFIXES and
    # is the better answer whenever this table cannot judge.
    sfx = m[2].sub(/low\z/i, "")
    want = CORE_TONES[sfx] or return false
    pc = NOTE_PC[m[1]] or return false
    got = chord[:hz].map { |h| (69.0 + (12.0 * Math.log2(h / 440.0))).round % 12 }.uniq
    return false unless want.all? { |iv| got.include?((pc + iv) % 12) }

    # Having every tone the symbol asks for is only half the question; the other
    # half is having nothing it did not. The gem hands back a SIX-note m11 with
    # a flat ninth stapled on -- Fm11 came out F Gb Ab Bb Eb, a b9 standing
    # where the fifth belongs -- and the core-tone check above waved it through
    # because all four tones it looks for were present somewhere in the pile.
    # A chord with an uninvited semitone against its own root is not the chord
    # that was asked for, whatever else it contains.
    #
    # Only judged when the built-in table knows the quality outright:
    # quality_for_suffix falls back to "maj9" for anything it cannot place, and
    # measuring a chord against the wrong template would reject good voicings.
    quality = QUALITY_ALIASES[sfx.downcase] || sfx.downcase
    template = CHORD_TEMPLATES[quality] or return true
    allowed = template.map { |iv| (pc + iv) % 12 }
    (got - allowed).empty?
  end

  # Transcription shorthand, not chord quality. Eight symbols in the profile
  # tables carry an annotation the parser has no template for -- "nc", "fil",
  # "e_major_third_rise", "over", "s11" -- and progression_for's `rescue ArgumentError; nil`
  # dropped every one of them silently. chromatic_mediant_drift lost five of its
  # eight chords that way and eb_minor_two_chord lost both of its two, returning nil.
  # The chord is written right there in front of the annotation; keeping it is
  # strictly better than losing a bar of harmony to a suffix nobody parsed.
  def normalize_chord_symbol(sym)
    sym.to_s.strip
       .sub(/over([A-G][#b]?)\z/i) { "/#{Regexp.last_match(1)}" }
       .sub(/s11\z/i, "#11")
       .sub(/(?:nc|fil|e_major_third_rise)\z/i, "")
  end

  # A suffix names its own template unless it is spelled differently there.
  #
  # This was 26 case arms, 21 of which mapped a suffix to the identically named
  # CHORD_TEMPLATES key -- so adding a chord quality meant editing the table and
  # then remembering to edit a case arm that said nothing, and forgetting the arm
  # voiced the new quality as maj9 with no error. Only the five genuine spelling
  # differences need stating:
  #
  #   7sus/7sus4 -> sus4, because plain "7" is [0,4,7,10] and the one thing a
  #     suspended chord must not contain is the third (C7sus came out C E G Bb).
  #   "" -> maj, a bare triad stays a plain triad: these appear almost only as
  #     the upper structure of a slash chord (D/Bb, G/D), where the whole point
  #     is a clean triad over a foreign bass, and voicing it as maj9 piles on a
  #     7th and 9th that fight the bass note.
  #   m -> m9, maj9low -> maj9 (the "low" is a register, not a quality).
  #
  # Unknown suffixes still fall back to maj9, as build_voicing does for a
  # quality with no template.
  QUALITY_ALIASES = { "maj9low" => "maj9", "7sus4" => "sus4", "7sus" => "sus4",
                      "m" => "m9", "" => "maj" }.freeze

  def quality_for_suffix(suffix)
    sfx = suffix.downcase
    QUALITY_ALIASES[sfx] || (CHORD_TEMPLATES.key?(sfx) ? sfx : "maj9")
  end

  def pitch_class_of(hz)
    (69.0 + (12.0 * Math.log2(hz / 440.0))).round % 12
  end

  # A slash chord is its upper structure over a foreign bass, capped at the pad's
  # voice count -- so one voice has to go, and which one is the whole question.
  #
  # The rule was `.sort.uniq.first(5)`: trim from the top, on the reasoning that
  # the top voice is a padded octave doubling. That holds for a four-note template
  # padded up to five and fails for every five-note ninth voicing, where the top
  # voice IS the ninth the chord is named after. Measured before this change:
  # Cm9/Bb came out Bb2 C3 Eb3 G3 Bb3 -- a Cm7 over Bb, Bb doubled, no D anywhere
  # -- and Cmaj9/G lost its D, Gm9/G its A. Those spellings are most of
  # stepwise_bass, descending_bass_soul, chromatic_bass_walk and
  # pedal_dominant_hold, so the ninth that defines the sound was absent from the
  # progressions built entirely out of it.
  #
  # Drop what a player drops: first a voice doubling the bass's pitch class, then
  # the fifth, then the lowest inner voice. The bass and the top voice always
  # survive.
  #
  # root_pc has to be told, not guessed. Read off the lowest note it is only
  # the root in root position -- and the voicings that reach here
  # are routinely inverted. Abmaj9 arrives as C Eb G Ab Bb, so "lowest note" said
  # C, "the fifth above C" said G, and G is Ab's MAJOR SEVENTH: Abmaj9/F and
  # Ebmaj9/C were each losing the one interval that separates a maj9 from a 6/9,
  # in the name of leaving out a fifth that was still sitting there afterwards.
  def trim_slash_voicing(bass_hz, upper_hz, voices: 5, root_pc: nil)
    upper = upper_hz.sort
    drops = upper.length + 1 - voices
    return ([bass_hz] + upper).sort if drops <= 0

    bass_pc = pitch_class_of(bass_hz)
    root_pc ||= pitch_class_of(upper.first)
    seen = {}
    upper.each { |h| seen[pitch_class_of(h)] = (seen[pitch_class_of(h)] || 0) + 1 }
    # Rank by what the note IS, not by where it sits. Protecting the top voice
    # unconditionally was a proxy for protecting the ninth, and it stopped being
    # one the moment a voicing arrived with something else up there: Ebmaj9 comes
    # back as D Eb F G Bb, fifth on top and major seventh at the bottom, so the
    # rule shielded the one tone a player drops first and spent the cut on the
    # tone that names the chord. The fifth is expendable in any octave; the third,
    # the seventh and the extensions are expendable in none.
    removed = upper.sort_by do |h|
      pc = pitch_class_of(h)
      interval = (pc - root_pc) % 12
      rank = if pc == bass_pc || seen[pc] > 1
               0 # a doubling: the bass already plays it, or the stack does
             elsif interval == 7
               1 # the fifth, the first chord tone a player leaves out
             elsif interval.zero?
               2 # the root: the bass anchors the chord and the ear supplies it
             else
               3 # third, seventh, ninth -- what the symbol is actually named for
             end
      # A doubling: take the higher copy, so the shape keeps its lower anchor.
      # A real chord tone: take the lowest inner voice, which is the one crowding
      # the bass.
      [rank, rank.zero? ? -h : h]
    end.first(drops)
    ([bass_hz] + (upper - removed)).sort
  end

  # Memoised, and slash chords resolve before the gem is consulted.
  #
  # Both because the gem hangs, not just occasionally but reliably, on bare minor
  # uppers: DillaMusicGems.chord_from_symbol("Bm") never returns (measured past
  # 120s), so every such symbol burns the whole Timeout(1.5) budget, and a slash
  # chord burns it twice — once for "Bm/E", once for the recursive "Bm".
  # pedal_e_descent's six chords are D/E Db/E C/E Bm/E Bbm/E Am/E, which cost
  # progression_for 6.4s and beautify_curated_pipeline 11.3s per render, for
  # answers that never varied. Hoisting the slash branch above the gem block
  # takes Am/E from 1609ms to 0.02ms; the memo takes the whole progression to 0ms
  # after the first parse.
  #
  # This got hotter in the same change set that added it: curated_progression?
  # now routes documented transcriptions through beautify_curated_pipeline.
  #
  # CHORD_VOICINGS' lookup stays first — it holds exactly one slash key (Fm/C)
  # and that hand-written voicing should still win.
  def chord_from_symbol(sym)
    sym = normalize_chord_symbol(sym)
    @chord_symbol_cache ||= {}
    if (cached = @chord_symbol_cache[sym])
      # dup the array: callers voice-lead and transpose these in place.
      return cached.merge(hz: cached[:hz].dup)
    end

    chord = uncached_chord_from_symbol(sym)
    @chord_symbol_cache[sym] = chord if chord
    chord
  end

  def uncached_chord_from_symbol(sym)
    if (hz = CHORD_VOICINGS[sym])
      return { name: sym, hz: hz.dup }
    end
    return slash_chord_from_symbol(sym) if sym.include?("/")

    if defined?(DillaMusicGems)
      # The major_third_cycle_full-gem path has hung indefinitely on specific symbols
      # (Dm7b5, Cmaj9 — see README) with no clear pattern; rather than wait
      # for the next one to be discovered by a stuck render, bound it and
      # fall through to the built-in suffix parser below on timeout.
      gem_chord = begin
        Timeout.timeout(1.5) { DillaMusicGems.chord_from_symbol(sym) }
      rescue Timeout::Error
        warn "chord_from_symbol: DillaMusicGems hung on #{sym.inspect}, falling back" if $VERBOSE
        nil
      end
      return gem_chord if gem_chord && gem_chord_sane?(sym, gem_chord)
    end
    low_register = sym.match?(/low\z/i)
    base = sym.sub(/low\z/i, "")
    suffix = SUFFIX_MATCHERS.find { |(_, re)| base.match?(re) }&.first
    raise ArgumentError, "bad chord symbol: #{sym}" unless suffix

    root_name = base.match(/\A([A-G][#b]?)/i)[1]
    root_name = root_name[0].upcase + root_name[1..]
    quality = quality_for_suffix(suffix)
    octave = low_register ? 2 : 3
    root_hz = note_hz(root_name, octave:)
    hz = build_voicing(root_hz, quality)
    { name: sym, hz: }
  end

# X over Y. Split out of chord_from_symbol so it can run before the major_third_cycle_full
  # gem is consulted — the gem hangs on the bare-minor uppers these use.
  def slash_chord_from_symbol(sym)
  upper, bass_note = sym.split("/", 2)
  ch = chord_from_symbol(upper.strip)
  bass_hz = note_hz(bass_note.strip, octave: 2)
  # The bass note goes UNDER the upper structure. It used to overwrite the
  # structure's lowest voice, which for a rootless triad is its root: D/E
  # came out E2 F#4 A4 B4 with no D in it, C/E as E2 E4 G4 A4 with no C,
  # Db/E as E2 F3 G#3 -- an E major triad wearing a Db label. Every slash
  # chord in pedal_e_descent, the progression the stream actually plays, was
  # missing the note it is named after. A slash chord is X over Y, not X
  # with its root traded for Y.
  # The pad's copy of the bass sits close under the upper structure; :bass_hz
  # keeps the real octave-2 pitch for the bass layer. Putting E2 itself in the
  # pad made the chord span more than the pad register (E2..A5 for D/E), and
  # the register clamp then threw away everything above the window -- leaving
  # pedal_e_descent, the default progression, as two voices per chord. The
  # division of labour dilla_chord_bass_hz documents wants a mid-register pad
  # over a real bass, not the pad doubling the bass three octaves down.
  pad_bass = bass_hz
  pad_bass *= 2.0 while 12.0 * Math.log2(ch[:hz].min / pad_bass) > 17.0
  upper_root = NOTE_PC[upper.strip.match(/\A([A-G][#b]?)/i)&.captures&.first&.then { |r| r[0].upcase + r[1..].to_s }]
  hz = trim_slash_voicing(pad_bass.round(2), ch[:hz], root_pc: upper_root)
  return ch.merge(name: sym, hz:, bass_hz:)
  end

  def note_hz(name, octave: 3)
    base = name[0].upcase
    acc = name[1..] || ""
    acc = acc.tr("♯", "#").tr("♭", "b")
    pc = NOTE_PC.fetch("#{base}#{acc}")
    midi = 12 + (octave * 12) + pc
    (440.0 * (2.0**((midi - 69.0) / 12.0))).round(2)
  end

  # Upper extensions are written in simple form in CHORD_TEMPLATES -- m9 is
  # [0,3,7,10,2] and 7b9 is [0,4,7,10,1] -- so taken literally the "ninth" is a
  # second against the root. Worse, being the SMALLEST interval it sorts lowest
  # and is the first thing dropped by the trim below, which is how m9 lost its
  # ninth and 7b9 its flat nine. The template's own order says which notes are
  # extensions: anything smaller than an interval already seen. Raise those an
  # octave and they both sound right and survive the trim.

# Euclidean rhythms: k onsets spread as evenly as possible over n steps.
#
# Bjorklund's algorithm, the same one that generates the timing patterns in a
# linear accelerator, and it produces most of the world's traditional bell
# patterns as a side effect -- E(5,8) is the Cuban cinquillo, E(3,8) the
# tresillo, E(7,16) a common West African bell. They are here because "spread
# k events evenly over n" is a genuinely different generator from "write the
# steps down", and it lands hits in places a hand-written grid rarely reaches.
#
# The backbeat rule still applies: these set kicks, hats and perc, while the
# snare stays on 4 and 12. Euclid decides density, not where the bar turns.
def self.euclid(k, n)
  return [] if k <= 0 || n <= 0 || k > n

  # Build k groups of [1] and n-k of [0], then repeatedly distribute the
  # remainder into the groups until the remainder is one or zero.
  a = Array.new(k) { [1] }
  b = Array.new(n - k) { [0] }
  while b.length > 1
    pairs = [a.length, b.length].min
    merged = Array.new(pairs) { |i| a[i] + b[i] }
    rest = a.length > pairs ? a[pairs..] : b[pairs..]
    a = merged
    b = rest || []
  end
  (a + b).flatten.each_index.select { |i| (a + b).flatten[i] == 1 }
end

  def self.voice_extensions(intervals)
    seen = -1
    intervals.map do |iv|
      raised = iv
      raised += 12 while raised < seen
      seen = [seen, raised].max
      raised
    end
  end

  # Fill a voicing up to `voices` with octaves of tones it already contains,
  # cheapest colour first.
  #
  # Two earlier rules both put the root on top. `max + 2` stacked a minor ninth
  # (two semitones above a maj7's 11 is 13): Dmaj7 measured D F# A C# D#. Octaves
  # of the root fixed that and introduced its own problem -- the root landing
  # directly above the seventh is a semitone in the top of the voicing (Ebmaj7 as
  # Eb G Bb D Eb), and a triad padded twice came out D4 Gb4 A4 D5 D6, the root
  # tripled with the fifth crowded out. Both are the single most un-Dilla move
  # available: his pads are rootless shells over a bass, never root-doubled
  # blocks.
  #
  # So double the third first, then the seventh, and only then the root -- weight
  # without changing which pitch classes the chord contains, which also keeps
  # chord_tones_preserved? satisfied. Any candidate closer than a whole tone to a
  # voice already present is skipped rather than smeared against it.
  def self.pad_voicing(hz, root_hz, intervals, voices)
    return hz if hz.length >= voices

    third = intervals.find { |i| [3, 4].include?(i % 12) }
    seventh = intervals.find { |i| [10, 11].include?(i % 12) }
    fifth = intervals.find { |i| (i % 12) == 7 }
    top = intervals.max
    preference = [third, seventh, fifth, 0].compact
    octave = ((top / 12) + 1) * 12
    # A voicing wider than a twelfth is not a pad, it is two parts. Both earlier
    # rules ignored span and pushed doublings up as far as they had to: a triad
    # padded to five came out D4 Gb4 A4 D5 D6, and once the bass of a slash chord
    # joined it the chord covered E2..D6. The pad register is 29 semitones wide, so
    # such a chord was thinned back to two voices at the end of the pipeline --
    # which is what every chord of pedal_e_descent, the default progression, was
    # reduced to.
    span_ceiling = 12.0 * Math.log2(hz.min / root_hz) + 19.0
    while hz.length < voices && octave <= 36
      preference.each do |iv|
        break if hz.length >= voices
        next if iv + octave > span_ceiling

        cand = (root_hz * (2**((iv + octave) / 12.0))).round(2)
        next if hz.any? { |h| (12.0 * Math.log2(cand / h)).abs < 2.0 }

        hz << cand
      end
      octave += 12
    end
    hz
  end

  # 5, not 4: the extension that names an altered chord is a fifth or sixth
  # voice, so a four-voice cap removes precisely the note under discussion.
  # The register the whole voicing is folded into, as MIDI note numbers for its
  # LOWEST note.
  #
  # Was a literal 50..62 (D3..D4) inline in build_voicing. Operator direction on
  # 2026-08-09 was "slower deeper chords always", and this window is what "deep"
  # means for a chord: every voicing in the engine gets shifted as a unit until
  # its bottom note sits inside it, so lowering the window lowers every pad,
  # every stab and every held chord in one place rather than per preset.
  #
  # 43..55 is G2..G3, a fifth below where it was. Chosen to stay clear of the
  # sub: the sampled beds are high-passed at 45 Hz and the sub bus owns roughly
  # 32..64 Hz, and MIDI 43 is 98 Hz, so a root here still sits an octave above
  # the sub rather than fighting it. Going lower starts muddying the low end
  # instead of deepening the chord.
  #
  # CHORD_REGISTER_LOW/HIGH override for a render that wants the old placement.
  #
  # Read through a helper that treats an EMPTY variable as unset. `ENV["X"] ||
  # default` does not: an empty string is truthy in Ruby, so `CHORD_REGISTER_HIGH=`
  # in the environment yields "".to_f == 0.0, the fold-down loop then runs until
  # the chord is below MIDI 0, and every voicing comes out around 6.9 Hz --
  # inaudible, and silent rather than obviously broken.
  def self.register_env(name, default)
    v = ENV[name].to_s.strip
    v.empty? ? default : v.to_f
  end
  CHORD_REGISTER_LOW = register_env("CHORD_REGISTER_LOW", 43.0)
  CHORD_REGISTER_HIGH = register_env("CHORD_REGISTER_HIGH", 55.0)
  raise "CHORD_REGISTER_LOW must be below CHORD_REGISTER_HIGH" if CHORD_REGISTER_LOW >= CHORD_REGISTER_HIGH

  def build_voicing(root_hz, quality, voices: 5)
    intervals = voice_extensions(CHORD_TEMPLATES.fetch(quality) { CHORD_TEMPLATES["maj9"] })
    hz = intervals.map { |iv| (root_hz * (2**(iv / 12.0))).round(2) }
    pad_voicing(hz, root_hz, intervals, voices)
    # Root is always the lowest of these same-octave interval frequencies,
    # so `hz.sort.last(voices)` silently dropped it for any template longer
    # than `voices` (m9/m11/maj9 all list 5 intervals against the default
    # voices: 4) -- e.g. Cm11 came out as [Eb, F, G, Bb], no C at all, wrong
    # pitch classes entirely once octave-wrapped below. Root now always
    # survives the trim; only the extensions get thinned.
    root = hz.min
    rest = (hz - [root]).sort.last([voices - 1, 0].max)
    voiced = ([root] + rest).sort
    midis = voiced.map { |h| 69.0 + 12.0 * Math.log2(h / 440.0) }
    # `m + 12.0` (not `+=`) here never reassigns m, so `while m < 50.0` used
    # to spin forever for any note landing below MIDI 50 (e.g. "C7sus" ->
    # quality "7" -> some octave lands there) -- looked exactly like the
    # documented major_third_cycle_full-gem hang but had nothing to do with major_third_cycle_full.
    # Transpose the chord AS A UNIT, not note by note. Folding each note
    # independently into 50..76 is what destroyed the voicing this method has
    # just built: an extension raised an octave lands above 76, gets folded back
    # down, and is a second against the root again -- so the octave placement
    # above would have been undone one line later. Shifting the whole chord
    # keeps every interval intact and only moves the register.
    shift = 0.0
    shift += 12.0 while midis.min + shift < CHORD_REGISTER_LOW
    shift -= 12.0 while midis.min + shift > CHORD_REGISTER_HIGH
    midis = midis.map { |m| m + shift }
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
    # Band-limited three-oscillator detuned saw stack (see analog_pad in
    # dilla.rb's native_waveform_body) -- the only saw here that does not alias.
    when "analog", "analog_pad" then :analog_pad
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

  def track_preset(track)
    profile_preset(track)
  end

end

DillaProducerDNA = DillaLofiMachine

# Pocket, humanize, Markov drums, Euclidean/prime grids — hip-hop groove layer.
#
# Pocket DNA (MPC finger-drum craft, Charnas “Dilla Time”, Hein analyses):
#   1. SIMPLICITY — sparse 16-step: few kicks, hard 2&4 snare, rare ghosts
#   2. MICRO-TIMING — independent layers: snare early, kick late, hats later
#   3. SAMPLE CHOICE — alternate kicks, soft ghost snare, closed vs open hat
module DillaGroove
  PRIMES = [3, 5, 7, 11].freeze
  # Tempo/timing should breathe over a multi-bar phrase, not sit dead-locked
  # to the grid — a slow sine LFO, period within the 4-8 bar range documented
  # for this kind of groove-breathing.
  PHRASE_DRIFT_PERIOD_BARS = 6.0
  PHRASE_DRIFT_MAX_MS = 5.0

  # Classic sparse Dilla / Questlove pockets — FEWER kicks, solid 2&4, space.
  # Dense 4-kick bars read as house/techno; soul leaves air for Rhodes.
  POCKET_KICK_PHRASES = [
    [0, 10],
    [0, 6, 10],
    [0, 10, 14],
    [0, 7, 10],
    [0, 6],
    [0, 3, 10],
    [6, 10],
    [0, 11],
  ].freeze
  # Dusty / Madlib — still sparse, occasional four-on-floor half-bar only.
  POCKET_KICK_PHRASES_DUSTY = [
    [0, 10],
    [0, 8, 11],
    [0, 7, 10],
    [0, 4, 10],
    [0, 10, 14],
    [2, 10],
    [0, 6, 10],
    [0, 8],
  ].freeze
  # Neo-soul / D'Angelo live-pocket: often downbeat + one syncopation.
  # Expanded set rotates across bars so stream/one-shots don't feel looped.
  POCKET_KICK_PHRASES_NEOSOUL = [
    [0, 10],
    [0, 6],
    [0, 10, 13],
    [0],
    [0, 7, 10],
    [0, 11],
    [6, 10],
    [0, 6, 14],
    [0, 9],
    [0, 3, 10],
    [0, 10, 14],
    [0, 5, 10],
    [10],
    [0, 6, 11],
    [0, 8, 14],
    [0, 7],
  ].freeze
  # Sparse shapes for breathing bars.
  POCKET_KICK_SPARSE_PHRASES = [
    [0],
    [0, 10],
    [10],
    [0, 6],
    [],
  ].freeze
  POCKET_KICK_SPARSE_PHRASES_DUSTY = [
    [0, 8],
    [0],
    [0, 10],
    [8],
  ].freeze
  POCKET_KICK_SPARSE_PHRASES_NEOSOUL = [
    [0],
    [0, 10],
    [],
    [10],
    [0, 6],
    [0, 11],
    [],
    [0, 7],
  ].freeze
  POCKET_SNARE_HARD = [4, 12].freeze
  # Documented Dilla off-kilter device: the backbeat snare occasionally
  # pushed a full 16th early rather than sitting on 4/12 -- a placement
  # choice, distinct from the ms-level micro-timing in role_timing_offset.
  POCKET_SNARE_RUSH = [4, 11].freeze
  POCKET_SNARE_RUSH_DUSTY = [3, 12].freeze
  POCKET_SNARE_RUSH_NEOSOUL = [4, 12].freeze # keep backbeat locked more often
  POCKET_SNARE_GHOST_PHRASES = [
    [],
    [7],
    [10],
    [7, 15],
    [],
    [2],
  ].freeze
  POCKET_SNARE_GHOST_PHRASES_DUSTY = [
    [6],
    [],
    [6, 14],
    [14],
    [],
  ].freeze
  # Live neo-soul ghosts: quiet 16th after 2, rarely both — more phrase variety.
  POCKET_SNARE_GHOST_PHRASES_NEOSOUL = [
    [],
    [5],
    [7],
    [],
    [13],
    [5, 13],
    [6],
    [],
    [15],
    [5, 7],
    [13, 15],
    [],
  ].freeze
  # 8th hats, but NOT every bar identical — leave space (real RH pocket).
  POCKET_HAT_PHRASES = [
    [0, 2, 4, 6, 8, 10, 12, 14],
    [0, 2, 4, 6, 8, 10, 12],
    [0, 4, 6, 8, 10, 12, 14],
    [0, 2, 4, 8, 10, 12, 14],
    [2, 4, 6, 8, 10, 12, 14],
  ].freeze
  # Offbeat-biased dusty hats — thinner than full 16ths.
  POCKET_HAT_PHRASES_DUSTY = [
    [1, 3, 5, 7, 9, 11, 13],
    [1, 3, 5, 7, 9, 11, 15],
    [1, 3, 5, 9, 11, 13],
    [0, 3, 5, 7, 9, 11, 13],
  ].freeze
  # Neo-soul: often quarters or sparse 8ths — never full 16th grid.
  POCKET_HAT_PHRASES_NEOSOUL = [
    [0, 4, 8, 12],
    [0, 2, 4, 8, 12],
    [0, 4, 8, 10, 12],
    [0, 4, 6, 8, 12, 14],
    [2, 4, 8, 12],
    [0, 4, 8],
    [0, 4, 10, 12],
    [0, 2, 8, 12],
    [4, 8, 12],
    [0, 6, 8, 12, 14],
  ].freeze
  # Industrial techno: four-on-floor kick, solid 2+4 snare/clap, 16th hats.
  POCKET_KICK_PHRASES_INDUSTRIAL = [
    [0, 4, 8, 12],
    [0, 4, 8, 12],
    [0, 4, 8, 10, 12],
    [0, 4, 8, 12, 14],
    [0, 4, 6, 8, 12],
    [0, 4, 8, 12],
    [0, 2, 4, 8, 12],
    [0, 4, 8, 11, 12],
  ].freeze
  POCKET_KICK_SPARSE_PHRASES_INDUSTRIAL = [
    [0, 4, 8, 12],
    [0, 8],
    [0, 4, 12],
  ].freeze
  POCKET_SNARE_HARD_INDUSTRIAL = [4, 12].freeze
  POCKET_SNARE_RUSH_INDUSTRIAL = [4, 12].freeze
  POCKET_SNARE_GHOST_PHRASES_INDUSTRIAL = [
    [],
    [10],
    [],
    [6],
    [],
  ].freeze
  POCKET_HAT_PHRASES_INDUSTRIAL = [
    (0..15).to_a,
    (0..15).to_a,
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [0, 2, 4, 6, 8, 10, 12, 14],
    [0, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14],
  ].freeze

  # Freehand nudge ranges in MPC ticks (1/96 beat) — cyclic, not random chaos.
  POCKET_TICKS = {
    kick_anchor: 0..3,
    kick_sync: 2..9,
    snare: -14..-5,
    ghost: -6..4,
    hat_down: -1..4,
    hat_up: 6..16,
    open: 4..12,
    clap: -12..-4,
  }.freeze

  KICK_SAMPLE_CYCLE = %i[kick ind_kick kick kick].freeze
  module_function

  # djb2, not Symbol/String#hash. Ruby randomises both per process (SipHash),
  # so role.hash seeded the Markov RNG from a different number on every run
  # and the same bar/role never stroked the same way twice.
  def stable_hash(text)
    text.to_s.each_byte.reduce(5381) { |a, b| ((a * 33) + b) % 4_294_967_296 }
  end

  def enabled?
    ENV["GROOVE_ENGINE"] != "0"
  end

  # Gaussian-clustered jitter, not uniform: ~80% of hits land within one
  # sigma of center, a rare (~5%) outlier lands 3-4x further out. Uniform
  # "humanize" jitter reads as robotic — real players cluster tight around
  # a target with occasional misses, not a flat scatter (Box-Muller).
  def gaussian_jitter(rng, half_width)
    u1 = [rng.rand, 1.0e-9].max
    u2 = rng.rand
    z = Math.sqrt(-2.0 * Math.log(u1)) * Math.cos(2.0 * Math::PI * u2)
    sigma = half_width / 3.0
    outlier = rng.rand < 0.05
    (z * sigma * (outlier ? 3.5 : 1.0)).clamp(-half_width * 1.6, half_width * 1.6)
  end

  def pocket_dna?
    ENV.fetch("POCKET_DNA", "1") != "0"
  end

  # dusty | industrial | neo_soul | classic
  def pocket_set
    set = ENV.fetch("POCKET_SET", "neo_soul").to_s.downcase
    return "neo_soul" if set == "soul" || set == "neosoul"
    # An explicit POCKET_SET wins outright -- DRUM_PRESET-based inference below
    # is a fallback for when the caller didn't choose a pocket at all, not a
    # second vote that can overrule one they did (e.g. POCKET_SET=classic with
    # DRUM_PRESET=dilla_slight silently became neo_soul before this guard).
    return set if ENV.key?("POCKET_SET") && !set.empty?

    preset = ENV["DRUM_PRESET"].to_s.downcase
    return "dusty" if preset.include?("madlib")
    return "industrial" if preset.include?("industrial") || preset.include?("boom_808")
    return "neo_soul" if preset.include?("dilla") || preset.include?("mpc")

    set
  end

  def dusty_pocket? = pocket_set == "dusty"
  def industrial_pocket? = pocket_set == "industrial"
  def neosoul_pocket? = pocket_set == "neo_soul" || pocket_set == "soul"

  def kick_phrases
    return POCKET_KICK_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_KICK_PHRASES_DUSTY if dusty_pocket?
    return POCKET_KICK_PHRASES_NEOSOUL if neosoul_pocket?

    POCKET_KICK_PHRASES
  end

  def kick_sparse_phrases
    return POCKET_KICK_SPARSE_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_KICK_SPARSE_PHRASES_DUSTY if dusty_pocket?
    return POCKET_KICK_SPARSE_PHRASES_NEOSOUL if neosoul_pocket?

    POCKET_KICK_SPARSE_PHRASES
  end

  def snare_rush_steps
    return POCKET_SNARE_RUSH_INDUSTRIAL if industrial_pocket?
    return POCKET_SNARE_RUSH_DUSTY if dusty_pocket?
    return POCKET_SNARE_RUSH_NEOSOUL if neosoul_pocket?

    POCKET_SNARE_RUSH
  end

  def snare_hard_steps
    return POCKET_SNARE_HARD_INDUSTRIAL if industrial_pocket?

    POCKET_SNARE_HARD
  end

  def snare_ghost_phrases
    return POCKET_SNARE_GHOST_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_SNARE_GHOST_PHRASES_DUSTY if dusty_pocket?
    return POCKET_SNARE_GHOST_PHRASES_NEOSOUL if neosoul_pocket?

    POCKET_SNARE_GHOST_PHRASES
  end

  def hat_phrases
    return POCKET_HAT_PHRASES_INDUSTRIAL if industrial_pocket?
    return POCKET_HAT_PHRASES_DUSTY if dusty_pocket?
    return POCKET_HAT_PHRASES_NEOSOUL if neosoul_pocket?

    POCKET_HAT_PHRASES
  end

  # Bridged from main's @render_seed by pick_render_seed! (dilla.rb) so the
  # phrase-rotation and probabilistic pocket choices below vary by render
  # instead of being a pure function of bar number -- without this, bar N
  # picks the identical kick/hat/ghost-snare shape on every single render
  # of every single track, which read as "the same drums every time".
  def render_seed
    ENV["DILLA_RENDER_SEED"].to_i
  end

  # Structural use of the humanization system: looser (more jitter) where a
  # section should feel open/unlocked, tighter where it should feel nailed
  # down -- not a flat constant across the whole track regardless of what's
  # happening structurally.
  SECTION_JITTER_MUL = {
    breakdown: 1.35, development: 1.2, bridge: 1.2, intro: 1.15,
    e_major_third_rise: 0.6, peak: 0.6, hook: 0.6, recapitulation: 0.7,
  }.freeze

  def swing_jitter_ms(bpm, step, bar, role: nil, section: nil)
    return 0.0 unless enabled?
    return 0.0 if ENV["SWING_JITTER"] == "0"
    beat_ms = 60_000.0 / bpm
    tick_ms = beat_ms / 96.0
    rng = Random.new((bar * 509) + (step * 97) + 8803)
    base_ticks = (ENV["SWING_JITTER_TICKS"] || (pocket_dna? ? 4 : 3)).to_i
    max_ticks = [(base_ticks * SECTION_JITTER_MUL.fetch(section.to_s.to_sym, 1.0)).round, 1].max
    raw = gaussian_jitter(rng, max_ticks * tick_ms / 1000.0)
    # Quantize to a whole tick -- the MPC3000's manual nudge tool (the real
    # mechanism this jitter approximates) can only land on one of 96
    # discrete positions per beat, so a fractional-tick jitter value is one
    # that could never have been produced by hand on the actual hardware.
    quantized_ticks = (raw / (tick_ms / 1000.0)).round
    (quantized_ticks * tick_ms / 1000.0) + phrase_drift_sec(bar, role:)
  end

  # Per-role period multiplier + phase offset so kick/snare/hat drift
  # independently rather than breathing in lockstep -- this is the actual
  # core of Charnas's "Dilla Time" thesis (multiple simultaneous time-feels
  # layered against each other), not one groove with uniform noise added.
  ROLE_DRIFT_PERIOD_MUL = {
    kick: 1.0, kick_anchor: 1.0, kick_sync: 1.0,
    snare: 0.78, clap: 0.78,
    hat: 1.35, hat_down: 1.35, hat_up: 1.35, open: 1.35,
    ghost: 0.6,
  }.freeze
  ROLE_DRIFT_PHASE = {
    kick: 0.0, kick_anchor: 0.0, kick_sync: 0.0,
    snare: Math::PI * 0.6, clap: Math::PI * 0.6,
    hat: Math::PI * 1.3, hat_down: Math::PI * 1.3, hat_up: Math::PI * 1.3, open: Math::PI * 1.3,
    ghost: Math::PI * 0.25,
  }.freeze

  # Slow-oscillating timing drift applied on top of per-hit jitter — the
  # difference between a groove that "breathes" over a phrase and one that's
  # merely noisy hit-to-hit. Deterministic (same bar always drifts the same
  # amount), independent of the per-hit RNG.
  def phrase_drift_sec(bar, role: nil)
    return 0.0 unless enabled?
    return 0.0 if ENV["PHRASE_DRIFT"] == "0"
    role_key = role.to_s.to_sym
    period = (ENV["PHRASE_DRIFT_PERIOD_BARS"] || PHRASE_DRIFT_PERIOD_BARS).to_f * ROLE_DRIFT_PERIOD_MUL.fetch(role_key, 1.0)
    max_ms = (ENV["PHRASE_DRIFT_MAX_MS"] || PHRASE_DRIFT_MAX_MS).to_f
    return 0.0 if period <= 0
    phase = (bar.to_f / period) * 2.0 * Math::PI + ROLE_DRIFT_PHASE.fetch(role_key, 0.0)
    (Math.sin(phase) * max_ms) / 1000.0
  end

  # Multipliers are whole ticks, not arbitrary floats: the MPC3000 runs at
  # 96 PPQ (pulses per quarter note), and its manual time-shift/nudge tool
  # -- the actual mechanism Dilla used instead of quantization -- can only
  # place a hit on one of those 96 discrete positions per beat. A fractional
  # tick offset is a value that could never have existed on the real
  # hardware; whole-tick multipliers keep every offset authentically
  # reachable by the tool this feel is modeled on.
  # Which way each role leans, in whole ticks. Positive drags, negative pushes.
  #
  # The offsets are neither inline nor one-directional. Snare -3/-4 with
  # everything else positive is a real feel — a pushed snare against a dragged
  # kit, which the code calls "laid-back boom-bap tension" — but it is the only one
  # reachable, and SNARE_EARLY=0 could only switch it off, never reverse it.
  #
  # It is also the inverse of the lurch most people mean by "Dilla". On Donuts
  # and Ruff Draft the snare is the element that drags, against hats that hold
  # steady; Charnas's thesis is that the feels *conflict*, and which layer lags
  # is what distinguishes one groove from another. So the polarity is a profile.
  #
  # Whole ticks throughout, because the MPC3000 runs at 96 PPQ and its nudge tool
  # can only land on those positions — a fractional offset is one the hardware
  # this models could never have produced.
  GROOVE_FEELS = {
    # Unchanged from the inline values, so nothing moves unless asked.
    boom_bap: { snare: -4, snare_plain: -3, clap: -4, kick_anchor: 1, kick: 3,
                hat: 2, hat_up: 3, ghost: 1, bass: 0,
                keys: 0, lead: 0 },

    # Snare behind, hats holding the grid. The hats are the reference the snare
    # is late against — drag them too and the whole bar just sounds slow rather
    # than lurching.
    dilla_drag: { snare: 4, snare_plain: 3, clap: 4, kick_anchor: -1, kick: 0,
                  hat: 0, hat_up: 1, ghost: 2, bass: -2,
                  keys: 5, lead: 7 },

    # Camel: the kick displaced off the grid rather than merely late, hats a
    # touch ahead so the top stutters against a snare that drags further than
    # Dilla's.
    #
    # Not the widest spread — boom_bap is, at 51.5ms against Camel's 44.2 at
    # 85 BPM, because its snare is pushed nearly 30ms while its kick drags 22.
    # What separates Camel is the *direction*: everything below the hats leans
    # late while the hats lean early, so the top and bottom of the kit pull
    # apart. boom_bap splits snare-against-everything; Camel splits
    # hats-against-everything, and that is what reads as broken rather than
    # merely swung.
    camel: { snare: 5, snare_plain: 4, clap: 5, kick_anchor: 2, kick: 4,
             hat: -1, hat_up: 0, ghost: 3, bass: 2,
             keys: 6, lead: 8 },
  }.freeze

  # dilla_drag, not boom_bap.
  #
  # ENV_AND_RENDER.md listed the old default under "a default that surprises",
  # and it was the plainest one there: an engine named for Dilla did not apply
  # the Dilla microtiming unless a knob was set, so every render anyone made
  # without reading that document came out boom-bap — snare four ticks EARLY
  # where the whole point is four ticks late. The table existed, was correct,
  # and nobody reached it.
  #
  # GROOVE_FEEL still takes boom_bap and camel; what changed is which one you
  # get for free.
  def groove_feel
    key = ENV.fetch("GROOVE_FEEL", "dilla_drag").to_s.downcase.to_sym
    GROOVE_FEELS.fetch(key, GROOVE_FEELS[:dilla_drag])
  end

  def role_timing_offset(role, beat_p, _bar, _step)
    return 0.0 unless enabled?
    tick = beat_p / 96.0
    feel = groove_feel
    case role.to_sym
    when :snare
      return 0.0 if ENV["SNARE_EARLY"] == "0"
      tick * (pocket_dna? ? feel[:snare] : feel[:snare_plain])
    when :clap
      ENV["SNARE_EARLY"] == "0" ? 0.0 : tick * feel[:clap]
    when :kick_anchor, :kick_sync, :kick
      return 0.0 if ENV["KICK_LATE"] == "0"
      # Outside pocket_dna the kick stayed on the grid in every feel; keeping
      # that, so this switch changes the lean and not how much is quantized.
      return 0.0 unless pocket_dna?

      tick * (role.to_sym == :kick_anchor ? feel[:kick_anchor] : feel[:kick])
    when :hat, :hat_down, :hat_up, :open
      return 0.0 if ENV["HATS_LATE"] == "0"
      tick * (role.to_sym == :hat_up ? feel[:hat_up] : feel[:hat])
    when :ghost
      tick * feel[:ghost]
    when :pad, :ep, :keys, :chord
      # The whole harmonic layer was pinned to the grid while the rhythm section
      # leaned around it: at 88 BPM in dilla_drag the snare sat +28.4 ms and the
      # bass -14.2, and pads, EPs and leads all sat at exactly 0.
      #
      # That is backwards for this music. On a Dilla or D'Angelo record the keys
      # are the *latest* thing in the bar — later than the dragged snare — which
      # is most of why the harmony sounds unhurried over a groove that is not.
      # The drums establish the time and the chords refuse to hurry to it.
      return 0.0 if ENV["KEYS_FEEL"] == "0"

      tick * feel.fetch(:keys, 0)
    when :lead, :scale_lead, :xlead
      # Further back still, so the three layers form a hierarchy rather than two
      # positions: bass ahead, drums leaning, keys behind, lead behind the keys.
      return 0.0 if ENV["KEYS_FEEL"] == "0"

      tick * feel.fetch(:lead, 0)
    when :lead_extra
      # The lead is built on top of a pad event and inherits that event's time,
      # so it has already taken the :keys offset by the time it is placed. This
      # returns only the difference, which lets the table above stay absolute
      # (keys 5, lead 7 means the lead lands at 7, not at 12).
      return 0.0 if ENV["KEYS_FEEL"] == "0"

      tick * (feel.fetch(:lead, 0) - feel.fetch(:keys, 0))
    when :bass
      # The bass was the one voice with no entry here, so it fell to the `else`
      # and stayed pinned to the grid in every feel. That made a groove switch a
      # drums-against-a-metronome change rather than a change in how the band
      # sits together.
      #
      # It is the D'Angelo point. On Voodoo the drums drag and the bass does not
      # follow them down — Pino sits fractionally ahead of Questlove, and the
      # pocket is the *distance between them*, not either one's distance from a
      # click. A dragging snare over a locked bass only widens that gap by the
      # snare's own lateness; moving the bass the other way widens it by both.
      #
      # boom_bap stays at 0, which is exactly what the `else` returned, so
      # nothing moves unless the feel is switched.
      return 0.0 if ENV["BASS_FEEL"] == "0"

      tick * feel.fetch(:bass, 0)
    else
      0.0
    end
  end

  def hat_micro_delay_sec(bar, step, beat_p)
    return 0.0 unless enabled?
    return 0.0 if ENV["HAT_MICRO"] == "0"
    rng = Random.new((bar * 313) + (step * 17) + 42)
    # Freehand hats: slightly wider when pocket DNA is on.
    hi = pocket_dna? ? 0.0045 : 0.0022
    raw = rng.rand(0.0004..hi)
    tick_sec = beat_p / 96.0
    return raw if tick_sec <= 0
    [(raw / tick_sec).round, 1].max * tick_sec
  end

  # Real finger-drumming occasionally misses a kick too, not just hats --
  # rare (~3%) and never the downbeat/anchor.
  def kick_should_drop?(bar, step)
    return false unless enabled? && pocket_dna?
    return false if ENV["KICK_DROP"] == "0"
    return false if step.zero?
    Random.new((bar * 971) + (step * 61) + 337 + render_seed).rand < 0.03
  end

  # Documented Dilla technique: kick doubles that sit off the grid -- a
  # quick, quieter second hit close behind the main kick, not a clean
  # quantized repeat. Whole-tick offset (2-4 ticks), same 96-PPQ
  # authenticity as the rest of the timing system.
  def kick_double_offset_ticks(bar, step)
    return unless enabled? && pocket_dna?
    return if ENV["KICK_DOUBLE"] == "0"
    return unless Random.new((bar * 883) + (step * 47) + 521 + render_seed).rand < 0.05
    [2, 3, 4].sample(random: Random.new((bar * 601) + (step * 29) + 71 + render_seed))
  end

  # A ghost note immediately before the backbeat snare -- a quieter
  # pickup hit distinct from the scattered ghost phrase pool, which
  # tends to be a genuine pre-hit ornament rather than mid-bar filler.
  def snare_prehit_ghost?(bar, step)
    return false unless enabled? && pocket_dna?
    return false if ENV["SNARE_PREHIT_GHOST"] == "0"
    Random.new((bar * 449) + (step * 71) + 883 + render_seed).rand < 0.08
  end

  # A finger-drummer occasionally misses a hat, or leaves space on purpose —
  # a pattern that never drops a single 16th over 32 bars reads as sequenced.
  # Rare (~4%), deterministic per bar/step, and never the downbeat.
  def hat_should_drop?(bar, step, section: nil)
    return false unless enabled? && pocket_dna?
    return false if ENV["HAT_DROP"] == "0"
    return false if step.zero?
    prob = 0.04 * SECTION_JITTER_MUL.fetch(section.to_s.to_sym, 1.0)
    Random.new((bar * 787) + (step * 53) + 191 + render_seed).rand < prob
  end

  def freehand_kick_sec(bar, step, beat_p)
    return 0.0 unless pocket_dna? && ENV.fetch("KICK_FREEHAND", "1") != "0"
    # Unquantized kick nudges (time-shift feel) — cyclic by bar/step.
    tick = beat_p / 96.0
    seed = (bar % 4) * 97 + step * 31 + 19
    ticks = POCKET_TICKS[:kick_sync]
    raw = ticks.begin + (seed % (ticks.end - ticks.begin + 1))
    raw * tick * (step.zero? ? 0.35 : 1.0)
  end

  # A flam is a fixed number of MPC ticks, not a fixed ms value -- a fixed-ms
  # constant means the same flam represents a different (and at fast tempos,
  # audibly wrong) fraction of a beat as BPM changes. 2 ticks was the
  # previous ~0.0012s at a typical ~90 BPM (tick ~6.9ms there); express it
  # as 2 ticks directly so it scales correctly with tempo.
  def flam_offset_sec(beat_p = nil)
    return 0.0 unless enabled? && ENV["FLAM"] != "0"
    return 0.0012 unless beat_p&.positive?
    2 * (beat_p / 96.0)
  end

  def kick_snare_swap?
    enabled? && ENV["KICK_SNARE_SWAP"] == "1"
  end

  def groove_lock_melody?
    ENV["GROOVE_LOCK"].to_s.downcase == "kick"
  end

  def melody_time_offset(bar, step, beat_p)
    return 0.0 unless groove_lock_melody?
    step_p = beat_p / 4.0
    rng = Random.new(bar * 71 + step)
    center = step_p * 0.10
    center + gaussian_jitter(rng, step_p * 0.45)
  end

  def trap_morph_hat_density(bar, n_bars, base_steps)
    return base_steps unless enabled? && ENV["TRAP_MORPH"] == "1"
    progress = bar.to_f / [n_bars - 1, 1].max
    extra = (0..15).select { |s| s.odd? && Random.new(bar * 3).rand < (0.15 + progress * 0.55) }
    (base_steps + extra).uniq.sort
  end

  def euclidean(pulses, steps, rotation: 0)
    return [] if steps <= 0 || pulses <= 0
    bucket = 0.0
    out = []
    steps.times do |i|
      bucket += pulses.to_f / steps
      out << ((i + rotation) % steps) if bucket >= 1.0
      bucket -= 1.0 if bucket >= 1.0
    end
    out.uniq.sort
  end

  def prime_poly_steps(_bar)
    return [] unless enabled? && ENV["PRIME_GRID"] == "1"
    PRIMES.flat_map { |p| (0...16).step(p).map { |s| s % 16 } }.uniq.sort
  end

  # A cycle that does not reset at the bar line.
  #
  # Everything else in this file lands inside one 16-step bar and starts over:
  # euclidean(5, 16) is a 16-step figure, prime_poly_steps folds its primes back
  # with `s % 16`, and drum_pattern_pick returns a per-bar list. That is a
  # cross-rhythm INSIDE a bar, which is not the same thing as a polymeter, and
  # the difference is audible -- a figure that resets every bar agrees with the
  # downbeat every bar, however uneven it is within one.
  #
  # This indexes the pattern by the GLOBAL step instead, so an 11-step cycle
  # against a 16-step bar precesses and only comes back round to the downbeat
  # after lcm(11, 16) = 176 steps, or 11 bars.
  #
  # The gap this fills was a claim rather than a feature. groove.rb's
  # wonky_cosmogramma preset says its hats are "a 3-step cycle against a 16-step
  # bar, so they only agree with the downbeat once every three bars" -- but its
  # pool holds one entry, [0, 3, 6, 9, 12, 15], so drum_pattern_pick returns the
  # identical list for every bar and the hats hit the downbeat in all of them.
  # That preset is left alone (nothing moves unless asked); POLYMETER_HATS=3 is
  # what the comment describes.
  #
  # pulses defaults to ONE hit per cycle, not one per position in it. "A 3-step
  # cycle" is a hit every third step -- [0, 3, 6, 9, ...] -- and the first cut of
  # this defaulted to `(0...cycle).to_a`, i.e. every residue, which matches every
  # step and fires continuously. It looked like a working polymeter in the code
  # and was a 16th-note roll in the output.
  #
  # Give pulses to spread more than one hit across the cycle with euclidean, so
  # POLYMETER_HATS=11 POLYMETER_PULSES=7 is the 7-against-11 that IDM uses.
  #
  # Capped at cycle - 1, not at cycle. euclidean(n, n) is every position by
  # definition, so a cycle filled to its own length has no gap in it, precesses
  # against nothing and is audible only as a 16th roll -- the same output as the
  # default bug above, reached by asking for too many pulses instead of too few.
  # One gap is the minimum that makes a cycle a cycle.
  def polymeter_steps(bar, cycle:, pulses: nil, steps_per_bar: 16)
    return [] if cycle.to_i < 2 || steps_per_bar.to_i < 1

    cycle = cycle.to_i
    n = pulses.to_i.clamp(0, cycle - 1)
    hits = n > 1 ? euclidean(n, cycle) : [0]
    return [] if hits.empty?

    base = bar.to_i * steps_per_bar
    (0...steps_per_bar).select { |s| hits.include?((base + s) % cycle) }
  end

  # POLYMETER_HATS=<cycle>, optionally POLYMETER_PULSES=<n>. Off unless set,
  # like every other grid switch here.
  def polymeter_hat_steps(bar)
    return [] unless enabled?

    cycle = ENV["POLYMETER_HATS"].to_i
    return [] unless cycle > 1

    polymeter_steps(bar, cycle:, pulses: ENV["POLYMETER_PULSES"])
  end

  # A lazily-initialized module ivar, not a `NAME = {}` constant -- that
  # constant-literal pattern is exactly what an automated formatting pass
  # kept matching and appending .freeze to (three separate times tonight),
  # each time breaking every render that touches the Markov drum path with
  # FrozenError. This shape isn't a hash-literal-assigned-to-constant, so
  # there's nothing for that kind of blanket rule to catch.
  def markov_cache
    @markov_cache ||= {}
  end

  def markov_steps(bar, role, pool)
    flat = pool.flatten.uniq
    return flat if flat.empty?
    return flat unless enabled? && ENV["MARKOV_DRUMS"] != "0"
    key = [role, stable_hash(flat)].join(":")
    matrix = markov_cache[key] ||= build_markov_from_pool(flat)
    rng = Random.new((bar * 1009) + stable_hash(role))
    seed_step = flat[bar % flat.length]
    extra = matrix.dig(seed_step)&.sample(random: rng) || flat[(bar + 1) % flat.length]
    (flat + [seed_step, extra]).uniq.sort
  end

  def build_markov_from_pool(flat)
    transitions = Hash.new { |h, k| h[k] = [] }
    flat.each_with_index do |step, i|
      transitions[step] << flat[(i + 1) % flat.length]
      transitions[step] << flat[(i + 2) % flat.length]
    end
    transitions.transform_values(&:uniq)
  end

  def apply_event_timing!(t, role:, beat_p:, bar:, step:, bpm: 90, section: nil)
    t + role_timing_offset(role, beat_p, bar, step) +
      swing_jitter_ms(bpm, step, bar, role:, section:) +
      (role.to_s.start_with?("hat") ? hat_micro_delay_sec(bar, step, beat_p) : 0.0) +
      (%i[kick kick_anchor kick_sync].include?(role.to_sym) ? freehand_kick_sec(bar, step, beat_p) : 0.0)
  end

  # --- Simplicity: sparse rotating phrases ---

  def pocket_kicks(bar)
    phrases = kick_phrases
    return phrases[0] unless pocket_dna?
    phrase = phrases[(bar + render_seed) % phrases.length]
    # Breathing bar: ~22% chance, seeded per bar+render (reproducible within
    # a render, but not the same every render), drop to a sparser shape
    # drawn from a small pool instead of always the same [0, 10].
    if ENV.fetch("POCKET_SIMPLE", "1") != "0" && Random.new((bar * 733) + 41 + render_seed).rand < 0.22
      # A slice of those breathing bars go all the way to silence -- a real
      # producer choice, not just reduced density every time.
      if ENV["POCKET_KICK_SILENCE"] != "0" && Random.new((bar * 457) + 233 + render_seed).rand < 0.12
        return []
      end
      sparse = kick_sparse_phrases
      return sparse[Random.new((bar * 911) + 17 + render_seed).rand(sparse.length)]
    end
    phrase
  end

  # Rush is a loosening device -- more of it where a section is meant to
  # feel open/unlocked (breakdown, development/bridge), rarer where it
  # should feel locked in (e_major_third_rise/peak/hook/recap).
  SNARE_RUSH_PROB_BY_SECTION = {
    breakdown: 0.20, development: 0.18, bridge: 0.18,
    e_major_third_rise: 0.04, peak: 0.04, hook: 0.04, recapitulation: 0.05
  }.freeze

  def pocket_snares_hard(bar, section: nil)
    hard = snare_hard_steps
    return hard unless pocket_dna?
    return hard if ENV["POCKET_RUSH"] == "0" || industrial_pocket?
    prob = SNARE_RUSH_PROB_BY_SECTION.fetch(section.to_s.to_sym, 0.12)
    Random.new((bar * 619) + 83 + render_seed).rand < prob ? snare_rush_steps : hard
  end

  def pocket_snares_ghost(bar)
    return [] unless pocket_dna?
    return [] if ENV["POCKET_GHOSTS"] == "0"
    ghosts = snare_ghost_phrases
    ghosts[(bar + render_seed) % ghosts.length]
  end

  def pocket_hats(bar)
    phrases = hat_phrases
    phrases[(bar + render_seed) % phrases.length]
  end

  def pocket_open_hat?(bar)
    pocket_dna? && (bar % 8) == 7 && ENV.fetch("POCKET_OPEN_HAT", "1") != "0"
  end

  # --- Sample choice ---

  def kick_sample_key(bar, step)
    return :kick unless pocket_dna?
    # Alternate kicks (different pitch/body) — common MPC finger-drum habit.
    cycle = KICK_SAMPLE_CYCLE
    idx = (bar + (step.zero? ? 0 : 1) + step / 4) % cycle.length
    # Prefer tighter body on downbeat, alternate on offbeats.
    step.zero? ? :kick : cycle[idx]
  end

  def snare_sample_key(ghost:)
    ghost ? :ghost : :snare
  end

  def apply_pocket_place(t, role:, beat_p:, bar:, step:, bpm:, section: nil)
    apply_event_timing!(t, role:, beat_p:, bar:, step:, bpm:, section:)
  end
end

# The semantics of techno, as data a renderer reads.
#
# A techno track is mostly not pitch. It is where hits land and where they do
# not, how long each figure takes to come round, which parameter moves over
# which span of time, and which state the whole thing is in. Every renderer in
# this engine already carries pieces of that -- GROOVE_FEELS, polymeter_steps,
# HATE_LAYERS, the DFAM patch -- as literals inside one render method each, so a
# style could only be copied, never described. This module is the description:
# seventeen axes on 0..1, a low-end choice, a kick voice, and the elements a
# track is made of, per style. Energy is not an axis; it is measured from a
# state, because a section's energy is what it contains, not a knob.
#
# Pure: no ENV, no IO, no randomness it was not handed a seed for. The renderer
# (SemanticTechno in sound.rb) and the profile-to-knob mapping for `hate` and
# `industrial` both read it, so the two cannot describe a style differently.
module DillaSemantics
  AXES = %i[pulse microtiming accent density sparsity persistence mutation polyrhythm
            velocity_curve envelope_variance spectral_motion spatial_motion harmonic_density
            feedback resampling tension contrast].freeze

  # The low end is a choice among five, not KICK + RUMBLE. A dry kick with a long
  # tail is a whole low end in some styles and a rumble would bury it.
  LOW_ENDS = %i[kick_tail rumble bass tom_sub hybrid].freeze

  ENERGY = %i[density brightness transient_sharpness spectral_width harmonic_density
              rhythmic_complexity tension contrast].freeze

  # Two clocks per element. cycle_bars is how long its figure takes to repeat, so
  # a 1-bar kick, 2-bar perc and 3-bar perc only line up every six bars and the
  # relationship changes without anyone writing a new pattern. motion_beats is
  # the period of the parameter that moves it -- a hat's decay on eighths, a
  # filter over sixteen bars, the atmosphere over sixty-four -- so everything
  # moves and nothing moves at the same time.
  ELEMENTS = {
    kick: { cycle_bars: 1, motion_beats: 1.0, register: :low },
    hat: { cycle_bars: 1, motion_beats: 0.5, register: :high },
    open: { cycle_bars: 2, motion_beats: 4.0, register: :high },
    clap: { cycle_bars: 2, motion_beats: 8.0, register: :mid },
    perc_a: { cycle_bars: 2, motion_beats: 4.0, register: :mid },
    perc_b: { cycle_bars: 3, motion_beats: 16.0, register: :high },
    stab: { cycle_bars: 4, motion_beats: 64.0, register: :mid },
    texture: { cycle_bars: 4, motion_beats: 256.0, register: :wide },
    low: { cycle_bars: 1, motion_beats: 64.0, register: :low },
  }.freeze

  # GROOVE_FEELS speaks in drum roles; these are the roles each element plays.
  FEEL_ROLES = { kick: :kick, hat: :hat, open: :hat_up, clap: :clap, perc_a: :ghost,
                 perc_b: :ghost, stab: :keys, texture: :keys, low: :bass }.freeze

  # Each profile states what the research on that style names, in the axes'
  # terms. The numbers are relative -- basic_channel's feedback is high against
  # detroit's -- and each style's kick is a voice with its own body, sweep and
  # click rather than a sample choice.
  #
  # Tempos are the records', not a blog's: dub techno sits near 125, hardgroove
  # a little above 130, and the HATE-adjacent industrial style at 138, where a
  # faster top end makes it feel quicker than its clock.
  PROFILES = {
    detroit: {
      bpm: 128, low_end: :bass, feel: nil,
      elements: %i[kick hat open clap perc_a perc_b stab low],
      kick: { body_hz: 52.0, sweep_hz: 140.0, sweep_decay: 30.0, amp_decay: 9.0, click_ms: 3.0, drive: 0.3 },
      axes: { pulse: 0.9, microtiming: 0.6, accent: 0.7, density: 0.6, sparsity: 0.3, persistence: 0.5,
              mutation: 0.5, polyrhythm: 0.6, velocity_curve: 0.6, envelope_variance: 0.3,
              spectral_motion: 0.5, spatial_motion: 0.3, harmonic_density: 0.35, feedback: 0.3,
              resampling: 0.2, tension: 0.45, contrast: 0.5 },
    },
    basic_channel: {
      bpm: 126, low_end: :rumble, feel: nil,
      elements: %i[kick hat perc_b stab texture low],
      kick: { body_hz: 48.0, sweep_hz: 90.0, sweep_decay: 22.0, amp_decay: 7.0, click_ms: 1.5, drive: 0.1 },
      axes: { pulse: 1.0, microtiming: 0.0, accent: 0.3, density: 0.25, sparsity: 0.6, persistence: 0.9,
              mutation: 0.2, polyrhythm: 0.3, velocity_curve: 0.3, envelope_variance: 0.2,
              spectral_motion: 0.85, spatial_motion: 0.8, harmonic_density: 0.25, feedback: 0.85,
              resampling: 0.5, tension: 0.35, contrast: 0.25 },
    },
    hardgroove: {
      bpm: 134, low_end: :tom_sub, feel: nil,
      elements: %i[kick hat open clap perc_a perc_b low],
      kick: { body_hz: 55.0, sweep_hz: 160.0, sweep_decay: 34.0, amp_decay: 11.0, click_ms: 4.0, drive: 0.4 },
      axes: { pulse: 0.95, microtiming: 0.35, accent: 0.8, density: 0.85, sparsity: 0.25, persistence: 0.45,
              mutation: 0.7, polyrhythm: 0.85, velocity_curve: 0.7, envelope_variance: 0.5,
              spectral_motion: 0.5, spatial_motion: 0.4, harmonic_density: 0.45, feedback: 0.3,
              resampling: 0.3, tension: 0.55, contrast: 0.55 },
    },
    industrial: {
      bpm: 138, low_end: :hybrid, feel: nil,
      elements: %i[kick hat clap perc_a perc_b texture low],
      kick: { body_hz: 50.0, sweep_hz: 220.0, sweep_decay: 26.0, amp_decay: 8.0, click_ms: 5.0, drive: 0.9 },
      axes: { pulse: 1.0, microtiming: 0.1, accent: 0.85, density: 0.65, sparsity: 0.4, persistence: 0.85,
              mutation: 0.3, polyrhythm: 0.45, velocity_curve: 0.8, envelope_variance: 0.4,
              spectral_motion: 0.6, spatial_motion: 0.5, harmonic_density: 0.9, feedback: 0.55,
              resampling: 0.7, tension: 0.85, contrast: 0.8 },
    },
    # Dilla's pocket on a machine: the snare late and the hats holding the grid,
    # at the full GROOVE_FEELS depth rather than hate's two thirds.
    dilla_pocket: {
      bpm: 122, low_end: :kick_tail, feel: :dilla_drag,
      elements: %i[kick hat open clap perc_a stab low],
      kick: { body_hz: 58.0, sweep_hz: 120.0, sweep_decay: 28.0, amp_decay: 10.0, click_ms: 2.5, drive: 0.35 },
      axes: { pulse: 0.7, microtiming: 0.9, accent: 0.6, density: 0.45, sparsity: 0.5, persistence: 0.6,
              mutation: 0.5, polyrhythm: 0.4, velocity_curve: 0.75, envelope_variance: 0.6,
              spectral_motion: 0.4, spatial_motion: 0.35, harmonic_density: 0.5, feedback: 0.4,
              resampling: 0.45, tension: 0.5, contrast: 0.45 },
    },
  }.freeze

  # The arrangement is subtractive. The busiest state is the track's definition
  # -- every element of the profile -- and each section names what it takes away
  # and what it transforms, never what it adds. That is what stops the chorus
  # pile-up: no section can hold an element the full state does not.
  SECTION_MOVES = {
    strip: { remove: %i[clap open stab low], transform: {} },
    ground: { remove: %i[stab open], transform: {} },
    filter: { remove: [], transform: { low: :filtered, stab: :filtered, hat: :filtered } },
    full: { remove: [], transform: {} },
    lift: { remove: %i[low], transform: {} },
    damage: { remove: %i[low stab], transform: { perc_a: :dirty, perc_b: :dirty, clap: :dirty } },
    return: { remove: [], transform: { low: :varied } },
  }.freeze
  SECTION_ORDER = %i[strip ground filter full lift damage return full strip].freeze
  SECTION_BARS = 16

  module_function

  def profile(name)
    PROFILES.fetch(name.to_s.to_sym) do
      raise ArgumentError, "no techno profile #{name.inspect} — try #{PROFILES.keys.join(', ')}"
    end
  end

  def axis(profile, name) = profile.fetch(:axes).fetch(name)

  # Swing is one shape of microtiming, and it lands on the off-sixteenths of the
  # elements that are not the clock. The kick stays where the pulse says: a
  # rigid kick under shifted hats is the style, a global swing is not.
  def timing_offset(profile, element, step, beat)
    return kick_offset(profile, beat) if element == :kick

    step_sec = beat / 4.0
    swing = 0.5 + (axis(profile, :microtiming) * 0.12)
    swung = step.odd? ? ((2.0 * swing) - 1.0) * step_sec : 0.0
    swung + feel_offset(profile, element, beat)
  end

  def kick_offset(profile, beat)
    feel_offset(profile, :kick, beat) * (1.0 - axis(profile, :pulse))
  end

  # GROOVE_FEELS ticks at 96 PPQ, scaled by how far this style lets events drift.
  def feel_offset(profile, element, beat)
    return 0.0 unless profile[:feel]

    ticks = DillaGroove::GROOVE_FEELS.fetch(profile[:feel]).fetch(FEEL_ROLES.fetch(element), 0)
    ticks * axis(profile, :microtiming) * beat / 96.0
  end

  # One bar of one element: [[step, velocity, decay_scale], ...]. `seed` names
  # the render; the same seed, profile, element and bar give the same figure.
  def figure(profile, element, bar, seed:)
    cycle = ELEMENTS.fetch(element).fetch(:cycle_bars)
    steps = (base_steps(profile, element, bar % cycle, bar) + mutation(profile, element, bar, seed)).uniq.sort
    steps = sparse(profile, element, steps, Random.new(seed + (bar * 131) + element_index(element)))
    rng = Random.new(seed ^ ((bar + 1) * 7919) ^ element_index(element))
    steps.map { |step| [step, velocity(profile, step), decay_scale(profile, rng)] }
  end

  def element_index(element) = ELEMENTS.keys.index(element)

  def base_steps(profile, element, variation, bar)
    density = axis(profile, :density)
    case element
    when :kick then [0, 4, 8, 12] + (density > 0.6 && variation.zero? && bar.odd? ? [14] : [])
    when :hat then [2, 6, 10, 14] + DillaGroove.euclidean((density * 8).round, 16, rotation: variation)
    when :open then [2, 6, 10, 14].select.with_index { |_, i| (i + variation).even? || density > 0.7 }
    when :clap then [4, 12] + (variation == 1 && density > 0.5 ? [15] : [])
    when :perc_a then DillaGroove.euclidean(3 + (density * 4).round, 16, rotation: 3 + (variation * 5))
    when :perc_b then polymeter(profile, bar)
    else melodic_steps(element, variation)
    end
  end

  # A figure whose cycle is not a bar at all: indexed by the global step, so it
  # precesses against the kick and meets the downbeat only every few bars.
  def polymeter(profile, bar)
    cycle = 5 + (axis(profile, :polyrhythm) * 6).round
    DillaGroove.polymeter_steps(bar, cycle:, pulses: 2 + (axis(profile, :density) * 3).round)
  end

  def melodic_steps(element, variation)
    case element
    when :stab then [[3, 10], [6], [3, 11], [14]][variation % 4]
    when :texture then variation.zero? ? [0] : []
    else [2, 6, 10, 14]
    end
  end

  # Persistence is how long a figure holds; mutation is whether it changes when
  # the hold runs out. One step toggles per window, and it stays toggled for the
  # whole window, so a change is a new state rather than a fill.
  def mutation(profile, element, bar, seed)
    window = (4 + (axis(profile, :persistence) * 28)).round
    rng = Random.new(seed + ((bar / window) * 104_729) + element_index(element))
    return [] unless rng.rand < axis(profile, :mutation) && element != :kick

    [rng.rand(16)]
  end

  # Silence as the instrument: the hit before an accent goes, so the accent lands
  # on a hole. Downbeats and the backbeat are the accents.
  def sparse(profile, element, steps, rng)
    return steps if %i[kick low].include?(element)

    steps.reject { |step| [0, 4, 8, 12].include?((step + 1) % 16) && rng.rand < axis(profile, :sparsity) * 0.6 }
  end

  def velocity(profile, step)
    weight = if (step % 4).zero? then 1.0 elsif step.even? then 0.5 else 0.2 end
    base = (0.5 + (axis(profile, :accent) * 0.5 * weight)).clamp(0.05, 1.0)
    (base**(0.5 + axis(profile, :velocity_curve))).round(4)
  end

  def decay_scale(profile, rng)
    (1.0 + (((rng.rand * 2.0) - 1.0) * axis(profile, :envelope_variance) * 0.5)).round(4)
  end

  # The sections for a render of `bars`, busiest first when there is room for
  # only one. A window of SECTION_ORDER centred on its first :full, so a short
  # render is the peak and its neighbours rather than an intro that never
  # arrives.
  def sections(bars)
    count = (bars / SECTION_BARS.to_f).ceil.clamp(1, 64)
    return SECTION_ORDER.cycle.first(count) if count > SECTION_ORDER.length

    start = (SECTION_ORDER.index(:full) - ((count - 1) / 2)).clamp(0, SECTION_ORDER.length - count)
    SECTION_ORDER[start, count]
  end

  # One section's state: every element of the full state with a gain and a
  # transform. Removal is not always silence -- low contrast leaves a removed
  # element faintly present, which is how a dub track changes without a cut.
  def section_state(profile, name)
    move = SECTION_MOVES.fetch(name)
    floor = ((1.0 - axis(profile, :contrast)) * 0.3).round(4)
    profile.fetch(:elements).to_h do |element|
      gain = move[:remove].include?(element) ? floor : 1.0
      [element, { gain:, transform: move[:transform][element] }]
    end
  end

  # Where the silence goes at a section's edge. The last bar before a section
  # that has the kick loses it from the third beat -- the return is what the
  # dropout was for -- when this style carries enough tension to want it.
  def dropout_bar?(profile, bar, seed)
    section_end = ((bar + 1) % SECTION_BARS).zero?
    section_end && Random.new(seed + (bar * 613)).rand < axis(profile, :tension)
  end

  # Energy as eight numbers rather than one loudness. Measured from what the
  # section contains, so a style cannot claim energy its state does not hold.
  def energy(profile, name, previous: nil)
    state = section_state(profile, name)
    present = state.select { |_, s| s[:gain] >= 0.5 }.keys
    vector = {
      density: (present.sum { |e| hits_per_bar(profile, e) } / 40.0).clamp(0.0, 1.0),
      brightness: register_share(present, :high, state),
      transient_sharpness: ((present.include?(:kick) ? 0.5 : 0.0) + (present.include?(:hat) ? 0.3 : 0.0) +
                            (dirty_count(state) * 0.1)).clamp(0.0, 1.0),
      spectral_width: (present.map { |e| ELEMENTS[e][:register] }.uniq.length / 4.0).clamp(0.0, 1.0),
      harmonic_density: (axis(profile, :harmonic_density) * (1.0 + (dirty_count(state) * 0.25))).clamp(0.0, 1.0),
      rhythmic_complexity: (present.map { |e| ELEMENTS[e][:cycle_bars] }.uniq.length / 4.0).clamp(0.0, 1.0),
      tension: tension(profile, present, state),
    }
    vector.merge(contrast: previous ? distance(vector, previous) : 0.0).transform_values { |v| v.round(4) }
  end

  def hits_per_bar(profile, element)
    cycle = ELEMENTS.fetch(element).fetch(:cycle_bars)
    (0...cycle).sum { |bar| base_steps(profile, element, bar, bar).uniq.length } / cycle.to_f
  end

  def register_share(present, register, state)
    all = state.keys.select { |e| ELEMENTS[e][:register] == register }
    return 0.0 if all.empty?

    open = present.count { |e| ELEMENTS[e][:register] == register && state[e][:transform] != :filtered }
    (open / all.length.to_f).clamp(0.0, 1.0)
  end

  def dirty_count(state) = state.count { |_, s| s[:transform] == :dirty }

  # Tension is what is withheld: a missing low end or a closed filter under a
  # running kick is anticipation, and a style's tension axis scales how much.
  def tension(profile, present, state)
    withheld = profile[:elements].length - present.length
    filtered = state.count { |_, s| s[:transform] == :filtered }
    (axis(profile, :tension) * (0.4 + (withheld * 0.15) + (filtered * 0.1))).clamp(0.0, 1.0)
  end

  def distance(a, b)
    keys = ENERGY - [:contrast]
    Math.sqrt(keys.sum { |k| (a[k] - b[k])**2 } / keys.length)
  end

  # The profile in `hate`'s and `industrial`'s own knobs, for the renderers that
  # predate it. Only knobs read at render time: HATE_BPM is a constant computed
  # at load, so a profile cannot move hate's tempo and does not pretend to.
  def engine_env(profile)
    a = profile.fetch(:axes)
    {
      "HATE_DILLA" => a[:microtiming] < 0.05 ? "0" : "1",
      "HATE_DILLA_DEPTH" => (a[:microtiming] * 0.9).round(2).to_s,
      "HATE_INTRICATE" => a[:density] >= 0.7 ? "1" : "0",
      "HATE_MODERN" => a[:sparsity] >= 0.5 && a[:harmonic_density] < 0.5 ? "1" : "0",
      "HATE_TUNNEL" => a[:feedback] >= 0.6 ? "1" : "0",
      "HATE_DFAM_HEAVY" => a[:harmonic_density] >= 0.75 ? "1" : "0",
      "HATE_PAULSTRETCH" => [a[:spatial_motion], a[:resampling]].max >= 0.5 ? "1" : "0",
      "HATE_WEIRD" => a[:resampling] >= 0.6 ? "1" : "0",
      "HATE_MELODY" => profile[:elements].include?(:stab) ? "1" : "0",
      "IBPM" => profile[:bpm].to_s,
    }
  end

  # A knob the operator set by hand wins over the profile, the rule DillaMacros
  # already keeps. Returns what was applied, so the caller can say it.
  def apply_env!(env, target = ENV)
    env.reject { |key, _| target.key?(key) }.each { |key, value| target[key] = value }
  end
end

# Notes as data, and what a player does to them.
#
# Every renderer here decides its notes and plays them in the same method, so a
# note can be placed but never reworked: nothing can take a stated motif and play
# it backwards, ratchet a hat or ghost a snare without rewriting the renderer.
# An Event is a note that has not sounded yet. Pitch is MIDI, and a drum voice is
# its General MIDI number; velocity is 0..1; time and duration are seconds;
# probability is the odds it plays; articulation is how it is struck; expression
# is whatever else the renderer reads. Each transform takes events and returns
# new ones, and the randomness is the rng handed in, so a seed replays a take.
module DillaEvents
  Event = Data.define(:pitch, :velocity, :duration, :at, :probability, :articulation, :expression) do
    def self.note(pitch:, at:, velocity: 0.8, duration: 0.25, probability: 1.0, articulation: :normal, expression: {})
      new(pitch:, velocity:, duration:, at:, probability:, articulation:, expression:)
    end
  end

  module_function

  def humanize(events, rng, ms: 12.0, spread: 0.1)
    events.map do |event|
      late = ((rng.rand * 2.0) - 1.0) * ms / 1000.0
      level = 1.0 + (((rng.rand * 2.0) - 1.0) * spread)
      event.with(at: [event.at + late, 0.0].max, velocity: (event.velocity * level).clamp(0.0, 1.0))
    end
  end

  # The off-sixteenths late by a share of a step; 0.5 is straight.
  def swing(events, step, amount)
    events.map { |event| (event.at / step).round.odd? ? event.with(at: event.at + (((2.0 * amount) - 1.0) * step)) : event }
  end

  def shift(events, seconds) = events.map { |event| event.with(at: [event.at + seconds, 0.0].max) }

  def stretch(events, factor) = events.map { |event| event.with(at: event.at * factor, duration: event.duration * factor) }

  def reverse(events, span) = events.map { |event| event.with(at: [span - event.at - event.duration, 0.0].max) }.sort_by(&:at)

  def repeat(events, span, times) = (0...times).flat_map { |n| shift(events, span * n) }

  # Each note struck `count` times inside its own length, falling away.
  def ratchet(events, count, decay: 0.8)
    events.flat_map do |event|
      gap = event.duration / count
      Array.new(count) { |n| event.with(at: event.at + (gap * n), duration: gap, velocity: event.velocity * (decay**n), articulation: :ratchet) }
    end
  end

  # A quiet copy a step before some notes: the grace a drummer leaves.
  def ghost(events, rng, step, odds:, level: 0.3)
    graces = events.filter_map do |event|
      event.with(at: event.at - step, velocity: event.velocity * level, articulation: :ghost) if event.at >= step && rng.rand < odds
    end
    events + graces
  end

  # The notes on a beat harder than the notes between.
  def accent(events, beat, amount: 1.25)
    events.map do |event|
      position = event.at / beat
      (position - position.round).abs < 0.02 ? event.with(velocity: (event.velocity * amount).clamp(0.0, 1.0)) : event
    end
  end

  def drop(events, rng, odds) = events.reject { rng.rand < odds }

  def transpose(events, semitones) = events.map { |event| event.with(pitch: event.pitch + semitones) }

  # Mirrored about a pitch, so a rising line falls by the same steps.
  def invert(events, axis) = events.map { |event| event.with(pitch: (2 * axis) - event.pitch) }

  # A held note cut into slices with air between them, as a sampler chop plays it.
  def chop(events, pieces)
    events.flat_map do |event|
      slice = event.duration / pieces
      Array.new(pieces) { |n| event.with(at: event.at + (slice * n), duration: slice * 0.8, articulation: :chop) }
    end
  end

  # The first slice said `repeats` times, over whatever it covered.
  def stutter(events, slice, repeats)
    head = events.select { |event| event.at < slice }
    return events if head.empty?

    repeat(head, slice, repeats) + events.reject { |event| event.at < slice * repeats }
  end

  def probabilize(events, odds) = events.map { |event| event.with(probability: event.probability * odds) }

  # Which notes play this time: the dice a probability promised, thrown once.
  def realize(events, rng) = events.select { |event| rng.rand < event.probability }

  def quantize(events, step, strength: 1.0)
    events.map { |event| event.with(at: event.at + ((((event.at / step).round * step) - event.at) * strength)) }
  end

  # Played slower, the way a sampler slows a record: later, longer and lower
  # together. Never faster, because a sample here is a slowed short idea.
  def resample(events, rate)
    raise ArgumentError, "a sample is slowed, never sped up (rate #{rate})" if rate > 1.0

    events.map { |event| event.with(at: event.at / rate, duration: event.duration / rate, pitch: event.pitch + (12.0 * Math.log2(rate))) }
  end
end

# Macro/micro rhythm — tempo ramps, stripdown, gap rhythm, prime bars.
module DillaRhythm
  @ctx = { n_bars: 16, base_bpm: 90.0, duration: 32.0 }

  module_function

  def configure!(n_bars:, bpm:, duration: nil)
    @ctx = { n_bars:, base_bpm: bpm.to_f, duration: duration || (60.0 / bpm * 4 * n_bars) }
  end

  def ctx
    @ctx
  end

  def bar_bpm(bar)
    n = @ctx[:n_bars]
    base = @ctx[:base_bpm]
    return base unless macro_enabled?

    return staircase_bpm(bar, base) if ENV["BPM_STAIRCASE"] == "1"
    return ramp_bpm(bar, n, base) if ENV["TEMPO_RAMP"] == "1"
    return accel_bpm(bar, n, base) if ENV["TEMPO_ACCEL"] == "1"
    base
  end

  def macro_enabled?
    ENV["RHYTHM_MACROS"] != "0"
  end

  def ramp_bpm(bar, n_bars, base)
    steps = (n_bars / 4.0).ceil
    base + (bar / 4) * (ENV["TEMPO_RAMP_STEP"] || 1).to_f
  end

  def accel_bpm(bar, n_bars, base)
    mult = 1.0 + (bar.to_f / [n_bars, 1].max) * 0.01 * (ENV["TEMPO_ACCEL_PCT"] || 1).to_f
    base * mult
  end

  def staircase_bpm(bar, base)
    base + bar * (180.0 - 60.0) / [(@ctx[:n_bars] - 1), 1].max
  end

  def bar_duration_sec(bar, _beat_p)
    bpm = bar_bpm(bar)
    (60.0 / bpm) * 4.0
  end

  def stripdown_gain(bar, section)
    return 1.0 unless macro_enabled? && ENV["STRIPDOWN"] == "1"
    n = @ctx[:n_bars]
    return 1.0 if section != :main
    progress = bar.to_f / n
    1.0 - (progress * 0.35)
  end

  def element_strip_gain(elapsed_sec)
    return 1.0 unless macro_enabled? && ENV["ELEMENT_STRIP"] == "1"
    removed = (elapsed_sec / 10.0).floor
    [1.0 - removed * 0.08, 0.25].max
  end

  def subdivision_density_steps(base_steps, bar)
    return base_steps unless macro_enabled? && ENV["SUB_DENSITY"] == "1"
    extra = (0..15).select { |s| s % 2 == 0 && Random.new(bar).rand < 0.4 }
    (base_steps + extra).uniq.sort
  end

  # Periodic full-layer drop-out — "remove elements periodically for
  # contrast" rather than stripdown's one-way fade to silence. Ducks (not
  # mutes) for `span` bars every `period` bars; never on bar 0, so the
  # arrangement is fully established before the first variation.
  def periodic_layer_drop_gain(bar, period: 8, span: 1)
    return 1.0 unless macro_enabled? && ENV["ARRANGEMENT_VARIATION"] != "0"
    return 1.0 if period <= 0 || bar.zero?
    (bar % period) < span ? 0.12 : 1.0
  end
end
