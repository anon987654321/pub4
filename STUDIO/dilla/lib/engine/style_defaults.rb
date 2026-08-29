# frozen_string_literal: true
#
# The style default tables — what each named style sets.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# Curated rotation — researched progressions only (no random generated_* walks).
STREAM_TRACKS = DillaLofiMachine::STREAM_ROTATION

# Tempo dropped a lot over this session (92->68 BPM) without this changing,
# so the same bar count now takes much longer in real time — re-read fresh
# on every hotswap exec below rather than baked into the original CLI arg,
# so tuning this constant alone is enough going forward.
# Default stream length (style table may set BARS).
STREAM_BARS_COUNT = 32
STREAM_BEAUTY_MIN = (ENV["STREAM_BEAUTY_MIN"] || "68").to_f
STREAM_MAX_RETRIES = (ENV["STREAM_MAX_RETRIES"] || "2").to_i

def stream_bars_default
  n = (ENV["STREAM_BARS"] || ENV["BARS"] || STREAM_BARS_COUNT).to_i
  n.positive? ? n : STREAM_BARS_COUNT
end
DEFAULT_RENDER_OUTPUT = File.join(OUTPUT_DIR, "beat.mp3")

# Canonical dilla DNA (kit-forward). Comfort is an overlay table, not a mode.
# RENDER_MODE aliases camel|beat|punch → dilla; comfort|sofa → dilla+flags.
# How slow a chord is allowed to speak and to fade in this style, whatever a
# progression preset asks for. Both are generous compared with a real Rhodes --
# the point is to stop a swell, not to forbid sustain.
DILLA_PAD_ATTACK_CEILING = (ENV["PAD_ATTACK_CEILING"] || 260).to_i
DILLA_PAD_RELEASE_CEILING = (ENV["PAD_RELEASE_CEILING"] || 2200).to_i

DILLA_STYLE_DEFAULTS = {
  # Ethan Hein exact Get Dis Money slash cycle (artist-verified).
  "TRACK" => "pedal_e_descent",
  "PROGRESSION" => "pedal_e_descent",
  # BPM deliberately NOT set here (pedal_e_descent's own TRACK_PRESETS entry
  # already has bpm: 92, so this was redundant for the default track and a
  # real bug for every other one: resolve_bpm checks ENV["BPM"] before
  # preset[:bpm], and this soft-fill ran before any track-specific preset
  # was ever consulted -- every track's own tuned bpm (86, 88, 138, ...)
  # was silently clobbered back to 92 for the entire session tonight.
  #
  # 058ff18f3 re-added "BPM" => "92" here, directly above this comment, to pin
  # the tempo the A-laget acapellas stretch cleanliest to. It reintroduced the
  # exact clobber: measured 2026-08-05, baroque (declares 104) and
  # generated_techno (declares 80) both rendered at 92 * bpm_scale. Tracks with
  # a sonic profile were spared because sonic_bpm outranks env_bpm; the rest
  # were not. The acapella intent needs nothing here -- pedal_e_descent is the
  # default TRACK and its own preset already carries 92.
  "BARS" => "32",
  "FORM" => "camel_32",
  "COMPOSITION" => "1",
  "GROOVE_DNA" => "donuts",
  "PERFORMER" => "yancey",
  "VOICING" => "rootless",
  "VOICE_LEAD_PADS" => "1",
  "LEARNED_PROGRESSION" => "0",
  # Rhodes + Prophet stack (Galaxy EP + Supersaw poly) — see PAD_LAYER_STACKS.
  "PAD_VOICE" => "stack_soul",
  # Held pads; arps live on the lead stem (stream rotates LEAD_ARP_MODE).
  "PAD_ARP_MODE" => "held",
  "PAD_ATTACK" => "90",
  "PAD_RELEASE" => "1800",
  "PAD_LEGATO_VAR" => "1",
  "PAD_LAYERS" => "1",
  # Quieter choir so Rhodes/Prophet aren't buried under oohs.
  # Vocals off by default. RAP_VOCAL=<slug> or CHOIR_VOX=1 re-enables.
  "CHOIR_VOX" => "0",
  "CHOIR_VOX_GAIN" => "0.16",
  "LUSH_SYNTH" => "1",
  "MOTIF_RECALL" => "1",
  # Hybrid pocket + Wonky overlay so kick/snare/hat/clap all read on speakers.
  # WONKY_DRUMS_ONLY=1 + KICKS=0 was "no-kicks" and buried the hat bus under pads.
  "KICKS" => "1",
  "POCKET_KICKS" => "1",
  # Pocket soul kit first. Wonky overlay / chops are opt-in — dual-kit mush
  # was the main "drums suck" report (pocket + Wonky + poly + shaker + chops).
  "WONKY_DRUMS_ONLY" => "0",
  "WONKY_DRUM_OVERLAY" => "0",
  "WONKY_KICK_GAIN" => "0.75",
  "KICK_SAMPLE_GAIN" => "0.9",
  "KICK_GAIN" => "0.88",
  "POCKET_DNA" => "1",
  "POCKET_SET" => "neo_soul",
  "POCKET_SIMPLE" => "1",
  "POCKET_GHOSTS" => "1",
  "POCKET_OPEN_HAT" => "1",
  "POCKET_RUSH" => "1",
  "POCKET_KICK_SILENCE" => "1",
  "KICK_DOUBLE" => "1",
  "KICK_DROP" => "1",
  "SNARE_PREHIT_GHOST" => "1",
  "SNARE_EARLY" => "1",
  "HATS_LATE" => "1",
  "KICK_LATE" => "1",
  "KICK_FREEHAND" => "1",
  "HAT_MICRO" => "1",
  "SWING_JITTER" => "1",
  "GROOVE_ENGINE" => "1",
  # Restored to "1" (2026-07-28). 1e74b12fd made the FM kit the full-replacement
  # default as an explicit, measured user choice ("User chose full-kit FM
  # replacement over blending or per-track rotation after reviewing the
  # tradeoff"; harshness -19.66 dB vs the analog kit's -17.68 dB). Three commits
  # later 6e5eed932 -- a styles-collapse refactor whose message says nothing
  # about drums -- added "FM_DRUMS" => "0" here and silently reverted it, so the
  # engine has been running the analog kit ever since despite fm_drums_enabled?
  # still defaulting on and the FM_DRUM_DIR comment still claiming "default on".
  "FM_DRUMS" => "1",
  "RAW_KICK" => "1",
  "DRUM_SAMPLE_RAW" => "1",
  "DRUM_CHOPS" => "0",
  "CHOP_ANCHOR_DRUMS" => "1",
  "CHOP_DRIFT_TICKS" => "3",
  "ECLECTIC_PERC" => "0",
  "NO_QUANTIZE" => "1",
  "BACKBEAT_CLAP" => "0",
  # Isolated rap vocals — sit on top of the kit, not under pads. Placement is
  # RAP_VOCAL_ANCHOR_DB (0.0 = level with the beat); this is the taste trim.
  # gunnhild is the only vocal source (operator decision). It is also the harder
  # one -- two usable pockets in 128s, needing pre-gain to survive the isolation
  # chain -- which is why this default had drifted to sa_g. Defaulting to the
  # easy source hid that problem rather than fixing it; the isolation and fit
  # path has to handle this voice, so this is what it runs against.
  # Vocals off by default. RAP_VOCAL=<slug> or CHOIR_VOX=1 re-enables.
  "RAP_VOCAL" => "0",
  "RAP_VOCAL_STYLE" => "rap",
  "RAP_VOCAL_MIX" => "1.0",
  "RAP_VOCAL_WEIGHT" => "1.0",
  "RAP_VOCAL_BED_WEIGHT" => "1.0",
  "RAP_VOCAL_DUCK" => "0.58",
  "RAP_VOCAL_SIDECHAIN" => "1",
  "LA_BEAT_PROGRESSION" => "0",
  "LINEAR_CHORD_INDEX" => "1",
  # Rotate full progression pack (not only the 10 verified names).
  "ARTIST_VERIFIED_ONLY" => "0",
  # One top line, and it is the counter-line.
  #
  # This block used to switch on all four lead layers at once and set
  # MELODIC_LEAD=0 to force sixteenth-note arps, with the note "real arps (not
  # slow melodic phrases)". That was the sound the operator described as
  # the leads destroying everything: three arp layers over the chords the pads
  # were already holding, at close to twice their level.
  #
  # MELODIC_LEAD=1 is the counter-line that answers the chords. HARMONY_LEAD,
  # SCALE_LEAD and LEAD_ARP ride on top of it: the signature lead is an arpeggio
  # locked to the progression's own scale — the ringtone-lead voice — sitting
  # over the counter-line rather than replacing it. CREATIVE_LEAD stays 0 so the
  # arp follows the harmony instead of improvising against it.
  "HARMONY_LEAD" => "1",
  "SCALE_LEAD" => "1",
  "CREATIVE_LEAD" => "0",
  "MELODIC_LEAD" => "1",
  "LEAD_ARP" => "1",
  "LEAD_ARP_MODE" => "wonky_spiral",
  "LEAD_VOICE" => "soul_prophet",
  "EXPERIMENTAL_LEADS" => "0",
  "STREAM_LEAD_MIDI_RICH" => "1",
  "STREAM_ROTATE_SYNTH" => "1",
  "STREAM_ROTATE_LEAD" => "1",
  # Cycle pad/lead patches every track; morph for extra color mid-phrase.
  "SYNTH_MORPH" => "1",
  "SYNTH_CYCLE" => "1",
  "LEAD_MORPH" => "1",
  "FM_NATIVE" => "1",
  "PAD_TEXTURE" => "1",
  "STREAM_CREATIVE_FREEDOM" => "1",
  "SIDECHAIN_STYLE" => "wonky",
  "SONITEX" => "donuts_warm",
  "SONITEX_PRESET" => "donuts_warm",
  "ANALOG_CHAIN" => "vinyl_hot",
  "DRUM_PRESET" => "dilla_slight",
  # Quieter drum bus — kit sits under pads/vox (~−3…−4 dB vs previous hot path).
  "WONKY_OVERLAY_GAIN" => "0.95",
  "WONKY_SUB_MIX" => "1.0",
  "WONKY_TOP_MIX" => "0.65",
  "WONKY_MERGE_BOOST" => "1.05",
  "WONKY_BASE_DRUM_VOL" => "0.85",
  "DRUM_BUS_VOL" => "0.95",
  "DRUM_BUS_GAIN" => "0.92",
  "DRUM_MIX_WEIGHT" => "0.95",
  "DRUM_PEAK_DB" => "-3.5",
  "DRUM_AIR_DB" => "1.8",
  "DRUM_PRESENCE_DB" => "1.5",
  # Pads a bit more present now that drums are stepped back.
  "HARM_MIX_WEIGHT" => "1.12",
  "HARM_BUS_VOL" => "1.25",
  "HARM_BODY_DB" => "2.2",
  "HARM_MID_DB" => "1.8",
  "HARM_PRESENCE_DB" => "1.6",
  "HARM_AIR_DB" => "0.8",
  "HARM_SUB_CUT_DB" => "-4.0",
  "HARM_SUB_SHELF_DB" => "0.6",
  "SIDECHAIN_DRUM_WEIGHT" => "1.2",
  "SIDECHAIN_HARM_WEIGHT" => "1.15",
  "WONKY_CHORD_DUCK" => "0.9",
  "HARMONIC_PADS_WEIGHT" => "1.12",
  "HARMONIC_PADS_VOLUME" => "1.2",
  # The pad bed sits back under the voice and the lead, not out over a kit.
  "PAD_VOL" => "74",
  # Lead must cut over the stacked pad bed.
  "HARMONIC_SCALE_LEAD_WEIGHT" => "1.25",
  "HARMONIC_SCALE_LEAD_VOLUME" => "1.55",
  "HARMONIC_LEAD_ARP_WEIGHT" => "1.75",
  "HARMONIC_LEAD_ARP_VOLUME" => "1.95",
  "HARMONIC_XLEAD_WEIGHT" => "0.22",
  "HARMONIC_XLEAD_VOLUME" => "0.45",
  "HARMONIC_HARMONY_LEAD_WEIGHT" => "1.05",
  "HARMONIC_HARMONY_LEAD_VOLUME" => "1.45",
  "HARMONIC_LEAD_WEIGHT" => "1.15",
  "HARMONIC_LEAD_VOLUME" => "1.55",
  "STREAM_ANALOG_WILD" => "0",
  "STREAM_ANALOG_EVERY" => "0",
  "STREAM_ITERATE" => "0",
  "PHONE_PREVIEW_GATE" => "0",
  "CAMEL_LOCK_COLOR" => "1",
  "CAMEL_DRUM_LOCK" => "1",
  "CAMEL_NO_BREAK" => "1",
  "CAMEL_CLEAN_MASTER" => "1",
  "CAMEL_NO_REVERB" => "1",
  "CAMEL_DRY_DRUMS" => "0",
  "CONV_REVERB" => "0",
  "VINYL" => "1",
  "SELF_SAMPLE" => "0",
  "RADIO_BERGEN" => "0",
  "STREAM_CONTINUOUS" => "1",
  "STREAM_GAP" => "0.25",
  "STREAM_CROSSFADE" => "0.08",
  "STREAM_DEMO" => "demo.wav",
  "STREAM_NORMALIZE" => "1",
  # Loudness target only. True peak and loudness range are gates, not knobs:
  # dilla_reference.yml holds true_peak_max_dbtp and master_heuristics checks
  # the finished file against it. The stream master is a measure-then-static-
  # gain ride, so there is no limiter here for a ceiling to steer.
  "STREAM_LUFS" => "-16.5",
  # Dilla's documented MPC sweet spot is 54-58% (Dilla Time + producer
  # consensus); 60+ reads as over-swung rather than the authentic pocket.
  "SWING" => "56",
  "MASTER_HEURISTICS" => "1",
  # Slow tempo-breathe over a phrase (not per-hit noise) + periodic full-layer
  # drop-out for arrangement contrast — see DillaGroove.phrase_drift_sec and
  # DillaRhythm.periodic_layer_drop_gain.
  "PHRASE_DRIFT" => "1",
  "ARRANGEMENT_VARIATION" => "1",
  "THEORY_RUNTIME" => "1",
  "THEORY_DILLA" => "1",
  # Explicit CoC flags (also default-on via != "0" in code).
  "STREAM_DRUM_ROTATE" => "1",
  "DFAM" => "1",
  "SPECTRAL_ENGINE" => "1",
  "THEORY_PARALLELS" => "1",
}.freeze

# Baseline production knobs applied on every boot (soft-fill). Values that also
# appear in DILLA_STYLE_DEFAULTS MUST match that table — soft-fill is
# first-writer-wins, so a conservative BEST entry silently blocks style DNA on
# one-shot `dilla` / product paths that only soft-apply style. That used to be a
# comment you had to obey by hand; the shared keys are now inherited via slice
# rather than copied, so they cannot drift apart in the first place. Anything in
# the merge below is a deliberate BEST-only value or a deliberate divergence.
DILLA_BEST_DEFAULTS = DILLA_STYLE_DEFAULTS.slice(
  "PAD_VOICE", "PAD_ARP_MODE", "LEAD_VOICE",
  "LEAD_ARP_MODE", "LEAD_ARP", "EXPERIMENTAL_LEADS",
  "SYNTH_CYCLE", "LUSH_SYNTH", "PAD_TEXTURE",
  "DRUM_PRESET", "FM_DRUMS", "RAW_KICK",
  "DRUM_SAMPLE_RAW", "POCKET_SET", "WONKY_DRUM_OVERLAY",
  "DRUM_CHOPS", "ECLECTIC_PERC", "BACKBEAT_CLAP",
  "PERFORMER", "GROOVE_DNA", "COMPOSITION",
  "GROOVE_ENGINE", "POCKET_DNA", "SWING_JITTER",
  "PHRASE_DRIFT", "ARRANGEMENT_VARIATION", "KICK_DOUBLE",
  "KICK_DROP", "SNARE_PREHIT_GHOST", "POCKET_KICK_SILENCE",
  "POCKET_RUSH", "HARMONY_LEAD", "SCALE_LEAD",
  "FM_NATIVE", "MASTER_HEURISTICS", "KICK_GAIN",
  "DRUM_BUS_VOL", "DRUM_BUS_GAIN", "DRUM_MIX_WEIGHT",
  "KICKS", "MOTIF_RECALL",
).merge(
  "DILLA_DEEP" => "1",
  "SOUL_ENRICH" => "1",
  # Progressions rotate by default: a bare render moves through the curated pack
  # rather than sitting on one, so no command-line flag is needed to hear variety.
  "REHARM_LOOP" => "1",
  "CREEPY_PATCHES" => "0",
  # donuts_warm's hf_rolloff/groove_wear_lp sit at 2200/2600Hz (see the
  # "not a 2 kHz blanket" comment on its donuts_soul sibling) and its
  # out_comp_ratio runs a full point hotter — buries presence/air and
  # sits crest factor right at the reject-gate floor. This table is a
  # soft-fill only (apply_best_defaults!), so it never wins against
  # DILLA_STYLE_DEFAULTS' force-applied donuts_warm/vinyl_hot on the actual
  # dilla render path (verified: dilla.rb dilla <out> prints donuts_warm) --
  # it only matters for callers that reach this table without also going
  # through apply_dilla_style!(force: true). Kept at the safer donuts_soul/
  # broadcast for those; if the crest-factor risk above ever actually bites
  # (quality-gate reject, not just "close to the floor"), that's the signal
  # DILLA_STYLE_DEFAULTS' donuts_warm choice needs revisiting too.
  "SONITEX" => "donuts_soul",
  "SONITEX_PRESET" => "donuts_soul",
  "ANALOG_CHAIN" => "broadcast",
  "EXTERNAL_KIT" => "03-soulful-vintage",
  "MARKOV_DRUMS" => "1",
  "FLAM" => "1",
  "GROOVE_LOCK" => "kick",
  "VINYL" => "0",
  "BASS_SLIDE" => "1",
  "SPECTRAL_ARP" => "0",
  "GHOST_TIER" => "pocket",
  "SLASH_BASS" => "0",
  "PROMOTION_BEAUTY_MIN" => "78",
  "GROOVE_SCORE_MIN" => "75",
).freeze

RENDER_MODE_DEFAULTS = {
  sketch: {
    "STEM_EXPORT" => "0", "COMPOSITION" => "0", "LISTEN_PASSES" => "0",
    "DILLA_QUALITY_GATE" => "0", "MARKOV_DRUMS" => "1", "GHOST_TIER" => "pocket",
    "RENDER_BEAUTY_MIN" => "55", "KEEP_STEMS" => "0",
  },
  record: {
    "STEM_EXPORT" => "1", "COMPOSITION" => "1", "LISTEN_PASSES" => "2",
    "DILLA_QUALITY_GATE" => "1", "KEEP_STEMS" => "1", "RENDER_BEAUTY_MIN" => "72",
    "MOTIF_RECALL" => "1",
  },
  perform: {
    "STEM_EXPORT" => "1", "COMPOSITION" => "1", "LISTEN_PASSES" => "3",
    "DILLA_QUALITY_GATE" => "1", "STREAM_EVOLVE_PERFORMER" => "1",
    "RENDER_BEAUTY_MIN" => "75", "MOTIF_RECALL" => "1", "SLASH_BASS" => "1",
    "KEEP_STEMS" => "1", "GHOST_TIER" => "accent",
  },
  # The record's own finish, as one name.
  #
  # Every knob below defaults to the engine's previous behaviour on its own, so
  # nothing here changes an existing render -- which is correct for each knob
  # taken separately and useless for a record, because it means the sound a whole
  # album shares can only be reproduced by remembering sixteen environment
  # variables in the right order. Fifteen of the sixteen differ from a bare run.
  # That is not a sound anyone can ask for twice.
  #
  # So it is a mode: RENDER_MODE=album, and one word reaches it from the CLI, a
  # setlist, or MASTER's dilla surface. Different beats, one finish -- the shapes
  # vary and the superstructure does not.
  #
  # BARS=16 is load-bearing, not a length preference. harmony_lead_events drops
  # every note in the first two bars of an intro section, so a 4-bar render
  # produces zero lead events and an 8-bar one produces six, against 54 at
  # sixteen. A short render of this mode is silently a different arrangement.
  album: {
    # Real sampled kit, with the layered kick an external kit otherwise disables
    # and the backbeat clap that is implemented and off.
    "EXTERNAL_KIT" => "03-soulful-vintage", "LAYER_KICK" => "1", "BACKBEAT_CLAP" => "1",
    # Made new things old: 12-bit sampler grit and even-harmonic tube on the kit.
    "DRUM_CRUSH_MIX" => "0.42", "DRUM_CRUSH_BITS" => "12", "DRUM_TUBE_DB" => "6",
    "DRUM_PRESENCE_DB" => "6", "DRUM_AIR_DB" => "5", "DRUM_CRISP_AIR_DB" => "6",
    # Made old things new: the sampled bed gets the pad bus's own shaping and
    # sits at pad level rather than ten decibels under it.
    "SAMPLE_LOOP_VOL" => "1.6", "SAMPLE_LOOP_WEIGHT" => "1.5",
    "SAMPLE_LOOP_BODY_DB" => "2.8", "SAMPLE_LOOP_MID_DB" => "2.6",
    "SAMPLE_LOOP_PRESENCE_DB" => "2.4", "SAMPLE_LOOP_AIR_DB" => "1.2",
    # The lead, audible: it had no mix weight at all until LEAD_MIX_WEIGHT.
    "HARMONY_LEAD" => "1", "LEAD_MIX_WEIGHT" => "3.0",
    "VOICE_STACK" => "4", "VOICE_STACK_DETUNE" => "fifths",
    "LPG" => "1", "HOCKET" => "3", "HOCKET_MODE" => "pendulum",
    # The signature every beat carries.
    "MELT" => "0.7", "MASTER_SMOOTH_DB" => "2", "MASTER_AIR_DB" => "0", "MASTER_TILT_DB" => "3",
    "BARS" => "16", "COMPOSITION" => "1", "KEEP_STEMS" => "0",
  },
  long_soul: {
    "FORM" => "soul_32", "COMPOSITION" => "1", "VOICING" => "bill_evans",
    "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "PAD_VOL" => "58",
    "LEAD_ARP" => "1", "HARMONY_LEAD" => "1", "HARMONY_LEP_MODE" => "hybrid",
    "LUSH_SYNTH" => "1", "MOTIF_RECALL" => "1",
    "GROOVE_DNA" => "donuts", "PERFORMER" => "yancey",
    "SONITEX" => "donuts_warm", "SONITEX_PRESET" => "donuts_warm",
    "ANALOG_CHAIN" => "vinyl_hot", "CONV_REVERB" => "chamber",
    "TRACK" => "long_soul", "BARS" => "32",
  },
  # Ambient — the default. Soothing means removing things, not adding a reverb
  # to a busy arrangement, so this is mostly knobs turned down: no arp, the
  # kick present but well back, ghosts off the accent tier, one voicing family
  # held rather than rotated.
  #
  # BPM 68 against the engine's 86 default: the swing model is unchanged, there
  # is more time between hits for the pads to decay into. PAD_ATTACK and
  # PAD_RELEASE are roughly double long_soul's, which is what makes chords
  # arrive rather than land.
  #
  # SONITEX subtle and lo_fi rather than heavy or vinyl_lab: the analog chain is
  # here for warmth, and crackle plus stylus mistrack is texture that keeps
  # asking to be noticed.
  ambient: {
    "FORM" => "soul_32", "COMPOSITION" => "1", "VOICING" => "bill_evans",
    "BPM" => "68", "BARS" => "32",
    "PAD_ATTACK" => "3000", "PAD_RELEASE" => "8000", "PAD_VOL" => "72",
    "LUSH_SYNTH" => "1", "HARMONY_LEAD" => "1", "LEAD_ARP" => "0",
    "MOTIF_RECALL" => "1",
    "GROOVE_DNA" => "donuts", "PERFORMER" => "yancey",
    "KICKS" => "1", "KICK_GAIN" => "0.62", "GHOST_TIER" => "pocket",
    "SONITEX" => "subtle", "SONITEX_PRESET" => "subtle",
    "ANALOG_CHAIN" => "lo_fi", "CONV_REVERB" => "chamber",
    "TRACK" => "ambient_major_drift",
  },
  golden: {
    "FORM" => "donuts_time", "COMPOSITION" => "1", "VOICING" => "kenny_barron",
    "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "PAD_VOL" => "58",
    "LEAD_ARP" => "1", "HARMONY_LEAD" => "1", "HARMONY_LEP_MODE" => "hybrid",
    "LUSH_SYNTH" => "1", "MOTIF_RECALL" => "1",
    "GROOVE_DNA" => "donuts", "PERFORMER" => "yancey",
    "SONITEX" => "donuts_warm", "SONITEX_PRESET" => "donuts_warm",
    "ANALOG_CHAIN" => "cassette", "CONV_REVERB" => "chamber",
    "TRACK" => "golden", "BARS" => "32",
  },
  # Plug Research / Brainfeeder / Warp-leaning — points already-built,
  # normally-dormant knobs at each other rather than adding new engineering:
  # spectral chop/harmonic-stack arps, IDM-shape arp bias (euclidean/ratchet/
  # random_walk/stutter/burst), demucs-sliced granular chops, cosmogramma
  # groove DNA + thundercat performer feel, a more damaged analog chain.
  warp: {
    "SPECTRAL_ENGINE" => "1", "SPECTRAL_ARP" => "1", "HARMONIC_STACK" => "1",
    "ARP_IDM_BIAS" => "1", "DRUM_CHOPS" => "1",
    "GROOVE_DNA" => "cosmogramma", "PERFORMER" => "thundercat",
    "VOICING" => "quartal", "LEAD_ARP" => "1", "HARMONY_LEAD" => "1",
    "PAD_ARP_MODE" => "wash", "LUSH_SYNTH" => "1", "SYNTH_MORPH" => "1",
    "ANALOG_CHAIN" => "dub_chamber", "SONITEX" => "donuts_soul", "SONITEX_PRESET" => "donuts_soul",
    "STEREO_PAN" => "1", "MOTIF_RECALL" => "1", "COMPOSITION" => "1",
    "BARS" => "32",
  },
  # dilla/camel: empty here — DNA lives in DILLA_STYLE_DEFAULTS (applied via
  # apply_dilla_style! / apply_render_mode! for mode dilla).,
}.freeze

# Comfortable listening: fewer layers, warmer bed, quieter tops/vox, calmer master.
# Activate via STREAM_COMFORT=1 (stream default), DILLA_COMFORT=1, RENDER_MODE=comfort,
# or `ruby dilla.rb comfort …`. Opt out: STREAM_COMFORT=0 or STREAM_PUNCH=1.
# Keys shared verbatim with DILLA_STYLE_DEFAULTS are inherited, not copied:
# soft-fill is first-writer-wins, so a copy that drifts from the style table
# silently shadows the style DNA. Inheriting makes that drift impossible.
DILLA_COMFORT_DEFAULTS = DILLA_STYLE_DEFAULTS.slice(
  "POCKET_KICKS", "WONKY_DRUMS_ONLY", "WONKY_DRUM_OVERLAY",
  "DRUM_CHOPS", "DRUM_PRESET", "WONKY_SUB_MIX",
  "WONKY_TOP_MIX", "POCKET_DNA", "POCKET_SIMPLE",
  "POCKET_GHOSTS", "POCKET_OPEN_HAT", "RAP_VOCAL_STYLE",
  "RAP_VOCAL_MIX", "RAP_VOCAL_WEIGHT", "RAP_VOCAL_BED_WEIGHT",
  "PAD_ARP_MODE", "LEAD_ARP", "LEAD_VOICE",
  "MASTER_HEURISTICS", "STREAM_NORMALIZE", "STREAM_ROTATE_SYNTH",
  "SYNTH_MORPH", "LEAD_MORPH", "SYNTH_CYCLE",
  "STREAM_ANALOG_WILD", "STREAM_ANALOG_EVERY", "STREAM_ITERATE",
  "LA_BEAT_PROGRESSION", "SELF_SAMPLE", "CONV_REVERB",
  "CAMEL_CLEAN_MASTER", "ARTIST_VERIFIED_ONLY",
).merge(
  "STREAM_COMFORT" => "1",
  "STREAM_SOUL" => "1",
  "SPEAK" => "0",
  # Let the real track/progression pool cycle -- a single forced progression
  # ("mixo_sus_loop" pinned via TRACK/PROGRESSION/STREAM_TRACK) previously
  # sat here, which is exactly the monotony the render-seed/pocket variety
  # work elsewhere in this file exists to prevent. Comfort should mean
  # calmer mixing, not one repeating track forever.
  "STREAM_LOCK" => "0",
  # Dusty/Madlib-leaning pocket (warm, soulful) -- NOT the industrial techno
  # kit that was here before. That swap (128 BPM, swing=50/no-swing at all,
  # four-on-floor kick, full 16-step hats, ghosts/rush/open-hat all forced
  # off) fought against the entire Dilla-pocket direction this file has
  # been tuned toward all session and was the direct cause of "too harsh".
  "KICKS" => "1",
  "BACKBEAT_CLAP" => "1",
  "POCKET_SET" => "dusty",
  "KICK_GAIN" => "1.0",
  "WONKY_KICK_GAIN" => "0.9",
  "KICK_SAMPLE_GAIN" => "1.0",
  "WONKY_OVERLAY_GAIN" => "0.9",
  "WONKY_MERGE_BOOST" => "1.0",
  "WONKY_BASE_DRUM_VOL" => "0.9",
  # Kit sits under voice; still readable.
  "DRUM_BUS_VOL" => "1.05",
  "DRUM_BUS_GAIN" => "1.0",
  "DRUM_MIX_WEIGHT" => "0.9",
  "DRUM_AIR_DB" => "1.2",
  "DRUM_PRESENCE_DB" => "1.2",
  "DRUM_PEAK_DB" => "-3.0",
  "DRUM_PEAK_LIFT_DB" => "0",
  "POCKET_RUSH" => "1",
  # Jonas V — loud enough to hear (previous 1.35 left voice ≈−18dB under bed).
  # gunnhild is the only vocal source (operator decision). It is also the harder
  # one -- two usable pockets in 128s, needing pre-gain to survive the isolation
  # chain -- which is why this default had drifted to sa_g. Defaulting to the
  # easy source hid that problem rather than fixing it; the isolation and fit
  # path has to handle this voice, so this is what it runs against.
  # Vocals off by default. RAP_VOCAL=<slug> or CHOIR_VOX=1 re-enables.
  "RAP_VOCAL" => "0",
  "RAP_VOCAL_DUCK" => "0.42",
  "RAP_VOCAL_SIDECHAIN" => "1",
  # Held pad bed, real attack/release (not the tightened 900/2200 techno
  # values that were here -- neo-soul pads need room to bloom).
  "PAD_VOICE" => "stack_soul",
  "PAD_ATTACK" => "1500",
  "PAD_RELEASE" => "3800",
  "PAD_VOL" => "70",
  "HARM_MIX_WEIGHT" => "0.95",
  "HARM_BUS_VOL" => "1.15",
  "HARM_BODY_DB" => "2.5",
  "HARM_MID_DB" => "1.4",
  "HARM_PRESENCE_DB" => "0.8",
  "HARM_AIR_DB" => "0.3",
  "HARM_SUB_CUT_DB" => "-3.0",
  "HARMONIC_PADS_WEIGHT" => "1.15",
  "HARMONIC_PADS_VOLUME" => "1.25",
  "LEAD_ARP_MODE" => "melodic_soul",
  "MELODIC_LEAD" => "1",
  "SCALE_LEAD" => "0",
  "HARMONY_LEAD" => "0",
  "CREATIVE_LEAD" => "0",
  "EXPERIMENTAL_LEADS" => "0",
  "LEAD_FORCE_ARP" => "0",
  "STREAM_LEAD_MIDI_RICH" => "0",
  "HARMONIC_LEAD_ARP_WEIGHT" => "1.05",
  "HARMONIC_LEAD_ARP_VOLUME" => "1.1",
  "HARMONIC_SCALE_LEAD_WEIGHT" => "0.85",
  "HARMONIC_SCALE_LEAD_VOLUME" => "0.9",
  "HARMONIC_LEAD_WEIGHT" => "1.0",
  "HARMONIC_LEAD_VOLUME" => "1.05",
  "HARMONIC_HARMONY_LEAD_WEIGHT" => "0.7",
  "HARMONIC_HARMONY_LEAD_VOLUME" => "0.85",
  "HARMONIC_XLEAD_WEIGHT" => "0.1",
  "HARMONIC_XLEAD_VOLUME" => "0.2",
  # Gentle pump + warm master.
  "SIDECHAIN_STYLE" => "dilla",
  "SIDECHAIN_DRUM_WEIGHT" => "1.25",
  "SIDECHAIN_HARM_WEIGHT" => "1.1",
  "WONKY_CHORD_DUCK" => "0.92",
  "SONITEX" => "donuts_soul",
  "SONITEX_PRESET" => "donuts_soul",
  "ANALOG_CHAIN" => "broadcast",
  "HARSHNESS_NOTCH" => "1",
  "PERCEPTUAL_LIMIT" => "1",
  "STREAM_LUFS" => "-17.5",
  # Autorotate progressions/patches/leads between tracks so a stream session
  # actually surfaces variety instead of settling on one sound -- these were
  # all forced off ("less chaos"), which is exactly why a listening session
  # kept landing on the same handful of textures.
  "STREAM_ROTATE_LEAD" => "1",
  "STREAM_CREATIVE_FREEDOM" => "0",
  "EVOLVE_EVERY" => "2",
  "STREAM_HARMONY_EVERY" => "2",
  "STREAM_EVOLVE_PERFORMER" => "0",
  "VINYL" => "0",
  "CAMEL_NO_REVERB" => "1",
  # Dilla pocket range (documented at the top of lib/groove_engine.rb),
  # not the 128 BPM / swing=50 (i.e. literally no swing) techno values
  # that were here -- those alone made anything feel generic regardless
  # of drum EQ. Leave BPM unset so per-track tempo picks its own value
  # in the real hip-hop range instead of forcing house/techno tempo.
  "SWING" => "56",
  "FORM" => "soul_32",
  "BARS" => "16",
  "STREAM_BARS" => "16",
  "QUINTUPLET" => "0",
).freeze

# Keys shared verbatim with DILLA_STYLE_DEFAULTS are inherited, not copied:
# soft-fill is first-writer-wins, so a copy that drifts from the style table
# silently shadows the style DNA. Inheriting makes that drift impossible.
STREAM_SOUL_DEFAULTS = DILLA_STYLE_DEFAULTS.slice(
  "BARS", "LA_BEAT_PROGRESSION", "LINEAR_CHORD_INDEX",
  "PAD_LEGATO_VAR", "LEAD_ARP", "LEAD_VOICE",
  "PAD_VOICE", "PAD_ARP_MODE", "PAD_LAYERS",
  "VOICING", "VOICE_LEAD_PADS", "LEARNED_PROGRESSION",
  "TRACK", "PROGRESSION", "RADIO_BERGEN",
  "MOTIF_RECALL", "LUSH_SYNTH",
  "RAP_VOCAL_STYLE", "RAP_VOCAL_MIX", "RAP_VOCAL_WEIGHT",
  "RAP_VOCAL_BED_WEIGHT", "RAP_VOCAL_SIDECHAIN", "SIDECHAIN_STYLE",
  "SYNTH_CYCLE", "FM_NATIVE",
).merge(
  "STREAM_SOUL" => "1",
  "FORM" => "soul_32",
  "LEAD_ARP_MODE" => "melodic_soul",
  "MELODIC_LEAD" => "1",
  "SCALE_LEAD" => "0",
  "CREATIVE_LEAD" => "0",
  "HARMONY_LEAD" => "0",
  "PAD_VOL" => "74",
  "STREAM_LOCK" => "0",
  "ARTIST_VERIFIED_ONLY" => "1",
  "SPEAK" => "0",
  "PAD_ATTACK" => "1400",
  "PAD_RELEASE" => "3600",
  "STREAM_LEARN_BIAS" => "0",
  "PROMOTION_BEAUTY_MIN" => "85",
  # Soft only — comfort force sets overlay 0; do not re-hot kit here.
  "WONKY_DRUM_OVERLAY" => "0",
  "WONKY_OVERLAY_GAIN" => "0.85",
  # Jonas V acapella (rap-vocal ingest) — tempo-fit per track BPM.
  # gunnhild is the only vocal source (operator decision). It is also the harder
  # one -- two usable pockets in 128s, needing pre-gain to survive the isolation
  # chain -- which is why this default had drifted to sa_g. Defaulting to the
  # easy source hid that problem rather than fixing it; the isolation and fit
  # path has to handle this voice, so this is what it runs against.
  # Vocals off by default. RAP_VOCAL=<slug> or CHOIR_VOX=1 re-enables.
  "RAP_VOCAL" => "0",
  "RAP_VOCAL_DUCK" => "0.72",
  "SYNTH_MORPH" => "0",
  "LEAD_MORPH" => "0",
  "EXPERIMENTAL_LEADS" => "0",
  "HARMONIC_PADS_WEIGHT" => "1.85",
  "HARMONIC_PADS_VOLUME" => "1.85",
  "HARMONIC_LEAD_ARP_WEIGHT" => "1.55",
  "HARMONIC_LEAD_ARP_VOLUME" => "1.85",
  "HARMONIC_XLEAD_WEIGHT" => "0.15",
  "HARMONIC_XLEAD_VOLUME" => "0.35",
).freeze
