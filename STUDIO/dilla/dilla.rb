#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Dilla — unified audio engine
# Synthesis, analog pads, vocal mixes (v7–v11), stem rack, demux, MIDI electronium.
#
# Usage: ruby dilla.rb help

# lib/music_gems must load — and bootstrap! must run — before anything else
# requires a gem this Gemfile.lock pins (json 2.19.1, yaml/psych, ostruct):
# whichever code activates a gem name first wins for the whole process, and an
# unconstrained `require "json"`/`require "yaml"` below would activate
# whatever version ships as a Ruby default gem (e.g. json 2.20.0 on 3.4.9),
# so bootstrap!'s own `require "bundler/setup"` then conflicts and silently
# disables coltrane/midilib/wavefile/head_music for the rest of the process
# (bootstrap! rescues LoadError). Real invocations run plain `ruby dilla.rb`,
# not `bundle exec`, so this ordering is the only thing that pins it correctly.
require_relative "lib/music_gems"
DillaMusicGems.bootstrap!

# Everything the caller set before dilla touched the environment.
#
# force_env! overwrites unconditionally, so a style table always beat the
# command line: `SONITEX=heavy ruby dilla.rb ...` rendered donuts_warm,
# because DILLA_STYLE_DEFAULTS force both SONITEX and SONITEX_PRESET and ran
# after the caller's value was already in place. That is true of every knob
# those tables name, not just this one -- the documented environment
# variables were advisory at best.
#
# Captured before any require can mutate ENV. force_env! consults it and
# records the skip in config_provenance, so `print_config_provenance` shows
# which values the caller pinned and which a style chose.
#
# The stream re-execs itself when this file's mtime changes, and exec inherits
# the whole environment — including everything apply_best_defaults! and the
# style tables had already written into it. So after one restart the child's
# "user pins" contained TRACK/PROGRESSION=pedal_e_descent, values no user ever
# typed, and force_env! then refused to let any track's own progression
# overwrite them. Asking for slum_village_players_documented rendered its name
# and its 91 BPM over pedal_e_descent's chords, and no amount of restarting fixed
# it because each restart re-laundered the same defaults.
#
# The restart therefore declares the real pin set, and only those keys count as
# pinned in the child. Absent the declaration (a normal command line) every
# environment variable present at load is a pin, as before.
USER_PINNED_ENV = begin
  declared = ENV["DILLA_USER_PINNED_KEYS"]
  captured = ENV.to_h
  captured.delete("DILLA_USER_PINNED_KEYS")
  if declared.nil?
    captured.freeze
  else
    keys = declared.split(",")
    captured.select { |k, _| keys.include?(k) }.freeze
  end
end

require "fileutils"
require "json"
require "yaml"
require "shellwords"
require "tmpdir"
require_relative "../../MASTER/lib/io/analog_capabilities"
require "open3"
require "timeout"
require_relative "lib/mixer"
require_relative "lib/crate_dig"
require_relative "lib/radio_chop"
require_relative "lib/sample_flip"
require_relative "lib/vocal_chop"
require_relative "lib/analog_synth"
require_relative "lib/acapella"
require_relative "lib/outboard"
require_relative "lib/key_lock"
require_relative "lib/modal_family"
require_relative "lib/dilla_dmesg"
require_relative "lib/composition_engine"
require_relative "lib/groove_score"
require_relative "lib/harmony_score"
require_relative "lib/producer_dna"
require_relative "lib/harmony_engine"
require_relative "lib/harmony_lead"
require_relative "lib/theory_runtime"
require_relative "lib/groove_engine"
require_relative "lib/seed_providers"
require_relative "lib/provenance"
require_relative "lib/rhythm_macros"
require_relative "lib/master_heuristics"
require_relative "lib/spectral_engine"
require_relative "lib/dilla_ml"
require_relative "lib/dfam_engine"
require_relative "lib/automation_lane"

# Terse OpenBSD-style console log (see lib/dilla_dmesg.rb). Prefer dmesg over
# decorative banners; set DILLA_DMESG=0 to silence, =2 for verbose argv.
def dmesg(msg, unit: "dilla0", parent: nil)
  DillaDmesg.ok(msg, unit:, parent:)
end

def dmesg_warn(msg)
  DillaDmesg.warn(msg)
end

def dmesg_error(msg)
  DillaDmesg.error(msg)
end

ROOT = File.expand_path(__dir__)
# The entry script. The parts below cannot use __FILE__ for this: theirs is a
# part, not the engine.
ENGINE_FILE = File.expand_path(__FILE__)
# Finished renders default to the invoking directory (override with
# DILLA_OUTPUT_DIR). ROOT stays the base for samples/stems, which aren't
# user output.
OUTPUT_DIR = ENV.fetch("DILLA_OUTPUT_DIR", Dir.pwd)
# Every cache and temp file the engine writes lives here — never loose
# dotfiles in the invoking directory or next to the source. Safe to wipe,
# with one exception: the progressions log (see log_progression!) is the
# only record of generated progressions, which never repeat.
# scratch/, not .cache/: hidden folders make generated audio invisible to
# anyone looking at the project, and this engine writes a lot of it. One
# visible directory holds all of it, gitignored as a whole.
SCRATCH_DIR = ENV.fetch("DILLA_SCRATCH_DIR", File.join(ROOT, "scratch"))

def scratch_path(name)
  FileUtils.mkdir_p(SCRATCH_DIR)
  File.join(SCRATCH_DIR, name)
rescue Errno::EACCES, Errno::EROFS => e
  # Requiring this file has a side effect: STREAM_LOCK_PATH calls scratch_path
  # at load time, so simply `require`-ing dilla creates a directory. Anything
  # running as a different user than the checkout's owner then dies on load
  # rather than on use. That is not hypothetical — brgen's CI runs as user
  # brgen, its radio_bergen_study_test requires this file, and the whole Rails
  # suite aborted with EACCES on /home/dev/pub4/STUDIO/dilla/scratch, which
  # blocked the deploy of an app that has nothing to do with audio.
  #
  # A scratch directory is by definition disposable, so fall back to one we can
  # certainly write instead of taking the process down. DILLA_SCRATCH_DIR still
  # wins when set.
  fallback = File.join(Dir.tmpdir, "dilla-scratch-#{Process.uid}")
  warn "dilla: #{SCRATCH_DIR} is not writable (#{e.class}); using #{fallback}"
  FileUtils.mkdir_p(fallback)
  File.join(fallback, name)
end
SAMPLE_DIR = File.join(ROOT, "samples")
DRUM_DIR = File.join(SAMPLE_DIR, "drums")
CUSTOM_DRUM_DIR = File.join(DRUM_DIR, "custom")
# FM-synthesized kit (default on: FM_DRUMS!=0) -- true operator-modulating-
# operator FM, distinct from the analog pitch-swept-sine/filtered-noise kit.
# Separate directory so it never overwrites the analog oneshots.
FM_DRUM_DIR = File.join(DRUM_DIR, "fm")
STEM_DIR = File.join(ROOT, "stems")
SAMPLE_CLEAN = File.join(SAMPLE_DIR, "clean_harmonic.wav")
STEM_MIDS = File.join(STEM_DIR, "mids.mp3")
STEM_HIGHS = File.join(STEM_DIR, "highs_pluck.mp3")
STEM_SUB = File.join(STEM_DIR, "sub_bass.mp3")
STEM_CENTER = File.join(STEM_DIR, "center.mp3")
STEM_MANIFEST = File.join(STEM_DIR, "manifest.json")
STEM_EXTS = %w[.mp3 .wav .ogg .flac].freeze
DEMUX_DIR = SAMPLE_DIR
DEMUX_MODEL = "htdemucs_6s"
# Fine-tuned 4-stem model, used only for vocal ingest (not the shared 6-stem
# path -- it has no guitar/piano output, which other callers of demux_six
# rely on). Ingest is a one-time cost per source, cached in the rap-vocal
# catalog afterward, so the extra model/shifts time is worth spending here.
DEMUX_VOCAL_MODEL = "htdemucs_ft"

# The engine's own top-level program, split by concern. Required in the order
# they were written in, which is load-bearing: constants here are computed at
# load time from ones above them, and reordering silently changes their values.
ENGINE_PARTS = %w[
  source_learn
  track_tables
  patch_catalog
  voice_presets
  patch_select
  render_seed
  patch_pools
  radio_bergen
  resolve_config
  progression_build
  groove_timing
  percussion
  drum_policy
  render_scratch
  drum_bus
  sample_loops
  bus_filters
  render_helpers
  drum_bus_filter
  master_chain
  form_map
  lead_arp
  lead_melodic
  engine_defaults
  drum_patterns
  chord_tables
  progression_tables
  chord_theory
  shell
  cli_commands
  analysis
  grade_analog
  setlist
  speech
  live_play
  style_defaults
  archetypes
  stream_tuning
  env_locks
  stream_iterate
  apply_profiles
  mix_metrics
  showcase
  stream_rotation
  demo_catalog
  demo_all
  stream
  composition_glue
  learned_engine
  dilla_progression
  dilla_drums
  dilla_schedule
  drum_kit
  assets
  synth_samples
  native_synth
  midi_smf
  pad_render
  pad_layers
  lead_render
  render_dilla
  render_industrial
  composition_cmds
  help
  render_analog
  render_madlib
  render_techno
  mix_recipes
  flylo_learn
  rap_vocal
  organic
  crate
  sample_morph
  organic_vary
  tape_master
  rap_vocal_fit
  punk_guitar
  learn_source
  electronium
].freeze
ENGINE_PARTS.each { |part| require_relative "lib/engine/#{part}" }

# Every file the engine is made of. `wiring_check`, `debug` and the stream's
# restart-on-edit all mean "the engine", which stopped being one file.
ENGINE_SOURCES = ([ENGINE_FILE] +
                  ENGINE_PARTS.map { |part| File.join(ROOT, "lib", "engine", "#{part}.rb") }).freeze

def engine_source
  ENGINE_SOURCES.map { |path| File.read(path) }.join("\n")
end

def engine_mtime
  ENGINE_SOURCES.map { |path| File.mtime(path) }.max
end

# =============================================================================
# CLI — one table is the command list, the dispatch, and (via COMMANDS) the
# debug/introspection surface. Adding a command = adding one entry here.
# =============================================================================

# `--flag=value` forms of the tuning ENV vars, usable anywhere on the command
# line. ENV still works (flags win when both are set) — the flags exist so the
# contract is visible in `help` and greppable, not to replace the env interface.
FLAG_ENV = {
  "track" => "TRACK", "progression" => "PROGRESSION", "sonitex" => "SONITEX_PRESET",
  "analog-chain" => "ANALOG_CHAIN", "sidechain" => "SIDECHAIN", "bars" => "BARS",
  "bpm" => "BPM", "swing" => "SWING", "voicing" => "VOICING", "kicks" => "KICKS",
  "performer" => "PERFORMER", "groove-dna" => "GROOVE_DNA", "composition" => "COMPOSITION",
  "generations" => "GENERATIONS", "listen-passes" => "LISTEN_PASSES",
  "drum-preset" => "DRUM_PRESET", "pad-wave" => "PAD_WAVE", "dfam" => "DFAM",
  "bit-depth" => "BIT_DEPTH", "pad-attack" => "PAD_ATTACK", "pad-release" => "PAD_RELEASE",
  "soul-enrich" => "SOUL_ENRICH", "seed-text" => "SEED_TEXT", "tempo-ramp" => "TEMPO_RAMP",
  "markov-drums" => "MARKOV_DRUMS", "groove-lock" => "GROOVE_LOCK", "spectral-arp" => "SPECTRAL_ARP",
  "arp-idm-bias" => "ARP_IDM_BIAS", "arp-shape-bias" => "ARP_SHAPE_BIAS",
  "reharm-loop" => "REHARM_LOOP", "prime-grid" => "PRIME_GRID",
  "inharmonic" => "INHARMONIC", "genre" => "GENRE", "genre-harmony" => "GENRE_HARMONY",
  "evolve-harmony-w" => "EVOLVE_HARMONY_W", "evolve-groove-w" => "EVOLVE_GROOVE_W",
  "sidechain-style" => "SIDECHAIN_STYLE",
  "lead-voice" => "LEAD_VOICE", "lead-arp-mode" => "LEAD_ARP_MODE",
  "pad-voice" => "PAD_VOICE", "pad-arp-mode" => "PAD_ARP_MODE", "experimental-leads" => "EXPERIMENTAL_LEADS",
  "synth-cycle" => "SYNTH_CYCLE", "synth-morph" => "SYNTH_MORPH",
  "lead-morph" => "LEAD_MORPH", "lead-morph-voice" => "LEAD_MORPH_VOICE",
  "kick-gain" => "KICK_GAIN", "vinyl" => "VINYL", "external-kit" => "EXTERNAL_KIT",
  "creepy-patches" => "CREEPY_PATCHES", "lead-arp" => "LEAD_ARP", "raw" => "DILLA_RAW",
  "deep" => "DILLA_DEEP", "quality-gate" => "DILLA_QUALITY_GATE", "render-retries" => "RENDER_RETRIES",
  "pad-vol" => "PAD_VOL", "conv-reverb" => "CONV_REVERB", "render-beauty-min" => "RENDER_BEAUTY_MIN",
  "stream-deep" => "STREAM_DEEP", "phone-preview-gate" => "PHONE_PREVIEW_GATE",
  "speak" => "SPEAK", "speak-voice" => "SPEAK_VOICE", "speak-rate" => "SPEAK_RATE",
  "speak-pitch" => "SPEAK_PITCH", "speak-vol" => "SPEAK_VOL", "radio-bergen" => "RADIO_BERGEN",
  "stream-iterate" => "STREAM_ITERATE", "evolve-every" => "EVOLVE_EVERY",
  "pocket-kicks" => "POCKET_KICKS", "drum-chops" => "DRUM_CHOPS", "camel-chops" => "DRUM_CHOPS",
  "fm-drums" => "FM_DRUMS", "kick-double" => "KICK_DOUBLE", "kick-drop" => "KICK_DROP",
  "snare-prehit-ghost" => "SNARE_PREHIT_GHOST", "pocket-kick-silence" => "POCKET_KICK_SILENCE",
  "pocket-rush" => "POCKET_RUSH",
  "stream-crossfade" => "STREAM_CROSSFADE", "stream-gap" => "STREAM_GAP",
  "stream-creative-freedom" => "STREAM_CREATIVE_FREEDOM", "stream-evolve-performer" => "STREAM_EVOLVE_PERFORMER",
  "form" => "FORM", "section-map" => "SECTION_MAP", "render-mode" => "RENDER_MODE",
  "harmony-lead" => "HARMONY_LEAD", "harmony-lep-mode" => "HARMONY_LEP_MODE",
  "harmony-arp-style" => "HARMONY_ARP_STYLE", "stream-soul" => "STREAM_SOUL",
  "stream-drum-rotate" => "STREAM_DRUM_ROTATE",
  "stream-drum-bpm" => "STREAM_DRUM_BPM",
  "electronium-classic" => "ELECTRONIUM_CLASSIC", "electronium-render" => "ELECTRONIUM_RENDER",
  "electronium-septuplet" => "ELECTRONIUM_SEPTUPLET",
  "stream-track" => "STREAM_TRACK", "stream-lock" => "STREAM_LOCK",
  "stem-export" => "STEM_EXPORT", "keep-stems" => "KEEP_STEMS",
  "ghost-tier" => "GHOST_TIER", "motif-recall" => "MOTIF_RECALL", "slash-bass" => "SLASH_BASS",
  "profile-mash" => "PROFILE_MASH", "groove-score-min" => "GROOVE_SCORE_MIN",
  "promotion-beauty-min" => "PROMOTION_BEAUTY_MIN"
}.freeze

# Flags whose whole point is the value. A bare `--bars` is not a boolean; it is a
# missing number, and taking it as "1" corrupts the render quietly.
#
# `--bars 8` reads like it works and does not: the parser only understands
# `--key=value`, so it set BARS=1 and left "8" in argv as a positional argument.
# `ruby dilla.rb render --bars 8 --track slum_village_players_documented out.wav`
# therefore rendered ONE bar of a track literally named "1" into a file named "8",
# and the only symptom was `failed: ffmpeg` from a filtergraph built against a
# 2.79-second duration. Every one of those is silent on its own.
FLAGS_REQUIRING_VALUE = %w[
  bars bpm track progression swing voicing seed-text form section-map render-mode
  drum-preset lead-voice pad-voice pad-arp-mode lead-arp-mode synth-cycle
  external-kit generations listen-passes stream-track pad-vol kick-gain
].freeze

def apply_flags!(argv)
  argv.reject! do |arg|
    next false unless arg.start_with?("--")
    key, _, value = arg.delete_prefix("--").partition("=")
    env_name = FLAG_ENV[key] or abort "unknown flag --#{key} — known: #{FLAG_ENV.keys.map { |k| "--#{k}" }.join(' ')}"
    if value.empty? && FLAGS_REQUIRING_VALUE.include?(key)
      abort "--#{key} needs a value, and it has to be attached: --#{key}=VALUE (not --#{key} VALUE)"
    end
    ENV[env_name] = value.empty? ? "1" : value
    true
  end
end

DISPATCH = {
  "capabilities" => -> { puts Master::Io::AnalogCapabilities.report(:dilla) },
  "quality" => -> { dilla_quality(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3"), ARGV.shift) },
  "help" => -> { help },
  "scan" => -> { scan },
  "sweep" => -> { sweep },
  "council" => -> { council },
  "debug" => -> { debug },
  "config-provenance" => -> { print_config_provenance },
  "sample" => -> { sample },
  "source" => -> { source(ARGV.shift, ARGV.shift) },
  "livestream" => -> { livestream(ARGV.shift, ARGV.shift) },
  "separate" => -> { separate(ARGV.shift) },
  "render" => -> { render(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3")) },
  "verify" => -> { verify(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3")) },
  "chords" => -> { chords },
  "vocab-check" => -> { vocab_check },
  "clean" => -> { clean(ARGV.shift, ARGV.shift || File.join(OUTPUT_DIR, "clean.wav")) },
  "stems" => -> { stems(*ARGV) },
  "study" => -> { study(ARGV.shift, ARGV.shift) },
  "radio-bergen-study" => lambda {
    audio_root = nil
    if (idx = ARGV.index("--audio-root"))
      audio_root = ARGV[idx + 1]
      ARGV.delete_at(idx + 1)
      ARGV.delete_at(idx)
    end
    path = RadioBergenStudy.write!(audio_root:)
    data = RadioBergenStudy.study!(audio_root:)
    remove_instance_variable(:@radio_bergen_learnings) if instance_variable_defined?(:@radio_bergen_learnings)
    remove_instance_variable(:@sonic_profiles) if instance_variable_defined?(:@sonic_profiles)
    load_radio_bergen_learnings
    puts "wrote #{path} (#{data.dig('meta', 'track_count')} tracks)"
    puts "rotation weights: #{load_radio_bergen_learnings['stream_rotation_weights']&.keys&.first(6)&.join(', ')}"
  },
  "radio-bergen-analyze" => lambda {
    audio_root = nil
    if (idx = ARGV.index("--audio-root"))
      audio_root = ARGV[idx + 1]
      ARGV.delete_at(idx + 1)
      ARGV.delete_at(idx)
    end
    path = RadioBergenStudy.write_dossiers!(audio_root:)
    data = RadioBergenStudy.dossiers!(audio_root:)
    puts "wrote #{path}"
    puts "measured #{data.dig('meta', 'measured_local')}/#{data.dig('meta', 'tracks')} tracks"
  },
  "radio-bergen-dossiers" => lambda {
    path = RadioBergenStudy.write_dossiers!
    data = RadioBergenStudy.dossiers!
    puts "wrote #{path}"
    puts "measured #{data.dig('meta', 'measured_local')}/#{data.dig('meta', 'tracks')} tracks"
  },
  "radio-bergen-librosa" => lambda {
    py = File.expand_path("venv-librosa/bin/python3", ROOT)
    script = File.expand_path("scripts/librosa_analyze.py", ROOT)
    unless File.executable?(py) && File.file?(script)
      abort "librosa venv missing — run: cd STUDIO/dilla && python3 -m venv venv-librosa && " \
            "venv-librosa/bin/pip install librosa pyyaml"
    end
    sh! py, script
  },
  "rhythm" => -> { rhythm(ARGV.shift) },
  "melody" => -> { melody(ARGV.shift) },
  "harmony" => -> { harmony(ARGV.shift) },
  "beauty" => -> { beauty_report(ARGV.shift) },
  "crate" => -> { build_crate!(ARGV.shift || CRATE_DIR) },
"mix-score" => lambda {
    require_relative "lib/mix_score"
    a = ARGV.shift
    b = ARGV.shift
    if b
      MixScore.compare(a.to_s, b.to_s)
    else
      exit(MixScore.report(a.to_s) ? 0 : 1)
    end
  },
  "verify-fx" => lambda {
    require_relative "lib/verify_fx"
    exit(VerifyFx.verify! ? 0 : 1)
  },
  # What has been built that nothing can select?
  #
  # Six separate faults in one session were the same shape: a capability was
  # finished and no rotation table referenced it, so it never rendered and never
  # got tested. The counter-line lead, the chopped sample loops, the Flying Lotus
  # kits, 24 pad voices, a pad whose effect chain had never once opened, and 209
  # of 250 chord progressions. Each was found by ear or by accident, one at a
  # time. This finds them all at once.
  "audit" => -> { exit(capability_audit! ? 0 : 1) },
  "import-midi" => -> { import_midi_drums!(ARGV.shift.to_s) },
  "export-midi" => -> { export_midi_drums!(ARGV.shift || MIDI_SEED_DIR) },
  "crit" => -> { crit_session_cli!(ARGV.shift) },
  "phone-preview" => -> { phone_preview(ARGV.shift) },
  "semantics" => -> { semantics(ARGV.shift) },
  "ears" => -> { ears(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3")) },
  "play" => -> { play(ARGV.shift, (ARGV.shift || 8).to_i) },
  "live" => -> { live((ARGV.shift || 32).to_i) },
  "stream" => -> { stream((ARGV.shift || stream_bars_default).to_i) },
  "demo-all" => lambda do
    bars = (ARGV[0]&.match?(/\A\d+\z/) ? ARGV.shift : nil) || ENV["BARS"] || "12"
    out = ARGV.shift
    demo_all(bars.to_i, out)
  end,
  # Same catalogue, same settings, one mp3 per track in demos/ and no concat.
  # BARS is read here rather than left to apply_best_defaults!, which sets 32 and
  # would otherwise silently override the 12 this and demo-all both default to.
  "demo-each" => lambda do
    bars = (ARGV[0]&.match?(/\A\d+\z/) ? ARGV.shift : nil) || ENV["BARS"] || "12"
    ENV["DEMO_EACH"] = "1"
    ENV["BARS"] = bars.to_s
    demo_all(bars.to_i)
  end,
  # demo-all is 84 tracks: ~45 minutes to render and ~47 to listen to. That is
  # the wrong loop for judging a change, because by the time it finishes you no
  # longer remember what the last version sounded like. This renders an evenly
  # spaced sample of the same catalogue under the same settings — 12 tracks,
  # roughly six minutes each way — so a change can be heard while the previous
  # one is still fresh. Use demo-all for a final pass.
  "demo-quick" => lambda do
    bars = (ARGV[0]&.match?(/\A\d+\z/) ? ARGV.shift : nil) || ENV["BARS"] || "8"
    out = ARGV.shift || File.join(ROOT, "demo_quick.wav")
    n = (ENV["DEMO_QUICK_TRACKS"] || "12").to_i.clamp(2, 84)
    order = demo_all_order
    # Every nth across the catalogue rather than the first n: the order is not
    # random, so the head of it is not a fair sample of the whole.
    step = [order.length / n, 1].max
    ENV["DEMO_TRACKS"] = order.each_slice(step).map(&:first).first(n).join(",")
    ENV["DEMO_MP3"] ||= "0"
    demo_all(bars.to_i, out)
  end,
  "live_now" => -> { live_now },
  "harmony_now" => -> { harmony_now },
  "regenerate" => -> { regenerate((ARGV.shift || 16).to_i) },
  "regenerate-stem" => lambda do
    stem = ARGV.shift or abort "usage: ruby dilla.rb regenerate-stem bass|hats|melody [bars]"
    regenerate_stem(stem, (ARGV.shift || 16).to_i)
  end,
  # Not "liveset" — that name is already a long-form WAV from the stem rack,
  # with its own render_liveset(name, minutes:). A setlist is the other thing:
  # the recipe for a set of takes, replayable.
  "setlist" => lambda do
    file = ARGV.shift or abort("usage: setlist <file.dilla> [outdir]  |  setlist --save <file.dilla>")
    if file == "--save"
      target = ARGV.shift or abort("usage: setlist --save <file.dilla>")
      save_setlist(target)
    else
      render_setlist(file, ARGV.shift)
    end
  end,
  "jam" => -> { composition_jam((ARGV.shift || 16).to_i) },
  "evolve" => lambda do
    n = (ARGV.shift || 16).to_i
    gens = ARGV[0]&.match?(/\A\d+\z/) ? ARGV.shift.to_i : 5
    composition_evolve(n, gens)
  end,
  "critique" => -> { composition_critique(ARGV.shift) },
  "session" => -> { composition_session_cmd(ARGV.shift, *ARGV) },
  "listen_loop" => -> { composition_listen_loop((ARGV.shift || 16).to_i) },
  "bass" => -> { bass((ARGV.shift || 55.0).to_f) },
  "grade" => -> { grade(ARGV.shift, ARGV.shift, ARGV.shift) },
  "fetch-assets" => -> { fetch_assets! },
  "dig" => -> { crate_dig!(ARGV.shift, (ARGV.shift || 8).to_i) },
  "dig-seams" => -> { crate_seams },
  "dig-cc" => -> { cc_dig!(ARGV.shift, (ARGV.shift || 6).to_i) },
  "credits" => -> { crate_credits },
  "dug" => -> { dug_list },
  "use-external-kit" => -> { use_external_kit!(ARGV.shift || abort("usage: use-external-kit <01-hard-trap|02-bounce|03-soulful-vintage>")) },
  "grade_list" => -> { grade_list },
  "sonitex_list" => -> { sonitex_list },
  "analog_list" => -> { analog_list },
  "prepare" => -> { prepare(ARGV.shift) },
  "loose_pocket" => lambda do
    out = ARGV.shift
    if out.nil? || out == "beats"
      render_madlib_album(out == "beats" ? (ARGV.shift || File.join(ROOT, "renders", "beats")) : File.join(ROOT, "renders", "beats"))
    else
      render_madlib_drums(out)
    end
  end,
  "lofi" => -> { puts JSON.pretty_generate(DillaLofiMachine.machine_status(ENV["TRACK"])) },
  "dfam" => lambda do
    require_tools! "ffmpeg"
    pick_render_seed!
    cfg = dilla_resolve_config
    n = (ARGV.shift || 4).to_i
    beat_p = 60.0 / cfg[:bpm]
    events = Hash.new { |h, k| h[k] = [] }
    schedule_dfam_events!(events, n, beat_p, cfg[:swing], cfg[:quintuplet], cfg[:timing])
    path = File.join(OUTPUT_DIR, "dfam_preview.wav")
    duration = (beat_p * 4.0 * n).round(3)
    render_dfam_wav(path, events[:dfam], duration)
    puts "wrote #{path} (#{cfg[:bpm].round} BPM, #{n} bars, DFAM 8-step)"
    play(path) if ARGV.shift != "no-play"
  end,
  # One render path. Mix knobs via ENV (STREAM_COMFORT, RENDER_MODE=…), not command names.
  "dilla" => lambda do
    dest = ARGV.shift || File.join(OUTPUT_DIR, "beat.mp3")
    n_bars = ARGV[0]&.match?(/\A\d+\z/) ? ARGV.shift.to_i : nil
    normalize_render_mode!
    unless ENV["DILLA_RAW"] == "1"
      apply_dilla_style!(force: false)
      apply_comfort_style!(force: true) if comfort_mode?
    end
    render_dilla(dest, n_bars)
  end,
  "hiphop" => -> { render_hiphop(ARGV.shift || File.join(OUTPUT_DIR, "hiphop.mp3")) },
  "slum" => -> { render_slum_album(ARGV.shift || File.join(ROOT, "renders")) },
  "industrial" => -> { render_industrial(ARGV.shift || File.join(ROOT, "renders", "foundry_pulse.mp3")) },
  "techno" => -> { render_techno(ARGV.shift || File.join(OUTPUT_DIR, "techno_hate.mp3")) },
  # Long-form industrial techno with layers that arrive and leave.
  # HATE_MIN sets the length in minutes, HATE_BPM the tempo (130-150 is the range).
  "hate" => -> { render_hate_techno(ARGV.shift || File.join(ROOT, "renders", "hate_session.mp3")) },
  "analog" => -> { render_analog(ARGV.shift || File.join(OUTPUT_DIR, "analog_full.mp3")) },
  "analog_liveset" => -> { analog_liveset(ARGV.shift || File.join(OUTPUT_DIR, "analog_liveset.mp3"), (ARGV.shift || 12).to_f) },
  "electronium" => -> { electronium_dispatch! },
  "electronium-full" => lambda {
    dest = ARGV.shift || File.join(OUTPUT_DIR, "electronium.wav")
    electronium_full_render(dest, classic: ENV["ELECTRONIUM_CLASSIC"] == "1")
  },
  "mix" => -> { run_mix(ARGV.shift || "v11") },
  "v7" => -> { run_mix("v7") },
  "v8" => -> { run_mix("v8") },
  "v9" => -> { run_mix("v9") },
  "v10" => -> { run_mix("v10") },
  "v11" => -> { run_mix("v11") },
  "demux" => lambda do
    src = ARGV.shift or abort "usage: ruby dilla.rb demux <url-or-path> [deep]"
    ARGV[0] == "deep" ? demux_deep(src) : demux_six(src)
  end,
  "chop" => -> { chop_dispatch! },
  # Recovers the voices the chop pipeline separated and then discarded. Needs no
  # new separation: demucs already wrote vocals.wav for every cut it examined.
  "vocal-chop" => -> { VocalChop.build! },
  # Measures every separated acapella against its own mix and records the
  # tempo and first downbeat. Fitting happens per render, at that tempo.
  "acapella" => -> { Acapella.index! },
  # The other half, which the library had constants for and no code: put an
  # indexed acapella over a beat that already exists as a file. `acapella`
  # measured every vocal and wrote samples/acapella/index.json, and nothing
  # opened it.
  #
  # Distinct from RAP_VOCAL_*, which places a voice while a track renders.
  # This one takes a finished wav and a tempo and hands back a wav with
  # somebody on it, which is what you want for a beat that already exists --
  # a bounced take, a stem, something off the stream.
  #
  # Flags go through apply_flags! like everywhere else, so it is --bpm=88 and
  # --bars=16 (BPM and BARS), and who may appear is VOCAL_ONLY / VOCAL_EXCLUDE
  # -- the same two lists index! and ranked already read. No new vocabulary.
  "acapella-lay" => lambda do
    beat = ARGV.shift or abort "usage: ruby dilla.rb acapella-lay <beat.wav> [out.wav] --bpm=N [--bars=N]"
    abort "acapella-lay: no such file #{beat}" unless File.file?(beat)

    bpm = ENV["BPM"].to_f
    abort "acapella-lay: --bpm=N is the beat's own tempo and is required" unless bpm.positive?

    bars = (ENV["BARS"] || "16").to_i
    dest = ARGV.shift || beat.sub(/(\.\w+)?\z/) { |ext| "_vocal#{ext}" }
    laid = Acapella.over!(beat:, dest:, bpm:, bars:)
    abort "acapella-lay: nothing laid" unless laid

    puts format("ok: %s  %s %.1f->%.1f bpm%s  %d bars  from %.2fs",
                laid[:out], laid[:slug], laid[:from_bpm], laid[:to_bpm],
                laid[:half_time] ? " (half-time)" : "", laid[:bars], laid[:start_sec])
  end,
  # Auditions the built-in synthesiser, one file per patch. PATCH=<name> for one.
  "synth" => -> { synth_audition! },
  # A drum kit cut from our own recordings. The inverse of `chop`: that one
  # runs demucs and throws the drum stem away, this one keeps only the drums.
  "kit" => lambda do
    require_relative "lib/kit_dig"
    cmd = demucs_cmd or abort "demucs required — see `ruby dilla.rb chop` for the venv setup"
    KitDig.build!(demucs: cmd, limit: ENV["KIT_LIMIT"]&.to_i)
  rescue RuntimeError => e
    abort "kit: #{e.message}"
  end,
  "learn" => lambda do
    src = ARGV.shift or abort "usage: ruby dilla.rb learn <url-or-path> [--apply] [--deep]"
    apply = ARGV.delete("--apply")
    deep = ARGV.delete("--deep")
    learn_source!(src, apply: !apply.nil?, deep: !deep.nil?)
  end,
  "learn-flylo" => lambda do
    src = ARGV.shift or abort "usage: ruby dilla.rb learn-flylo <url-or-path> [track] [apply] [shallow]"
    apply = !ARGV.delete("apply").nil?
    deep = ARGV.delete("shallow").nil?
    track_arg = ARGV.reject { |a| a.start_with?("-") }.first
    track = (track_arg || "quartal_west_coast").to_sym
    slug = track == :quartal_west_coast ? "flylo_camel" : track.to_s
    learn_flylo_drums!(src, track:, slug:, apply:, deep:)
  end,
  "learn-apply" => lambda do
    report = DillaSourceLearn.load_last_report or abort "no last learn report — run: ruby dilla.rb learn <url>"
    applied = DillaSourceLearn.apply_hints_to_env!(report[:engine_hints])
    ENV["STREAM_LEARN_BIAS"] = "1"
    puts "applied: #{applied.join(', ')}"
  end,
  "learn-playlist" => lambda do
    youtube_only = !ARGV.delete("--all")
    deep = !ARGV.delete("--no-deep")
    resume = !ARGV.delete("--no-resume")
    force = !ARGV.delete("--force")
    no_promote = ARGV.delete("--no-promote")
    limit = nil
    if (idx = ARGV.index("--limit"))
      limit = ARGV.delete_at(idx + 1)
      ARGV.delete_at(idx)
    end
    learn_playlist_batch!(youtube_only:, deep:, resume:, limit:, force:,
                          promote: !no_promote)
  end,
  "learn-playlist-agent" => lambda do
    learn_playlist_agent!(foreground: ARGV.delete("foreground"))
  end,
  "learn-promote" => -> { learn_promote! },
  "learn-calibrate" => lambda do
    audio_root = nil
    if (idx = ARGV.index("--audio-root"))
      audio_root = ARGV[idx + 1]
    end
    learn_calibrate!(audio_root:)
  end,
  "learn-diff" => lambda do
    audio_root = nil
    if (idx = ARGV.index("--audio-root"))
      audio_root = ARGV[idx + 1]
    end
    learn_diff_dossiers!(audio_root:)
  end,
  "rap-vocal" => lambda do
    sub = ARGV.shift or abort "usage: ruby dilla.rb rap-vocal ingest|fit|list ..."
    case sub
    when "ingest"
      artist = ARGV.shift or abort "usage: rap-vocal ingest <artist> <youtube-url-or-path>"
      src = ARGV.shift or abort "usage: rap-vocal ingest <artist> <youtube-url-or-path>"
      rap_vocal_ingest!(artist, src)
    when "fit"
      slug = ARGV.shift or abort "usage: rap-vocal fit <slug>"
      cfg = dilla_resolve_config
      n_bars = (ENV["BARS"] || bars).to_i
      rap_vocal_fit!(slug, beat_bpm: cfg[:bpm], n_bars:, progression: cfg[:progression])
    when "list"
      puts JSON.pretty_generate(rap_vocal_load_catalog)
    else
      abort "usage: ruby dilla.rb rap-vocal ingest|fit|list"
    end
  end,
  # Print the command that rebuilds a render. The .dilla file carries it; this
  # saves reading JSON to find it.
  "replay" => lambda do
    manifest = ARGV.shift or abort "usage: ruby dilla.rb replay <file.dilla>"
    puts DillaProvenance.replay_command(manifest)
  end,
  "liveset" => lambda do
    set = ARGV.shift || stems_load_manifest["active"] || "default"
    mins = (ARGV.shift || LIVESET_MIN).to_i
    render_liveset(set, minutes: mins)
  end,
}.freeze

# No command aliases — every name is a real DISPATCH key (or help).
COMMANDS = DISPATCH.keys.sort.freeze

def render_output_path?(token)
  token =~ /\.(wav|mp3|flac|ogg|m4a|aiff?)\z/i
end

if __FILE__ == $PROGRAM_NAME
  # Before anything reads a seed. Draws and records RENDER_SEED when it is unset,
  # so every file this run produces gets a .dilla recipe beside it and can be
  # made again. DILLA_NO_PROVENANCE=1 restores the old unrecorded behaviour.
  DillaProvenance.begin!(root: OUTPUT_DIR, argv: ARGV)

  pad_voice_before = ENV["PAD_VOICE"]
  pad_arp_before = ENV["PAD_ARP_MODE"]
  apply_best_defaults!
  apply_flags!(ARGV)
  unless ENV["DILLA_RAW"] == "1"
    pad_locked = (pad_voice_before && !pad_voice_before.empty?) ||
                 (pad_arp_before && !pad_arp_before.empty?)
    apply_track_soul_profile!(ENV["TRACK"], force: !pad_locked) if ENV["TRACK"] && !ENV["TRACK"].empty?
  end
  cmd = ARGV.shift
  if cmd.nil?
    # Bare invoke: render demo.wav showcasing every named style/progression,
    # a few bars each. Used to default to stream() (an infinite live-playback
    # loop needing afplay/ffplay + real speakers) -- that's still available
    # explicitly via `ruby dilla.rb stream`, but convention-over-configuration
    # means the zero-args path should finish and produce a real file, runnable
    # headless/over SSH, not hang forever waiting on an audio device.
    showcase_demo!
  elsif render_output_path?(cmd) && !DISPATCH.key?(cmd)
    ARGV.unshift(cmd)
    default_render!
  else
    handler = DISPATCH[cmd]
    handler ? handler.call : help
  end
end
