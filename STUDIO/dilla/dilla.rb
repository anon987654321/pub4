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
# Before anything reads a file. The engine's own sources carry UTF-8 — em dashes
# and Norwegian vowels in comments and track names — and 37 File.read/readlines
# sites across lib/ ask for no encoding, so they inherit the locale's. Under a C
# or POSIX locale that is US-ASCII, and the first thing to read a source file
# raises: `env -i ruby dilla.rb help` died at lib/knobs.rb:228 building the knob
# table, before printing a word of help.
#
# It never bit interactively because a login shell exports a UTF-8 LANG. It bites
# anything that does not: cron, a minimal deploy shell, an agent's non-login
# invocation. One assignment here rather than an encoding: argument on all 37,
# which is also how RAILS/gates/runner.rb solved the identical problem — see
# OPENBSD/lib/utf8.rb and the comment above its require.
Encoding.default_external = Encoding::UTF_8

require_relative "lib/music_gems"
DillaMusicGems.bootstrap!
# The one definition of which files the engine is made of. Required this early
# because it has no dependencies and ENGINE_PARTS below is read out of it.
require_relative "lib/engine_sources"

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
    captured
  else
    keys = declared.split(",")
    captured.select { |k, _| keys.include?(k) }
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
# Parameters that move over time, and the small devices that move them. modulation
# reads TapeHysteresis for its random walk and requires it itself; macros reads
# knobs.rb, which is why it comes after.
require_relative "lib/modulation"
require_relative "lib/devices"
require_relative "lib/knobs"
require_relative "lib/frozen_state"
require_relative "lib/assets_manifest"
require_relative "lib/taste"

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

# Installed tools, which are not scratch.
#
# The demucs virtualenv lived in scratch/ and is 23,783 files -- 99% of
# everything under a directory whose name promises it can be deleted, and enough
# to make the tree unreadable in any file browser. It is an installation: slow to
# rebuild, unaffected by a render, and the one thing in there that must survive a
# clean. Named once here because three files were each computing the same path
# from SCRATCH_DIR, so moving it meant finding all three.
TOOLS_DIR = ENV.fetch("DILLA_TOOLS_DIR", File.join(ROOT, "tools"))
DEMUX_VENV_DIR = File.join(TOOLS_DIR, "venv-demucs").freeze

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

# The engine's own top-level program, split by concern. The list and its order
# live in lib/engine_sources.rb, which is also what provenance, the parse check
# and the wiring ratchets read -- see that file for why there is exactly one of
# them now. The order is load-bearing: constants in these files are computed at
# load time from ones above them, and reordering silently changes their values.
ENGINE_PARTS = DillaSources::ENGINE_PARTS
ENGINE_PARTS.each { |part| require_relative "lib/engine/#{part}" }

# A part sitting in lib/engine/ that ENGINE_PARTS does not name is never
# required. Nothing failed when that happened -- the file simply did not exist
# as far as the running engine was concerned -- so say it at load.
unless DillaSources.unlisted_parts.empty?
  warn "dilla: lib/engine/ holds #{DillaSources.unlisted_parts.length} file(s) no ENGINE_PARTS entry " \
       "requires, so nothing in them runs: " +
       DillaSources.unlisted_parts.map { |p| File.basename(p) }.join(", ")
end

# Every file the engine is made of. `wiring_check`, `debug`, provenance and the
# stream's restart-on-edit all mean "the engine", which stopped being one file.
ENGINE_SOURCES = DillaSources.all

def engine_source
  ENGINE_SOURCES.map { |path| File.read(path) }.join("\n")
end

def engine_mtime
  ENGINE_SOURCES.map { |path| File.mtime(path) }.max
end

# =============================================================================
# Sidecar replay, balance audition, demo matrix, album master
# =============================================================================

# Every .dilla sidecar pins the whole environment of a render. Replaying it with
# the seed keys dropped draws a fresh performance from the same recipe, which is
# what a new take means here: seed and performer rotate per run and renders are
# not reproducible bit for bit, so pinning the seed buys nothing and hides that
# this is a new take.
def replay_environment(src, overrides = {})
  path = src.end_with?(".dilla") ? src : "#{src}.dilla"
  abort "no sidecar at #{path}" unless File.file?(path)

  JSON.parse(File.read(path)).fetch("environment")
      .reject { |key, _| key.match?(/RENDER_SEED\z/) }
      .merge(overrides)
end

# KEY=VAL pairs left on the command line. One command covers the fresh-take,
# lossless-re-render and remake-from-another-sample cases.
def replay_overrides(tokens)
  tokens.each_with_object({}) do |token, out|
    key, value = token.split("=", 2)
    out[key] = value if value
  end
end

# A .wav destination masters from a first-generation source instead of decoding
# an mp3 and re-encoding it. Width comes from master_chain's stereotools rather
# than a Haas delay, so the result does not comb in mono. True peak is NOT fixed
# here: cli_commands measures it and appends a warning, then ships anyway.
def rerender_from_sidecar(src, dest, overrides = {})
  env = replay_environment(src, overrides)
  bars = env["BARS"] || "32"
  warn "rerender #{File.basename(src)} -> #{dest}"
  warn "  #{env.size} vars replayed, seed dropped, BARS=#{bars} " \
       "SAMPLE_LOOP=#{env['SAMPLE_LOOP'].inspect} MASTER_WIDTH=#{env['MASTER_WIDTH'].inspect}"
  exec(env, RbConfig.ruby, File.join(ROOT, "dilla.rb"), "dilla", "--bars=#{bars}", dest)
end

# Sample-to-pad balance, so it can be chosen by ear rather than by argument.
#
# The record carries its own harmony, so nothing else should state one.
# semua_untuk_mu has vocal chords in it, and a curated progression played by pads
# on top is a second piece of music in the same bar — which is what the harmonic
# guard says in as many words. That guard only fires when the loop's key is
# unreadable; this loop reads G minor at fit 0.75, so the pads played.
#
# DRUM_FORWARD=0 throughout: the default carves the bed at 180/3000 Hz to clear
# room for drums, which removes the sample's body and leaves the noisy middle.
BALANCE_VARIANTS = {
  # Mutes exactly the layer list the harmonic guard mutes, plus the synth voices.
  # FLIP=0 because the chords are IN the record and chopping it destroys them.
  "chordless" => { "PAD_VOL" => "0", "HARM_MIX_WEIGHT" => "0", "MELODIC_LEAD" => "0",
                   "SCALE_LEAD" => "0", "LEAD_ARP" => "0", "HARMONY_LEAD" => "0",
                   "PAD_LAYERS" => "0", "PAD_TEXTURE" => "0", "CHOIR_VOX" => "0",
                   "LUSH_SYNTH" => "0", "SYNTH_MORPH" => "0", "LEAD_MORPH" => "0",
                   "SAMPLE_LOOP_VOL" => "1.2", "SAMPLE_LOOP_WEIGHT" => "1.5",
                   "DRUM_FORWARD" => "0", "FLIP" => "0" },
  "flip_only" => { "FLIP" => "1", "FLIP_RECORDS" => "1", "VOCAL_CHOPS" => "0", "DRUM_FORWARD" => "0" },
  "flip" => { "FLIP" => "1", "DRUM_FORWARD" => "0" },
  "a_sample_forward" => { "SAMPLE_LOOP_VOL" => "1.3", "SAMPLE_LOOP_WEIGHT" => "1.6",
                          "HARM_BUS_VOL" => "1.4", "DRUM_FORWARD" => "0" },
  "b_pads_back" => { "SAMPLE_LOOP_VOL" => "1.3", "SAMPLE_LOOP_WEIGHT" => "1.6",
                     "HARM_BUS_VOL" => "1.0", "DRUM_FORWARD" => "0" },
  "c_sample_leads" => { "SAMPLE_LOOP_VOL" => "1.5", "SAMPLE_LOOP_WEIGHT" => "1.8",
                        "HARM_BUS_VOL" => "0.7", "DRUM_FORWARD" => "0" },
}.freeze

BALANCE_RECIPE = "renders/beats/dilla_semua_96.mp3"

def render_balance(name)
  overrides = BALANCE_VARIANTS.fetch(name) { abort "unknown variant #{name}" }
  dest = File.join(ROOT, "renders", "wav", "semua_#{name}.wav")
  warn "#{name} -> #{dest}"
  warn "  sample vol #{overrides['SAMPLE_LOOP_VOL']} weight #{overrides['SAMPLE_LOOP_WEIGHT']}  " \
       "pads #{overrides['HARM_BUS_VOL']}  bed carve off"
  rerender_from_sidecar(File.join(ROOT, BALANCE_RECIPE), dest, overrides)
end

# A demo of dilla is generated, not assembled from whatever is sitting in
# renders/beats — that would treat old output as the work. SAMPLE_LOOP picks the
# record and TRACK picks the progression, chosen independently so each record is
# heard against more than one harmonic setting.
#
# semua_untuk_mu carries carries_own_harmony in the crate, so its beats mute the
# tonal layers automatically. Nothing here special-cases it; the flag does.
DEMO_PROGRESSIONS = %w[pedal_e_descent circle_fifths_descent minor_iv_loop].freeze
DEMO_SAMPLES = %w[semua_untuk_mu arat_swost_wolet kembara_rindu lo_borges rauingar].freeze
DEMO_MIN_BYTES = 1_000_000

def generate_demo(bars: ENV.fetch("BARS", "32"), parallel: ENV.fetch("PARALLEL", "3").to_i)
  out = File.join(ROOT, "renders", "demo")
  FileUtils.mkdir_p(out)
  base = replay_environment(File.join(ROOT, BALANCE_RECIPE))

  jobs = DEMO_SAMPLES.flat_map do |sample|
    DEMO_PROGRESSIONS.map do |progression|
      { sample:, progression:, dest: File.join(out, "#{sample}__#{progression}.wav") }
    end
  end
  jobs.reject! { |job| File.file?(job[:dest]) && File.size(job[:dest]) > DEMO_MIN_BYTES }

  puts "#{jobs.size} beats to render (#{DEMO_SAMPLES.size} records x " \
       "#{DEMO_PROGRESSIONS.size} progressions), #{bars} bars, #{parallel} at a time"

  jobs.each_slice(parallel) { |batch| demo_render_batch(batch, base, bars) }
  puts "#{jobs.count { |job| File.file?(job[:dest]) }}/#{jobs.size} beats in #{out}/"
end

def demo_render_batch(batch, base, bars)
  pids = batch.map do |job|
    env = base.merge("SAMPLE_LOOP" => job[:sample], "TRACK" => job[:progression],
                     "PROGRESSION" => job[:progression], "BARS" => bars)
    log = File.join(Dir.tmpdir, "demo_#{job[:sample]}__#{job[:progression]}.log")
    puts "  -> #{File.basename(job[:dest])}"
    spawn(env, RbConfig.ruby, File.join(ROOT, "dilla.rb"), "dilla", "--bars=#{bars}", job[:dest],
          out: log, err: log)
  end
  pids.each { |pid| Process.wait(pid) }
  batch.each do |job|
    ok = File.file?(job[:dest]) && File.size(job[:dest]) > DEMO_MIN_BYTES
    puts format("  %-46s %s", File.basename(job[:dest]),
                ok ? "ok #{File.size(job[:dest]) / 1_048_576}MB" : "FAILED")
  end
end

# Album master. The chain per track, in this order:
#
#   1. side-gain correction     The fix. Five tracks measured a SIDE channel
#                               louder than their MID, which is not a wide mix
#                               but out-of-phase content, and it collapses 6-8 dB
#                               summed to mono. Their source samples are healthy
#                               (-5 to -7.5 dB side/mid), so the width comes from
#                               the render chain. Applied only where measurement
#                               says it is needed.
#   2. true-peak limit          Recovers level without compressing. Pure gain left
#                               the album at -15.4 LUFS because one track peaked
#                               at +0.1 dBFS.
#   3. dither to 16-bit         Triangular with high-pass noise shaping, so
#                               truncation noise is not quantised into the
#                               program material.
#
# What it cannot fix: a source that is a lossy mp3 makes the deliverable a
# second-generation encode. `rerender` to .wav first is the answer to that.
#
# -19.0 is the house target for dilla material, NOT the -14 streaming figure.
# MASTER_LUFS_BY_STYLE records why: pulled down ~3 dB across the board after
# direct feedback that it read as fatiguing even when true peak was safe. -14 is
# the number this project rejected; techno is the one exception.
ALBUM_TARGET_TP = -1.0
ALBUM_XFADE = 1.5
# 0.6 dB of encoder headroom: alimiter works on SAMPLE peak while the delivery
# spec is TRUE peak, and lame reconstructs inter-sample peaks above the sample
# ceiling — limiting at exactly -1.0 produced a -0.7 dBTP file.
ALBUM_ENCODER_HEADROOM = 0.6

# How far under mid the side channel may sit. -7.0 narrowed eight tracks by
# 8.7 dB in one step; the spectrum survived (no band lost more than 1.1 dB) but
# the record lost the analog spread that reads as warmth. Measurement said the
# mono problem was real; it did not say to fix all of it at once.
# SIDE_TARGET=none disables the correction for comparison.
def album_side_target = ENV.fetch("SIDE_TARGET", "-7.0")
def album_target_lufs = ENV.fetch("TARGET_LUFS", "-19.0").to_f

def album_channel_db(path, pan)
  `ffmpeg -hide_banner -nostats -i "#{path}" -af "pan=mono|c0=#{pan},volumedetect" -f null - 2>&1`
    [/mean_volume:\s*(-?[\d.]+)/, 1].to_f
end

def album_loudness(path)
  out = `ffmpeg -hide_banner -nostats -i "#{path}" -af ebur128=peak=true -f null - 2>&1`
  { i: out[/Integrated loudness:\s*\n\s*I:\s*(-?[\d.]+)/m, 1].to_f,
    lra: out[/Loudness range:\s*\n\s*LRA:\s*(-?[\d.]+)/m, 1].to_f,
    tp: out[/True peak:\s*\n\s*Peak:\s*(-?[\d.]+)/m, 1].to_f }
end

def album_side_over_mid(path)
  (album_channel_db(path, "0.5*c0-0.5*c1") - album_channel_db(path, "0.5*c0+0.5*c1")).round(1)
end

def album_tracklist
  path = File.join(ROOT, "data", "album_tracks.yml")
  abort "no album tracklist at #{path}" unless File.file?(path)

  YAML.safe_load_file(path).fetch("tracks").map do |row|
    [File.join(ROOT, row.fetch("path")), row.fetch("title"), row["why"]]
  end
end

# Two passes per track. Guessing a compensation for the side cut was wrong:
# removing ~9 dB of side takes far more than the 0.6 dB first assumed, so those
# tracks landed 3 dB quiet and the limiter rescued them — which is limiting for
# level rather than for peaks. Pass A does the M/S and is measured; pass B sets
# the gain from that measurement so the limiter only ever catches peaks.
def album_stem(src, title, index, out_dir)
  abort "missing: #{src}" unless File.file?(src)

  side_over_mid = album_side_over_mid(src)
  target = album_side_target == "none" ? nil : album_side_target.to_f
  side_cut = target && side_over_mid > target ? (target - side_over_mid).round(2) : 0.0
  dest = File.join(out_dir, format("%02d_%s.wav", index + 1, title.tr(" ()", "_")))
  staged = album_stage_mid_side(src, side_cut, index, out_dir)

  gain = (album_target_lufs - album_loudness(staged)[:i]).round(2)
  chain = "volume=#{gain}dB," \
          "alimiter=limit=#{10**(ALBUM_TARGET_TP / 20.0)}:level=disabled," \
          "aresample=44100:out_sample_fmt=s16:dither_method=triangular_hp"
  `ffmpeg -hide_banner -nostats -y -i "#{staged}" -af "#{chain}" -ac 2 "#{dest}" 2>&1`
  FileUtils.rm_f(staged)

  after = album_loudness(dest)
  puts format("%-24s %7.1f %7.1f -> %7.1f %7.1f %7.2f", title, side_over_mid,
              album_loudness(src)[:i], album_side_over_mid(dest), after[:i], after[:tp])
  dest
end

def album_stage_mid_side(src, side_cut, index, out_dir)
  staged = File.join(out_dir, ".ms_#{index}.wav")
  unless side_cut.negative?
    copy = staged.sub(".wav", File.extname(src))
    FileUtils.cp(src, copy)
    return copy
  end

  graph = "asplit=2[m_a][m_b];" \
          "[m_a]pan=mono|c0=0.5*c0+0.5*c1[mid];" \
          "[m_b]pan=mono|c0=0.5*c0-0.5*c1,volume=#{side_cut}dB[sid];" \
          "[mid][sid]join=inputs=2:channel_layout=stereo[ms];" \
          "[ms]pan=stereo|c0=c0+c1|c1=c0-c1,"
  command = "ffmpeg -hide_banner -nostats -y -i \"#{src}\" " \
            "-filter_complex \"[0:a]#{graph}anull[o]\" -map \"[o]\" -ac 2 -ar 44100 \"#{staged}\" 2>&1"
  `#{command}`
  staged
end

# A trim pass, not a level match: the limiter has already put every track within
# a decibel of target, so this closes the residual gap only.
def album_trim_to_target(stems)
  levels = stems.map { |stem| album_loudness(stem)[:i] }
  puts
  puts "after limiting: #{levels.min.round(1)} to #{levels.max.round(1)} LUFS " \
       "(spread #{(levels.max - levels.min).round(1)} LU)"

  stems.each_with_index.map do |stem, index|
    trim = (album_target_lufs - levels[index]).round(2)
    next stem if trim.abs < 0.1

    dest = stem.sub(".wav", "_lvl.wav")
    command = "ffmpeg -hide_banner -nostats -y -i \"#{stem}\" " \
              "-af \"volume=#{trim}dB,alimiter=limit=#{10**(ALBUM_TARGET_TP / 20.0)}:level=disabled\" " \
              "-ac 2 -ar 44100 \"#{dest}\" 2>&1"
    `#{command}`
    dest
  end
end

# A limiter on the album itself sits at -1.6 rather than the -1.0 target, because
# crossfades overlap two tracks and the sum can exceed what either peaked at.
def album_stitch(stems, dest)
  graph = +""
  previous = "[0:a]"
  stems.each_index do |index|
    next if index.zero?

    label = index == stems.size - 1 ? "[out]" : "[a#{index}]"
    graph << "#{previous}[#{index}:a]acrossfade=d=#{ALBUM_XFADE}:c1=tri:c2=tri#{label};"
    previous = label
  end
  ceiling = 10**((ALBUM_TARGET_TP - ALBUM_ENCODER_HEADROOM) / 20.0)
  graph << "[out]alimiter=limit=#{ceiling}:level=disabled[lim]"

  script = File.join(Dir.tmpdir, "album_graph.txt")
  File.write(script, graph)
  inputs = stems.map { |stem| "-i \"#{stem}\"" }.join(" ")
  system("ffmpeg -hide_banner -loglevel error -y #{inputs} -filter_complex_script #{script} " \
         "-map \"[lim]\" -c:a libmp3lame -q:a 0 \"#{dest}\"")
end

def album_master(dest)
  out_dir = File.join(ROOT, "renders", "mastered")
  FileUtils.rm_rf(out_dir)
  FileUtils.mkdir_p(out_dir)

  puts format("%-24s %7s %7s   %7s %7s %7s", "track", "S/M in", "LUFS in", "S/M out", "LUFS", "peak")
  stems = album_tracklist.each_with_index.map do |(src, title, _why), index|
    album_stem(src, title, index, out_dir)
  end

  album_stitch(album_trim_to_target(stems), dest)

  measured = album_loudness(dest)
  duration = `ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "#{dest}"`.to_f
  puts
  puts "album: #{stems.size} tracks, #{(duration / 60).round(2)} min, #{ALBUM_XFADE}s crossfades"
  puts "  I=#{measured[:i]} LUFS  LRA=#{measured[:lra]}  peak=#{measured[:tp]} dBTP  " \
       "S/M=#{album_side_over_mid(dest)} dB"
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
  sonitex analog-chain genre sidechain-style
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
    USER_PINNED_ENV[env_name] = ENV[env_name]
    # --sonitex writes SONITEX_PRESET; sonitex_enabled? only treats SONITEX
    # as an explicit on. The stream rotator already writes both.
    ENV["SONITEX"] = ENV[env_name] if env_name == "SONITEX_PRESET"
    USER_PINNED_ENV["SONITEX"] = ENV["SONITEX"] if env_name == "SONITEX_PRESET"
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
  "knobs" => -> { knobs_report(ARGV.shift) },
  "assets" => -> { assets_report(ARGV.shift) },
  "tracklist" => -> { tracklist_report(ARGV.shift) },
  "taste" => -> { taste_report(ARGV.dup) },
  "where" => -> { where_report(ARGV.shift) },
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
  # The devices. Each is a small machine with one idea, reachable on its own so
  # it can be auditioned before it is wired into a render -- which is the
  # difference between a device and a feature buried in a renderer.
  "copy-machine" => -> { copy_machine_cli!(ARGV) },
  "hocket" => -> { hocket_cli!(ARGV) },
  "midi-bag" => -> { midi_bag_cli!(ARGV) },
  "wav-map" => -> { wav_map_cli!(ARGV) },
  "arrangement" => -> { arrangement_cli!(ARGV) },
  "macro" => -> { macro_cli!(ARGV) },
  "modulate" => -> { modulate_cli!(ARGV) },
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
  # Replay a render's own sidecar with a fresh seed. KEY=VAL overrides on the
  # command line cover a plain fresh take, a lossless .wav re-render, and a
  # remake from a different sample.
  "rerender" => lambda do
    src = ARGV.shift or abort "usage: ruby dilla.rb rerender <src.mp3|sidecar> <dest> [KEY=VAL...]"
    dest = ARGV.shift or abort "usage: ruby dilla.rb rerender <src.mp3|sidecar> <dest> [KEY=VAL...]"
    rerender_from_sidecar(src, dest, replay_overrides(ARGV))
  end,
  # Audition the sample-to-pad balance by ear rather than by argument.
  "balance" => lambda do
    name = ARGV.shift or abort "usage: ruby dilla.rb balance <#{BALANCE_VARIANTS.keys.join("|")}>"
    render_balance(name)
  end,
  # Every record in the demo crate against three progressions.
  "demo" => -> { generate_demo },
  # Master the tracklist in data/album_tracks.yml into one crossfaded record.
  "album" => -> { album_master(ARGV.shift || File.join(ROOT, "renders", "ALBUM.mp3")) },
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

  apply_best_defaults!
  apply_flags!(ARGV)
  unless ENV["DILLA_RAW"] == "1"
    pad_locked = USER_PINNED_ENV.key?("PAD_VOICE") || USER_PINNED_ENV.key?("PAD_ARP_MODE")
    apply_track_soul_profile!(ENV["TRACK"], force: !pad_locked) if ENV["TRACK"] && !ENV["TRACK"].empty?
  end
  # After the defaults tables have run, because half the environment a render
  # sees comes from them, and before any of it is used. Advisory only: a knob
  # this cannot make sense of is far more often the checker's ignorance than
  # the operator's mistake, and a render must never fail on bookkeeping. It
  # catches the class of mistake that produces a perfect render of the wrong
  # thing -- a typo'd knob, a flag set to a word it does not accept, a value
  # outside a clamp -- none of which anything said a word about before.
  # A named input that is not here stops the render, rather than being
  # substituted for something that is.
  #
  # This is the one check in the engine that refuses instead of warning, and the
  # reason is that the failure it catches is invisible in the output: a missing
  # sample or an absent drum kit produces a finished, good-sounding beat that is
  # not the one the recipe asked for, and nothing downstream can tell. Every
  # other kind of mistake here shows up as a bad render; this one shows up as a
  # different render. DILLA_ASSET_CHECK=0 to proceed anyway.
  if ENV["DILLA_ASSET_CHECK"] != "0"
    missing = DillaAssets.missing_inputs
    unless missing.empty?
      missing.each { |problem| dmesg_error("asset: #{problem}") }
      abort "dilla: #{missing.length} named input(s) missing — fix them, or set DILLA_ASSET_CHECK=0 to " \
            "render with whatever the engine substitutes"
    end
  end

  # After the asset check, so a missing file is reported once by the check that
  # refuses rather than twice by two checks that say the same thing.
  if ENV["DILLA_KNOB_CHECK"] != "0"
    DillaKnobs.validate.each { |problem| dmesg_warn("knob: #{problem}") }
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
