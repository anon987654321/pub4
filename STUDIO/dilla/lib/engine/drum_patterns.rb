# frozen_string_literal: true
#
# Drum pattern, fill and feel tables.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Curated 16-step drum phrases per feel — rotated bar-to-bar instead of
# probabilistic organic generation. Kicks/snares/ghosts/hats are authored
# separately so each voice has its own pocket.
DRUM_PATTERN_SETS = {
  # LIQUID DNB. The two-step, at 170-176.
  #
  # Kick on 1, snare on 2, kick on the "and" of 3, snare on 4 -- steps 0, 4, 10,
  # 12 on this grid. That displaced second kick is the whole genre: it is what
  # makes the bar roll forward instead of marching, and moving it onto 8 turns
  # liquid into halftime.
  #
  # Liquid rather than neurofunk or jump-up, which matters for what is NOT here.
  # No chopped amen, no snare rushes, no double-time fills. The kit stays out of
  # the way and the harmony carries the track -- the style is defined by lush
  # Rhodes and strings over a break that barely changes, which is why the
  # variations below move ghosts and hats and almost never touch the anchors.
  #
  # Hats roll in 16ths. At 174 bpm a 16th is 86 ms, so a straight roll reads as
  # continuous motion rather than as separate hits, and that shimmer is what
  # people mean by "rolling".
  #
  # Ghosts sit between the snares, quiet, on the 16ths either side of the
  # backbeat. They are the difference between a programmed break and one that
  # sounds played.
  liquid_dnb: {
    kicks: [
      [0, 10], [0, 10], [0, 10, 14], [0, 6, 10],
      [0, 10], [0, 3, 10], [0, 10, 11], [0, 10],
    ],
    snares: [[4, 12], [4, 12], [4, 12], [4, 12, 15], [4, 12], [4, 12, 14]],
    ghosts: [[2, 7, 14], [6, 14], [2, 6, 11, 14], [7, 15], [2, 14], [6, 9, 14]],
    hats: [
      (0..15).to_a, (0..15).to_a,
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14],
      [0, 2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15],
      (0..15).to_a,
    ],
  },
  # ONE DROP. Roots reggae, the Hugh Mundell / Augustus Pablo end of it.
  #
  # The defining feature is a hole, not a hit: step 0 is empty. Kick and snare
  # land together on beat 3 (step 8) and the bar "drops" onto it. Every other
  # pattern in this file anchors the downbeat, so this is the one that must not
  # -- put a kick on 0 and it stops being a one drop and becomes a slow
  # rocksteady, which is a different genre.
  #
  # The rim/side-stick doubling the snare on 8 is the reggae sound rather than a
  # backbeat crack; it is voiced through the ghost lane because that is the
  # quiet lane this engine already has.
  #
  # Hats on the offbeats only. The skank -- the guitar/organ chop on the "and"
  # of every beat -- is harmonic, not percussive, so it is not here; it belongs
  # to the pad layer and is what a future DUB rack would carve around.
  #
  # Additive, like the canon pockets below: nothing changes unless GROOVE_FEEL
  # asks for it.
  one_drop: {
    kicks: [
      [8], [8], [8, 14], [8], [6, 8], [8, 15], [8], [8, 11],
    ],
    snares: [[8], [8], [8], [8, 14], [8], [8]],
    ghosts: [[8], [8, 12], [8], [4, 8], [8], [8, 10]],
    hats: [
      [2, 6, 10, 14], [2, 6, 10, 14], [2, 6, 10, 14, 15],
      [2, 4, 6, 10, 12, 14], [2, 6, 10, 14],
    ],
  },
  # The two canon pockets, played rather than described.
  #
  # RADIO_BERGEN dossiers carry these as prose -- "MPC swing 54-62%; kick late-3
  # anchor; snare early on 4/12; ghost on 2/10" for dilla_canon, "wonky_abstract
  # broken 16ths; kick 0,5,8,13; displaced snares" for wonky_canon. Those strings
  # sit in a dossier hash near DOSSIERS_PATH; the drums come from
  # drum_pattern_pick, which is keyed on feel and has never seen them. So the
  # engine documented a pocket it did not play, in the two styles it is most
  # often asked for.
  #
  # Transcribed here from those specs and nowhere else -- the anchors are the
  # dossier's, and the variation around them follows the house shape of the pools
  # below (a fixed anchor pair plus movement). Added as new feels rather than
  # edits to existing ones, so no render changes unless GROOVE_FEEL asks.
  dilla_canon: {
    # Every kick anchors 0 and the late 3. 10 is the second anchor, which is what
    # makes the bar lean without the snare having to move.
    kicks: [
      [0, 3, 10], [0, 3, 10, 14], [0, 3, 7, 10], [0, 3, 10, 13],
      [0, 2, 3, 10], [0, 3, 6, 10, 15], [0, 3, 9, 10], [0, 3, 11],
    ],
    # 4 and 12 held. "Early" is timing, not grid -- GROOVE_FEEL supplies it.
    snares: [[4, 12], [4, 12], [4, 12, 14], [4, 11, 12], [4, 12], [3, 4, 12]],
    ghosts: [[2, 10], [2, 6, 10], [2, 10, 14], [2, 5, 10], [2, 10, 13], [1, 2, 10]],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3], [0, 2, 4, 6, 8, 10, 12, 14, 11],
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 3, 6, 9, 12, 15],
      [0, 2, 4, 6, 8, 10, 12, 14],
    ],
    opens: [6, 14],
  },
  # The kick here is quoted exactly: 0, 5, 8, 13. Snares are displaced off 4/12
  # rather than sitting on them, which is what "displaced" buys -- the backbeat
  # stops being a reference point and the bar reads broken.
  wonky_canon: {
    kicks: [
      [0, 5, 8, 13], [0, 5, 8, 13, 15], [0, 5, 9, 13], [0, 4, 8, 13],
      [0, 5, 8, 12], [0, 3, 5, 8, 13],
    ],
    snares: [[5, 13], [4, 13], [5, 12], [6, 13], [4, 11], [5, 14]],
    ghosts: [[2, 7, 11, 15], [1, 6, 10, 14], [3, 9, 14], [2, 6, 11], [1, 7, 12]],
    hats: [
      [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15], [0, 2, 3, 5, 6, 8, 9, 11, 12, 14],
      [1, 2, 4, 5, 7, 8, 10, 11, 13, 14], [0, 3, 4, 7, 8, 11, 12, 15],
    ],
    opens: [7, 15],
  },
  # Detroit stumble — the kick is the erratic one.
  #
  # dilla_canon anchors every kick on 0 and the late 3 and lets snare and hat
  # carry the lean. The microtiming literature describes the opposite balance:
  # "21st Century Funk" (Academia) analyses Dilla's early beats and finds the
  # KICK the unstable element against stable snare and hi-hat, with 10 of 13
  # kick notes in one measure falling outside typical metric locations. Ethan
  # Hein's Ableton analysis of "Get Dis Money" agrees on the other two: the
  # backbeat sits a touch EARLY and the hats late, and because the ear orients
  # on the loud backbeat, everything else is heard as dragging behind it.
  #
  # So here the snare never moves — [4, 12] in every single bar, deliberately
  # repeated rather than varied — and the hats stay an even eighth grid. All of
  # the variation is in the kick, which lands somewhere different every bar.
  # That is a stumble rather than a lean, and a stumble is what "tipsy" means.
  #
  # Timing, not grid: the early backbeat and late hat come from GROOVE_FEEL, the
  # same way dilla_canon's do. This table only says WHICH sixteenth, never how
  # far off it sits.
  detroit_stumble: {
    kicks: [
      [0, 3, 6, 10], [0, 2, 7, 10, 14], [0, 3, 9, 11], [0, 5, 10, 13],
      [0, 3, 6, 11, 14], [0, 2, 6, 10], [0, 4, 7, 10, 15], [0, 3, 8, 10, 13],
      [0, 6, 10, 12], [0, 3, 7, 14],
    ],
    snares: [[4, 12], [4, 12], [4, 12], [4, 12], [4, 12], [4, 12]],
    # Ghosts on the sixteenth before each backbeat and trailing off it: the
    # unaccented chatter that makes a programmed bar breathe. 3 and 11 lead into
    # the snare, 6 and 14 fall out of it.
    ghosts: [
      [3, 6, 11, 14], [3, 7, 11, 14], [2, 6, 11, 15], [3, 6, 10, 14],
      [1, 3, 11, 13], [3, 6, 9, 11, 14],
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14], [0, 2, 4, 6, 8, 10, 12, 14],
      [0, 2, 4, 6, 8, 10, 12, 14], [0, 2, 4, 6, 8, 10, 12, 14],
    ],
    opens: [6, 14],
  },
  # LA beat scene — Knxwledge/Teebs/Samiyam side of the lineage.
  #
  # wonky_canon displaces the snare off 4/12 so the backbeat stops being a
  # reference. This keeps that but thins everything around it: the kick is
  # sparse and never on 8, the hats leave whole beats empty, and the ghosts do
  # the work the hats stop doing. Space is the instrument here — the LA records
  # are quiet in the middle of the bar in a way the Detroit ones are not.
  la_beat_scene: {
    kicks: [
      [0, 6, 11], [0, 7, 10], [0, 5, 11, 14], [0, 6, 9],
      [0, 7, 12], [0, 3, 6, 11], [0, 6, 13], [0, 5, 9, 14],
    ],
    snares: [[5, 12], [4, 13], [5, 13], [6, 12], [4, 12], [5, 11]],
    ghosts: [
      [2, 3, 7, 9, 14], [1, 3, 8, 10, 15], [2, 7, 9, 13, 14],
      [3, 6, 10, 14], [1, 2, 8, 11, 15], [2, 4, 9, 14],
    ],
    hats: [
      [0, 3, 6, 8, 11, 14], [0, 2, 5, 8, 10, 13],
      [2, 5, 7, 10, 13, 15], [0, 4, 7, 11, 14],
    ],
    opens: [8, 15],
  },
  timeless: {
    kicks: [
      [0, 8, 10, 15], [0, 3, 9, 11, 14], [0, 6, 10, 13], [0, 2, 7, 10, 14],
      [0, 5, 9, 12, 15], [0, 1, 8, 11, 14], [0, 4, 7, 10, 13], [0, 3, 6, 10, 14],
      [0, 7, 11, 14], [0, 2, 5, 9, 13], [0, 8, 12, 15], [0, 4, 10, 14],
    ],
    snares: [[4, 12], [4, 12], [4, 11, 12], [4, 10, 12], [4, 12, 14], [3, 12]],
    ghosts: [
      [2, 5, 9, 13], [1, 6, 10, 14], [3, 7, 11, 15], [2, 6, 10, 13],
      [1, 4, 8, 12], [3, 5, 9, 14], [2, 7, 11], [1, 5, 10, 13],
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 1, 3, 5, 7, 9, 11, 13, 15],
      [0, 2, 4, 6, 8, 10, 12, 14, 1, 9], [0, 2, 4, 6, 8, 10, 12, 14, 5, 13],
      [0, 3, 6, 9, 12, 15, 2, 8, 14], [0, 2, 4, 6, 8, 10, 12, 14, 7, 11],
    ],
    opens: [6, 14],
  },
  loose_pocket: {
    kicks: [
      [0, 5, 9, 13], [0, 2, 7, 11, 14], [0, 6, 10, 15], [0, 3, 8, 12, 14],
      [0, 1, 6, 10, 13], [0, 4, 7, 11, 15], [0, 2, 9, 12, 14], [0, 5, 8, 10, 14],
      [0, 3, 7, 10, 13], [0, 6, 11, 14],
    ],
    snares: [[4, 12], [3, 11, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12], [4, 12]],
    ghosts: [
      [1, 3, 5, 7, 9, 11, 13, 15], [2, 4, 6, 8, 10, 12, 14], [1, 4, 7, 10, 13],
      [3, 6, 9, 12, 15], [2, 5, 8, 11, 14], [1, 5, 9, 13], [3, 7, 11, 15], [2, 6, 10],
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 1, 5, 9, 13], [0, 2, 4, 6, 8, 10, 12, 14, 3, 7, 11, 15],
      [0, 1, 3, 4, 6, 8, 10, 12, 14], [0, 2, 4, 6, 8, 10, 12, 14, 5, 13],
      [0, 2, 4, 6, 8, 10, 12, 14, 1, 9], [0, 2, 4, 6, 8, 10, 12, 14, 7, 15],
    ],
    opens: [6, 10, 14],
  },
  syncopated_slash_ninth: {
    kicks: [
      [0, 7, 11, 14], [0, 3, 8, 10, 14], [0, 5, 9, 13], [0, 2, 6, 10, 15],
      [0, 4, 7, 11, 14], [0, 1, 7, 10, 13], [0, 6, 9, 12, 14], [0, 3, 7, 11, 15],
    ],
    snares: [[4, 12], [4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12], [4, 9, 12]],
    ghosts: [
      [2, 5, 8, 12], [3, 6, 10, 14], [1, 4, 9, 13], [2, 7, 11, 15],
      [3, 5, 10, 13], [1, 6, 11, 14],
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 2, 4, 6, 8, 10, 12, 14, 3, 7, 11, 15],
      [0, 4, 8, 12, 3, 11], [0, 2, 4, 6, 8, 10, 12, 14, 1, 3, 9, 11],
    ],
    opens: [6, 14],
  },
  chromatic_planing: {
    kicks: [
      [0, 4, 8, 12], [0, 3, 6, 9, 12, 15], [0, 2, 5, 8, 11, 14], [0, 1, 4, 7, 10, 13],
      [0, 5, 9, 13], [0, 2, 6, 10, 14], [0, 4, 7, 11, 14], [0, 3, 8, 12, 15],
    ],
    snares: [[4, 12], [4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12]],
    ghosts: [
      [2, 6, 10, 14], [1, 5, 9, 13], [3, 7, 11, 15], [2, 5, 9, 12, 14],
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14], [1, 3, 5, 7, 9, 11, 13, 15],
      [0, 2, 4, 6, 8, 10, 12, 14], [1, 3, 5, 7, 9, 11, 13, 15],
    ],
    opens: [6, 14],
  },
  organic: {
    kicks: [
      [0, 8, 11, 14], [0, 4, 7, 10, 14], [0, 3, 6, 10, 13], [0, 5, 9, 12, 15],
      [0, 2, 7, 10, 14], [0, 1, 6, 9, 13], [0, 4, 8, 11, 14], [0, 3, 7, 10, 14],
    ],
    snares: [[4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12], [4, 9, 12]],
    ghosts: [
      [3, 6, 10, 13], [2, 5, 9, 14], [1, 7, 11, 15], [4, 8, 12],
      [3, 5, 8, 11], [2, 6, 10, 14],
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 1, 3, 4, 6, 8, 10, 12, 14],
      [0, 2, 4, 6, 8, 10, 12, 14, 1, 9, 13], [0, 2, 4, 6, 8, 10, 12, 14, 5, 7],
    ],
    opens: [6, 14],
  },
  techno_house: {
    kicks: [[0, 4, 8, 12]],
    snares: [[4, 12], [4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12]],
    ghosts: [[10], [6, 10], [10, 14], []],
    hats: [
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
      [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15],
      [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15],
      [0, 2, 4, 5, 7, 8, 10, 11, 13, 14],
    ],
    opens: [6, 14],
  },
  # ==========================================================================
  # Feels for dancing (2026-07-30).
  #
  # Everything above this line is written for the head and the shoulders: the
  # Dilla pocket, the drunk lean, the loose behind-the-beat snare. Nothing in it
  # asks the hips a question. :techno_house was the whole dance vocabulary --
  # one four-on-the-floor grid, kicks [[0,4,8,12]], no variations at all -- so
  # "danceable" in this engine meant "the kick is on every beat", which is the
  # least interesting way anything has ever been danceable.
  #
  # These are nine specific answers instead. Each one is a real rhythmic
  # tradition reduced to its skeleton, and what they mostly have in common is
  # what they do with the SPACE between the kicks, not the kicks: the tresillo's
  # 3+3+2 limp, the two-step's missing downbeat, dembow's snare that lands
  # everywhere the backbeat is not. Grids are 16 sixteenths; swing and timing
  # come from the preset, not from here.
  # ==========================================================================

  # UK garage. The kick abandons beat 3 and turns up late instead, so the bar
  # tips forward and never quite lands -- two steps where four should be. The
  # hats do the walking that the kick refuses to.
  two_step: {
    kicks: [
      [0, 10], [0, 6, 10], [0, 10, 14], [0, 3, 10], [0, 10, 11],
      [0, 6, 10, 14], [0, 5, 10], [0, 10, 13],
    ],
    snares: [[4, 12], [4, 12], [4, 12, 14], [4, 11, 12], [4, 12, 15]],
    ghosts: [[7], [2, 7], [7, 14], [2, 7, 14], [6, 13], [3, 7, 11]],
    hats: [
      [0, 2, 3, 5, 6, 8, 10, 11, 13, 14], [0, 2, 4, 6, 7, 10, 12, 14],
      [0, 3, 4, 6, 8, 11, 12, 14], [2, 3, 6, 7, 10, 11, 14, 15],
      [0, 2, 3, 6, 8, 10, 11, 14],
    ],
    opens: [6, 14],
  },
  # West London broken beat. Every limb displaced off the grid it belongs on,
  # and the whole thing still walks. The kick pattern changes every bar on
  # purpose: bruk is defined by never repeating the same bar twice.
  broken_beat: {
    kicks: [
      [0, 3, 6, 11], [0, 5, 8, 11, 14], [0, 2, 7, 10, 13], [0, 4, 9, 12, 15],
      [0, 6, 9, 14], [0, 3, 8, 13], [0, 5, 7, 12], [0, 2, 9, 11, 14],
    ],
    snares: [[4, 12], [4, 10, 12], [3, 12], [4, 12, 15], [4, 9, 12]],
    ghosts: [[2, 5, 9, 13], [1, 6, 11, 14], [3, 7, 10, 15], [2, 8, 13], [5, 9, 14]],
    hats: [
      [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15], [0, 2, 3, 5, 7, 8, 10, 12, 14, 15],
      [0, 2, 4, 5, 7, 9, 11, 12, 14], [1, 2, 4, 6, 8, 9, 11, 13, 15],
    ],
    opens: [6, 10, 14],
  },
  # Amapiano. Four on the floor underneath, and everything else deliberately
  # between the beats -- the shaker, the log drum, the whole top end sitting on
  # the offbeat sixteenth. The kick is not the groove here; it is the floor the
  # groove happens above.
  amapiano_offbeat: {
    kicks: [[0, 4, 8, 12], [0, 4, 8, 12, 14], [0, 4, 6, 8, 12], [0, 4, 8, 12, 15]],
    snares: [[4, 12], [12], [4, 12, 14], [4, 12]],
    ghosts: [[2, 6, 10, 14], [3, 7, 11, 15], [6, 14], [2, 10], [6, 11, 14]],
    hats: [
      [2, 6, 10, 14], [2, 6, 10, 14, 15], [2, 3, 6, 7, 10, 11, 14, 15],
      [0, 2, 4, 6, 8, 10, 12, 14],
    ],
    opens: [2, 6, 10, 14],
  },
  # Dembow. The snare goes everywhere the backbeat is not -- and, because the
  # engine's whole rhythmic assumption is a snare on 4 and 12, that is exactly
  # why it belongs here. Half the variations keep the backbeat anyway so the
  # feel can sit under a track that needs one.
  dembow: {
    kicks: [[0, 8], [0, 6, 8, 14], [0, 8, 10], [0, 3, 8, 11], [0, 8, 11]],
    snares: [[3, 6, 11, 14], [3, 6, 11, 14], [4, 12], [3, 7, 11, 14], [4, 6, 12, 14]],
    ghosts: [[2, 10], [5, 13], [1, 9], [2, 7, 10, 15]],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14], [0, 2, 3, 4, 6, 8, 10, 11, 12, 14],
      [0, 4, 8, 12], [0, 2, 4, 6, 8, 10, 12, 14, 15],
    ],
    opens: [6, 14],
  },
  # 3+3+2. The tresillo -- one bar of sixteenths cut into unequal pieces, which
  # is the single most widespread rhythmic cell on earth and reaches this file
  # from about six directions at once. Four on the floor keeps time under it in
  # half the variations; in the other half nothing does, and it still works.
  tresillo_house: {
    kicks: [
      [0, 3, 6, 8, 11, 14], [0, 3, 6, 8], [0, 6, 8, 14], [0, 3, 8, 11],
      [0, 4, 8, 12], [0, 3, 6, 10, 14],
    ],
    snares: [[4, 12], [4, 12], [4, 12, 14], [4, 11, 12]],
    ghosts: [[2, 10], [5, 13], [7, 15], [2, 6, 10, 14]],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14], [0, 1, 2, 4, 6, 8, 9, 10, 12, 14],
      [0, 3, 6, 8, 11, 14], [2, 6, 10, 14],
    ],
    opens: [6, 14],
  },
  # Disco. Kick on all four, open hat on all four offbeats, and that alternation
  # -- down, up, down, up -- is the entire engine. Everything else in the record
  # is decoration on top of two sounds trading places.
  disco_boogie: {
    kicks: [[0, 4, 8, 12], [0, 4, 8, 12], [0, 4, 8, 12, 15], [0, 4, 7, 8, 12]],
    snares: [[4, 12], [4, 12], [4, 12, 14], [4, 12, 13]],
    ghosts: [[2, 6, 10, 14], [6, 14], [10], [6, 10, 14]],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14],
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
      [2, 6, 10, 14], [0, 2, 3, 6, 8, 10, 11, 14],
    ],
    opens: [2, 6, 10, 14],
  },
  # Batucada. The surdo answers on the second beat rather than announcing the
  # first, so the bar leans backwards into itself, and the caixa fills every
  # sixteenth above it. The one feel here where the busiest layer is the quietest.
  batucada: {
    kicks: [[0, 8], [0, 6, 8, 14], [0, 8, 11], [3, 8, 11], [0, 8, 10, 14]],
    snares: [[4, 12], [4, 10, 12], [2, 6, 10, 14], [4, 12, 14]],
    ghosts: [
      [1, 3, 5, 7, 9, 11, 13, 15], [2, 3, 6, 7, 10, 11, 14, 15],
      [1, 2, 5, 6, 9, 10, 13, 14], [0, 3, 6, 10, 12],
    ],
    hats: [
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
      [0, 2, 3, 5, 6, 8, 10, 11, 13, 14], [0, 3, 6, 10, 12],
      [0, 1, 3, 4, 6, 8, 9, 11, 12, 14],
    ],
    opens: [6, 14],
  },
  # Footwork. Kicks arriving in threes against a bar counted in fours, so the
  # pattern crosses itself every bar and lands back on the downbeat only
  # occasionally. Sparse up top: the density is all in the low end.
  footwork_triplet: {
    kicks: [
      [0, 3, 6, 8, 11, 14], [0, 1, 2, 8, 9, 10], [0, 3, 5, 8, 11, 13],
      [0, 2, 4, 8, 10, 12], [0, 5, 10, 15], [0, 3, 6, 9, 12, 15],
    ],
    snares: [[4, 12], [12], [4, 12], [12, 14]],
    ghosts: [[2, 6, 10, 14], [1, 5, 9, 13], [7, 15], [3, 11]],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14], [0, 3, 6, 9, 12, 15],
      [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15], [0, 4, 8, 12],
    ],
    opens: [6, 14],
  },
  # Afrobeats. A kick on the one, one just after the halfway point and one on
  # the last beat's front edge -- 0, 6, 10, which is the tresillo again, worn
  # loosely -- under a shaker riding the offbeats and a rim playing clave.
  afrobeats_pocket: {
    kicks: [[0, 6, 10], [0, 6, 10, 14], [0, 3, 6, 10], [0, 6, 8, 10], [0, 6, 10, 13]],
    snares: [[4, 12], [4, 12], [4, 12, 14], [4, 11, 12]],
    ghosts: [[2, 7, 12, 14], [0, 3, 6, 10, 12], [2, 5, 9, 13], [3, 10, 14]],
    hats: [
      [2, 6, 10, 14], [0, 2, 4, 6, 8, 10, 12, 14],
      [2, 3, 6, 7, 10, 11, 14, 15], [0, 2, 4, 6, 7, 8, 10, 12, 14, 15],
    ],
    opens: [6, 14],
  },

  default: {
    kicks: [
      [0, 7, 10, 14], [0, 3, 8, 11, 14], [0, 5, 9, 13], [0, 2, 6, 10, 14],
      [0, 4, 7, 11, 15], [0, 1, 7, 10, 13], [0, 6, 10, 14], [0, 3, 7, 10, 12, 14],
    ],
    snares: [[4, 12], [4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12]],
    ghosts: [
      [2, 5, 9, 13], [3, 6, 11, 14], [1, 4, 8, 12], [2, 7, 10, 15],
      [3, 5, 9, 12], [1, 6, 10, 13],
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 1, 3, 4, 6, 8, 10, 11, 13, 14],
      [0, 2, 4, 6, 8, 10, 12, 14], [0, 2, 4, 6, 8, 10, 12, 14, 1, 9],
    ],
    opens: [6, 14],
  },
}.merge(
  DillaLofiMachine::DRUM_PRESETS.transform_values do |p|
    {
      kicks: [p[:kicks]],
      snares: [p[:snares]],
      hats: [p[:hats]],
      ghosts: [p[:ghosts]],
      opens: [6, 14],
      claps: [p[:claps]],
      perc: [p[:perc]],
    }
  end,
).freeze

LOFI_DRUM_FEELS = DillaLofiMachine::DRUM_PRESETS.keys.freeze

# Authored fill phrases — snare runs, kick clusters, ghost chatter into phrase ends.
DRUM_FILL_SETS = {
  snare: [
    [10, 11, 12, 13, 14, 15], [8, 9, 10, 11, 12, 14], [6, 8, 10, 12, 13, 14, 15],
    [9, 10, 11, 12, 14, 15], [11, 12, 13, 14, 15], [8, 10, 12, 13, 14, 15],
    # Every fill above accelerates into the turn -- the run gets denser as it
    # approaches 15, which is the one gesture a drum machine reaches for first.
    # These do something else with the same eight steps: a fill that thins out
    # instead (the bar emptying rather than filling), one that stutters a single
    # step, and one built out of triplets against the sixteenths.
    [8, 9, 10, 12, 14], [8, 10, 12, 15], [12, 13, 15],
    [9, 12, 15], [8, 11, 14], [10, 13, 15], [8, 9, 11, 12, 14, 15],
  ],
  kicks: [
    [12, 13, 14, 15], [10, 12, 14, 15], [8, 10, 12, 14, 15], [13, 14, 15], [11, 13, 15],
    [8, 11, 14], [10, 13], [9, 12, 15], [8, 9, 12, 13, 15],
  ],
  ghosts: [
    [13, 14, 15], [11, 13, 15], [12, 14, 15], [10, 12, 14, 15],
    [9, 11, 13, 15], [8, 10, 13], [11, 12, 14], [8, 9, 10, 11, 12, 13, 14, 15],
  ],
}.freeze

# Wonky abstract overlay — second drum schedule on top of Dilla pocket (wonky 16ths).
WONKY_OVERLAY_SECTION_DENSITY = {
  intro: 0.42, main: 1.0, build: 0.88, turn: 0.92, breakdown: 0.35, outro: 0.48,
}.freeze
WONKY_OVERLAY_FORM_MUL = {
  intro: 0.55, main: 1.0, build: 0.92, turn: 0.95, breakdown: 0.38, outro: 0.5,
}.freeze
WONKY_OVERLAY_SECTION_SHIFT = {
  intro: 0, main: 2, build: 4, turn: 6, breakdown: 1, outro: 3,
}.freeze
WONKY_OVERLAY_GRID_COUNT = 8

MELODY_CHOP_HZ = [392.00, 349.23, 311.13, 277.18, 261.63, 233.08].freeze

# The lead's amplitude, and the one knob that scales it.
#
# The drum, harmony and bass buses each have a mix weight; the lead had none, so
# its level was a literal inside the synthesis loop and could not be moved
# without editing the renderer. Rendered alone it measures -51.0 dB against the
# kit's -31.3 -- about 20 dB down, which is why a lead is inaudible in a default
# mix and why there was no way to answer that by turning something.
#
# LEAD_MIX_WEIGHT defaults to 1.0, which is exactly the previous literal. Raising
# it is a tone decision and belongs to the operator.
MELODY_BASE_GAIN = 0.11

def resolved_lead_mix_weight
  ENV.fetch("LEAD_MIX_WEIGHT", "1.0").to_f.clamp(0.0, 8.0)
end
LOOSE_POCKET_TIMING_MS = {
  snare: -28..-12, ghost: -10..18, hat_down: 8..18, hat_up: 22..40,
  kick_anchor: 0..6, kick_sync: 10..22,
}.freeze
# Linda Perhacs "Delicious" layer calibration — beat at 0.72x ≈ 65 BPM native (minor_soul_loop 90 * 0.72).
DELICIOUS_POCKET_RATIO = 0.72
# VLC Tools > Effects and Filters — all tabs enabled (EQ, compressor, spatializer, widener, normalize).
VLC_EQ_BANDS = [
  [60, 4.5], [170, 3.5], [310, 2.0], [600, 0.5], [1000, -1.0],
  [3000, 2.5], [6000, 1.5], [9000, -1.0], [12_000, -2.5], [15_000, -3.5],
].freeze
VLC_COMPRESSOR = { threshold: -20, ratio: 4.0, attack: 8, release: 120, makeup: 3.2, mix: 0.78 }.freeze
LOOSE_POCKET_BEAT_CATALOG = TAPE_RENDER_CATALOG.map do |entry|
  { track: entry[:preset], out: entry[:out].sub("session", "beat"), bars: 32 }
end.freeze
