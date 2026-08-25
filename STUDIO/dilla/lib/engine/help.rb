# frozen_string_literal: true
#
# The help screen.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

# =============================================================================
# HELP
# =============================================================================

def help
  puts <<~HELP
    Dilla Lab — unified audio engine (#{ROOT})

    DEFAULT (no command — finite catalogue showcase to demo.wav)
      ruby dilla.rb                    Bare invoke: showcase_demo! (every named track, a few bars)
      ruby dilla.rb stream [bars]      Continuous stream (speakers via afplay/ffplay)
      ruby dilla.rb out.wav [bars]     One-shot render to path (not stream)
      ruby dilla.rb dilla [out] [bars] One-shot kit-forward render
      DILLA_DEEP=0                     One-shot: standard render (no quality gate / refine)
      DILLA_RAW=1                      Skip all best-default ENV
      PHONE_PREVIEW_GATE=1             Laptop-speaker check in quality gate (opt-in)

    STREAM (non-stop rotation — speakers via afplay/ffplay)
      stream [bars]                    Fast render+play (#{STREAM_BARS_COUNT} bars default)
      demo-all [bars] [out.wav]        Render all #{demo_catalog_sizes[:all]} named pieces → demo.wav + demo.mp3 (resumable)
      DEMO_CURATED_ONLY=1              Just the curated head (#{demo_catalog_sizes[:curated]} pieces)
      DEMO_CATALOG=stream              Restrict demo-all to the stream rotation (#{demo_catalog_sizes[:stream]})
      DEMO_MP3=0 / DEMO_MP3_BITRATE    Skip the tracked mp3 / override 128k
      STREAM_CONTINUOUS=1 (default)    Outer shell auto-restarts; per-track timeout skips hangs
      STREAM_TRACK_TIMEOUT=420         Max seconds per track before skip (0 = no limit)
      STREAM_GAP=0.15                  Pause between tracks (0 = back-to-back)
      STREAM_CROSSFADE=0.12            Crossfade between stream slots
      STREAM_ITERATE=1 (default)       Auto-refine mix/groove each track; log stream_iterate.log
      STREAM_DEMO=demo.wav (default)   Each stream track overwrites demo.wav (WAV = no mp3 encode)
      STREAM_CREATIVE=1                Opt-in wild layer (LA_BEAT/vinyl/hot LUFS) — off by default
      DILLA_SH_TIMEOUT=120             Kill hung ffmpeg/fluidsynth after N seconds
      DILLA_FS_DRY=1                   Fluidsynth without its own chorus/reverb (pads go ~mono)
      GENRE=hiphop|soul|jazz|techno|lofi   One word for the colour bundle; every knob still overrides it
      GENRE_HARMONY=1                  Techno/industrial/analog take their pitches from the progression
      RENDER_MODE=dilla                Canonical DNA
      RENDER_MODE=warp                 Spectral/IDM bias (Brainfeeder-leaning)
      RENDER_MODE=long_soul|golden     Lush 32-bar soul (FORM + HARMONY_LEAD + bill_evans pads)
      STREAM_PUNCH=1                   Kit-forward + creative max (off comfort sofa mix)
      FORM=soul_16|soul_32|donuts_time|camel_32  Section map for drums/arp density
      CAMEL_DRUM_ENTRY_BAR=4             Bars before FlyLo drums enter
      STREAM_TRACK=chromatic_mediant_drift  Pin progression in stream mode
      CAMEL_KEEP_FLYLO=1                 Keep FlyLo overlay on breakdowns
      HARMONY_LEAD=1                     Chord-tone harmonic arp stem (voiced pads + extensions)
      STREAM_SOUL=1 (stream default)     Locked Donuts turnaround + harmony lead + soul form
      STREAM_HARMONY_EVERY=2           Rotate voicing + soul TRACK family every N tracks
      STREAM_ANALOG_WILD=1             Random wild analog FX mashups (~35% of analog rotates)
      STREAM_LEARN_BIAS=1              Bias stream toward last learn --apply hints
      STREAM_CREATIVE_FREEDOM=1        Rotate lead/scale arp patches + stem weights every track
      STREAM_DEEP=1 stream [bars]      Full deep pipeline + quality gate per track (~1–2 min)
      DILLA_FORCE_TERMINAL=1         macOS: open Terminal.app for speaker playback
      KICKS=1 (default in stream)      Layered 808-style kicks in the drum bus
      KICK_GAIN=0.88 (style DNA wins after stream extra defaults)
      SPEAK=0 (stream default)         TTS off; SPEAK=1 overlays pickup lines
      SPEAK_VOICE=en-US-AndrewNeural   Funny-clear voice (GuyNeural also works)
      SPEAK_RATE=-48%                  Slower speech (default in stream)
      SPEAK=0                          Beat only — skip speech overlay
      RADIO_BERGEN=0 (stream default)  Set 1 to bias TRACK from playlist.brgen.no
      radio-bergen-study [--audio-root PATH]  Refresh learnings YAML from manifest
      radio-bergen-analyze [--audio-root PATH]  Per-track dossiers (drums/texture/harmony)
      radio-bergen-librosa            Librosa deep analysis (optional .venv)

    SYNTHESIS
      loose_pocket [out.wav|mp3]         Dirty pocket drums + VLC FX (default on)
      loose_pocket beats [dir]           Batch beat_01..14 wav+mp3 → renders/beats/
      DELICIOUS=1 (default)        0.72x pocket BPM | VLC=1 (default) all audio effects
      dilla [out.mp3]              J Dilla beat — TRACK= preset (default pedal_e_descent)
      hiphop [out.mp3]             Slum Village engine (default TRACK=syncopated_slash_ninth)
      slum [dir]                   Batch session_01..14 → renders/ (Sonitex on)
      industrial [out.mp3]         Industrial techno (default renders/foundry_pulse.mp3)
      techno [out.mp3]             Hard distorted techno (#{TECHNO_BPM} BPM)
      analog [out.mp3]             Full analog pad restoration renderer
      analog_liveset [out] [min]   Long-form analog render
      render [out.mp3]             Core pad + drum synthesis
      electronium [out.mid]        MIDI (--electronium-classic=1 | --electronium-render=1)
      electronium-full [out.wav]   Full engine render of electronium_loop (--electronium-classic=1)

    VOCAL MIXES (Sirkel Sag × Voicemails)
      mix | v11                    Latest mix recipe (default v11)
      v7 | v8 | v9 | v10           Earlier mix generations

    SAMPLE PIPELINE
      prepare [path]               Drum kit + FFmpeg stem rack (neosoul.mp3 default)
      sample                       source → demucs → clean harmonic
      source [url|path] [out]      yt-dlp / ffmpeg capture audio
      separate [path]              Demucs 4-stem (htdemucs_ft)
      demux <url|path> [deep]      6-stem demucs (htdemucs_6s) + optional EQ sub-bands
      chop [path]                  Long recording → bar-aligned sample loops with
                                   drums and vocals stripped (samples/chopped/).
                                   Defaults to samples/ubrukte_samples.mp3.
                                   CHOP_CANDIDATES/CHOP_KEEP/CHOP_SPAN tune it.
      chop list                    Show the registered rack
                                   TRACK=<slug> renders over one; CHOP_BED=1 lets
                                   the engine pick one matching the KEY_LOCK tonic
      learn | ingest <url|path> [--apply] [--deep]
                                   Download → demucs → harmony/rhythm analysis → engine hints
                                   Saves project/learnings/last_learn.json; --apply sets ENV
      learn-apply                  Re-apply hints from last learn report
      learn-playlist [--all] [--limit N] [--force] [--no-deep] [--no-resume]
                                   Batch playlist.brgen.no (YouTube + local MP3) → demucs → analysis
      learn-playlist-agent [--foreground]  Background/resume agent → catalog + promote + calibrate
      learn-promote                  Merge catalog copyable_dna → learned_engine.json (runtime)
      learn-calibrate [--audio-root] Measured dossiers → global BPM/swing calibration
      learn-diff [--audio-root]      Curated vs measured vs learned diff report
      learn-flylo <url|path> [track] [apply] [shallow]
                                   yt-dlp → demucs → FlyLo 16-step grid → learned_engine
                                   Default track quartal_west_coast; Camel grid baked into engine
      rap-vocal ingest <artist> <url|path>
                                   yt-dlp → demucs → isolated vocals + phrase/BPM catalog
      rap-vocal fit <slug>         Time-stretch + bar-align vocals to current BPM/BARS
      rap-vocal list               Show ingested vocal catalog
      RAP_VOCAL=<slug> on render/stream  Auto-fit (atempo+bar phase) + mix (RAP_VOCAL_MIX, RAP_VOCAL_WEIGHT, RAP_VOCAL_BED_WEIGHT, RAP_VOCAL_SPARKLE_DB)
      LA_BEAT_PROGRESSION=1            Long random progressions + variable chord lengths (stream soul)
      FLYLO_DRUM_OVERLAY=1             FlyLo overlay; Camel grid on quartal_west_coast / flylo_camel
      clean <in> [out]             Denoise + loudnorm

    STEM RACK (stems/manifest.json)
      stems                        Register default rack from stems/
      stems add <name> <dir> [bpm] Add a stem set to manifest
      stems scan [root] [manifest] Legacy directory scan → manifest

    LIVESET
      liveset [set] [minutes]      Long-form WAV from stem rack (LIVESET_MIN=#{LIVESET_MIN})

    ANALYSIS & GRADE
      scan | ears | verify | study | grade | grade_list | chords
      vocab-check                  Chord symbols, arp figures and drum grids — no audio, ~1s.
                                   Every chord resolves to the chord it is named after, every
                                   arp builder returns a real line, every grid fits its bar.

    COMPOSITION (session in #{DillaComposition::PROJECT_DIR})
      jam [bars]                   Render + play with fresh session (motifs, performers, arrangement)
      evolve [bars] [generations]  Mutate motifs/performer/groove, score, keep best (GENERATIONS=5)
      critique [path]              Producer scores + recommendations on last render
      session [save|load|show|new] Persist/load/show composition memory
      regenerate-stem bass|hats|melody [bars]  Re-render one layer (motif/groove mutation)
      listen_loop [bars]           Render → analyze LUFS/groove → adjust mix (LISTEN_PASSES=3)
      COMPOSITION=0                Disable arrangement spine (legacy density sections)

    SONITEX
      sonitex_list                   List STX-1260 subset presets

    DEVICES (options are bare words, not --flags — the global flag parser eats those)
      macro                          The 8 macro words, and which knobs each moves
      macro dust=0.7 weight=0.6      What they would set; add `apply` to set it
      copy-machine in out copies=8   N copies of one sound at once, some reversed
                                       family=harmonic|chromatic|spray reverse=0..1
                                       width=0..1 drift=ms duration=S  `describe`
      hocket voices=4 mode=pendulum  One line split across voices (round_robin|
                                       pendulum|shift_register|random) hold=N `write`
      midi-bag order=cycle           Melody's pitches on the kit's rhythm
                                       order=cycle|random|walk rests=0..1 `fit-chords`
      wav-map image.png out.wav      A picture read as a waveform (brightness is
                                       elevation) path=circle|spiral|lissajous|rose
                                       hz=110 duration=S lobes=N  `describe`
      arrangement out.mp3 ref.wav    Does it have sections? Foote spectral novelty
                                       + short-term loudness spread, against a
                                       reference record.  `detail`
      modulate in out lfo=0.5        A parameter moved over time via asendcmd
                                       target=filter.param base=N depth=0..1
                                       mode=modulate|remote family=straight|curved

DEVICES IN A RENDER (all off by default; each replaces or adds a real layer)
  COPY_MACHINE=6                 The sampled bed played 6 times at once, at
                                   different speeds. COPY_MACHINE_FAMILY=
                                   harmonic|chromatic|spray, _REVERSE, _WIDTH,
                                   _DRIFT. Needs a track whose bed is on disk.
  MIDI_BAG=1                     The lead's pitches on the kit's onsets.
                                   MIDI_BAG_ORDER=cycle|random|walk,
                                   MIDI_BAG_RESTS=0.25, MIDI_BAG_FIT=1
                                   (snap each to the chord underneath).
  HOCKET=3                       The harmony lead split across 3 voices, each
                                   through a different EP program.
                                   HOCKET_MODE=round_robin|pendulum|
                                   shift_register|random, HOCKET_HOLD=1
  WAV_MAP=path.png               A picture read as an oscillator, mixed as a
                                   texture channel in the track's key.
                                   WAV_MAP_PATH=circle|spiral|lissajous|rose,
                                   _HZ, _WEIGHT, _HP, _LP, _LOBES
  BUS_MOD=texture                An LFO on a mix bus filter. Needs
                                   DILLA_MIX_BUSES=1. BUS_MOD_HZ=0.25,
                                   _FILTER=lowpass, _PARAM=frequency, _BASE,
                                   _DEPTH, _MODE=modulate|remote
  STREAM_MACROS=1                Rotate stream slots by macro word (dust,
                                   drift, weight, air…) instead of by knobs.

    ARRANGEMENT AND BUS
      SECTION_LAYERS=1 (default)     Drums, bass and the sampled bed follow the
                                       section map; pads and texture play flat
      SECTION_LAYERS=full            The harmony bus, the analog pad and the
                                       vinyl/rumble texture get section shapes
                                       too — the two loudest channels had none.
      FORM_FIT=1                     Stretch FORM/SECTION_MAP across the track
                                       instead of repeating it. soul_32 over 128
                                       bars is four intros without this; one with.
      DILLA_MIX_BUSES=1              Group the mix into kit/harmonic/low/texture
                                       buses instead of one flat amix
      DILLA_BUS_<NAME>=<filters>     A filter chain on one of those buses
      CONSOLE_STACK=3                Instances in the summing stack (1-4). Measured:
                                       at matched THD, 3 stages put 23 dB less third
                                       harmonic in than 1 — a warmth control, not a
                                       drive one. Reached via RACK=summed.
      MOD_RATE_HZ=48                 Modulation command resolution

    EXTERNAL ASSETS (opt-in only — engine is pure-Ruby/ffmpeg by default)
      fetch-assets                   Cache CC0 drum WAVs + extra soundfonts
                                      (galaxy, supersaw, giga-fm, yamaha-grand + VintageDreams)
      export-midi [dir]              Write every DRUM_PRESET as GM MIDI clips (default: samples/midi/)
      import-midi <dir>              MIDI drum clips -> 16-step grids (Ruby hash dump)
      use-external-kit <name>        Install a fetched kit into samples/drums/custom/
                                      (01-hard-trap | 02-bounce | 03-soulful-vintage)
      dig <seam> [n]                 Dig n public-domain sides into samples/dug/
      dig-seams                      List the seams available to dig
      dug                            What has been dug, and under what terms
      dig-cc <seam> [n]              Dig CC-BY stems (dub, roots, breaks) from ccMixter
      credits                        Attribution owed for CC-BY material in the crate
    FLAGS (equivalent to the ENV vars below, usable on any command):
      #{FLAG_ENV.keys.map { |k| "--#{k}=…" }.join(' ')}

    SCRATCH: caches + temp audio in #{SCRATCH_DIR} (DILLA_SCRATCH_DIR overrides).
      progressions_log.txt there is the only record of generated progressions.

    ENV: BPM BARS TRACK PROGRESSION SWING KICKS SONITEX SONITEX_PRESET BEAT LIVESET_MIN
         PERFORMER=yancey GROOVE_DNA=donuts COMPOSITION=1 GENERATIONS=5 LISTEN_PASSES=3
     KICKS=1 (default) enable kicks | KICKS=0 mute kick drum
         KICK_GAIN=0.88 (0.78 on flylo) kick/sub level scale — lower if still loud
         SONITEX=donuts_warm (default) | SONITEX=classic | SONITEX=heavy | SONITEX=0 dry
         crush off: SONITEX_SAMPLING=0  noise off: SONITEX_NOISE=0  TAPE_BIAS=1 TAPE_LOSS_HZ=0
         ANALOG_CHAIN=acetate|sp1200|auto (rotates per session in slum batch)
         FORCE_KIT=1 regenerate synth drums
         samples/drums/custom/ overrides kit
         TRACK = internal preset id (use session_01..14 outputs via slum command)
         IBPM=135 BARS=128 for industrial techno length
  HELP
end
