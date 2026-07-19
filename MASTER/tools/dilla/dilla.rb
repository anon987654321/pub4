#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Dilla — unified audio engine
# Synthesis, analog pads, vocal mixes (v7–v11), stem rack, demux, MIDI electronium.
#
# Usage: ruby dilla.rb help

require "fileutils"
require "json"
require "yaml"
require "shellwords"
require_relative "../../lib/io/analog_capabilities"
require "open3"
require "timeout"
require_relative "lib/music_gems"
DillaMusicGems.bootstrap!
require_relative "lib/dilla_dmesg"
require_relative "lib/composition_engine"
require_relative "lib/groove_score"
require_relative "lib/producer_dna"
require_relative "lib/harmony_engine"
require_relative "lib/harmony_lead"
require_relative "lib/groove_engine"
require_relative "lib/seed_providers"
require_relative "lib/rhythm_macros"
require_relative "lib/master_heuristics"
require_relative "lib/spectral_engine"
require_relative "lib/dilla_ml"
require_relative "lib/dfam_engine"
require_relative "lib/automation_lane"

# Terse OpenBSD-style console log (see lib/dilla_dmesg.rb). Prefer dmesg over
# decorative banners; set DILLA_DMESG=0 to silence, =2 for verbose argv.
def dmesg(msg, unit: "dilla0", parent: nil)
  DillaDmesg.ok(msg, unit: unit, parent: parent)
end

def dmesg_warn(msg)
  DillaDmesg.warn(msg)
end

def dmesg_error(msg)
  DillaDmesg.error(msg)
end

ROOT = File.expand_path(__dir__)
# Finished renders default to the invoking directory (override with
# DILLA_OUTPUT_DIR). ROOT stays the base for samples/stems, which aren't
# user output.
OUTPUT_DIR = ENV.fetch("DILLA_OUTPUT_DIR", Dir.pwd)
# Every cache and temp file the engine writes lives here — never loose
# dotfiles in the invoking directory or next to the source. Safe to wipe,
# with one exception: the progressions log (see log_progression!) is the
# only record of generated progressions, which never repeat.
SCRATCH_DIR = ENV.fetch("DILLA_SCRATCH_DIR", File.join(ROOT, ".cache"))

def scratch_path(name)
  FileUtils.mkdir_p(SCRATCH_DIR)
  File.join(SCRATCH_DIR, name)
end
SAMPLE_DIR = File.join(ROOT, "samples")
DRUM_DIR = File.join(SAMPLE_DIR, "drums")
CUSTOM_DRUM_DIR = File.join(DRUM_DIR, "custom")
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

# YouTube/local ingest → demucs → rhythm/harmony analysis → engine hints (inlined).
module DillaSourceLearn
  LEARNINGS_DIR = File.expand_path("project/learnings", ROOT).freeze
  LAST_REPORT_PATH = File.join(LEARNINGS_DIR, "last_learn.json").freeze
  PLAYLIST_CATALOG_PATH = File.join(LEARNINGS_DIR, "playlist_catalog.json").freeze
  PLAYLIST_BATCH_STATE_PATH = File.join(LEARNINGS_DIR, "playlist_batch_state.json").freeze
  PLAYLIST_TRACKS_DIR = File.join(LEARNINGS_DIR, "tracks").freeze
  LEARNED_ENGINE_PATH = File.join(LEARNINGS_DIR, "learned_engine.json").freeze
  DOSSIER_DIFF_PATH = File.join(LEARNINGS_DIR, "dossier_diff.json").freeze
  PLAYLIST_BATCH_LOG = File.join(LEARNINGS_DIR, "playlist_batch.log").freeze

  HARMONY_STEMS = %w[piano.wav other.wav guitar.wav].freeze
  VOICING_ROTATION = %i[spread drop2 rootless kenny_barron bill_evans quartal].freeze
  SONITEX_ROTATION = %i[donuts_warm cassette sp1200 subtle scuzz].freeze

  module_function

  def ensure_dir!
    FileUtils.mkdir_p(LEARNINGS_DIR)
  end

  def compose_report(source:, stem_dir:, stem_analysis:, full_analysis: nil)
    harmonic = stem_analysis.values_at(*HARMONY_STEMS).compact
    chords = harmonic.flat_map { |s| s[:top_chords] || [] }
    coltrane = harmonic.filter_map { |s| s[:coltrane_candidates] }.flatten(1)
    merged_pcs = harmonic.flat_map { |s| s[:pitch_classes] || [] }.tally.sort_by { |_, c| -c }.map(&:first)
    progression_symbols = (chords + coltrane).map { |c| c[:name] || c["name"] }.compact.uniq.first(8)
    progression_insight = nil
    if defined?(DillaHarmony) && progression_symbols.length >= 2
      progression_insight = DillaHarmony.progression_insight(progression_symbols.map { |n| { name: n } })
    end
    bpm_est = stem_analysis["drums.wav"]&.fetch(:bpm_estimate, nil) ||
              full_analysis&.dig(:bpm_estimate) ||
              stem_analysis.values.map { |s| s[:bpm_estimate] }.compact.first
    semantics = full_analysis&.dig(:semantics) || stem_analysis["other.wav"]&.fetch(:semantics, nil)
    {
      source: source, stem_dir: stem_dir, analyzed_at: Time.now.utc.iso8601,
      bpm_estimate: bpm_est, progression_symbols: progression_symbols,
      progression_insight: progression_insight, pitch_classes: merged_pcs.first(12),
      stems: stem_analysis, semantics: semantics,
      engine_hints: suggest_engine_patch(progression_symbols: progression_symbols,
                                       progression_insight: progression_insight, bpm: bpm_est, semantics: semantics),
      drum_pattern: stem_analysis["drums.wav"]&.slice(:step_grid, :bpm_estimate, :swing_hint, :drum_density),
      melody_hints: harmonic.map { |s| s.slice(:pitch_classes, :top_chords) }.reject(&:empty?),
      copyable_dna: nil
    }.tap { |rep| rep[:copyable_dna] = copyable_dna(rep) }
  rescue StandardError => e
    warn "learn report: #{e.message}" if ENV["DILLA_DEBUG"]
    { source: source, stem_dir: stem_dir, analyzed_at: Time.now.utc.iso8601, error: e.message,
      engine_hints: suggest_engine_patch(progression_symbols: [], progression_insight: nil, bpm: nil, semantics: nil) }
  end

  def suggest_engine_patch(progression_symbols:, progression_insight:, bpm:, semantics:)
    track = map_progression_to_track(progression_symbols, progression_insight)
    voicing = VOICING_ROTATION[(progression_symbols.join.hash.abs) % VOICING_ROTATION.length]
    sonitex = semantics&.include?("vinyl") || semantics&.include?("dusty") ? :donuts_warm : :cassette
    sonitex = SONITEX_ROTATION[(bpm.to_f.round * 3).to_i % SONITEX_ROTATION.length] if bpm
    analog = semantics&.include?("warm") ? :acetate : :vinyl_hot
    { track: track, voicing: voicing, sonitex_preset: sonitex, analog_chain: analog, bpm: bpm&.round,
      groove_dna: bpm && bpm < 88 ? "endtroducing" : "donuts", performer: "yancey",
      notes: [progression_insight ? "coltrane=#{progression_insight[:notation]} in #{progression_insight[:scale]}" : nil,
              progression_symbols.any? ? "chords=#{progression_symbols.first(4).join('-')}" : nil].compact }
  end

  def map_progression_to_track(symbols, _insight)
    joined = symbols.map { |s| s.to_s.downcase }.join(" ")
    return :maj7_minor_cycle if joined.include?("db") && joined.include?("fm") && joined.include?("bbm")
    return :neo_soul_pocket if joined.include?("dm") && joined.include?("eb") && joined.include?("gm")
    return :minor_iv_loop if joined.include?("bbm") && joined.include?("fm")
    return :fourth_third_sixth_second_turn if symbols.length >= 6
    return :timeless_authentic if joined.include?("fm") && symbols.length >= 5
    :maj7_minor_cycle
  end

  def save_report!(report, path: LAST_REPORT_PATH)
    ensure_dir!
    File.write(path, JSON.pretty_generate(report) + "\n")
    archive = File.join(LEARNINGS_DIR, "learn_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json")
    File.write(archive, JSON.pretty_generate(report) + "\n")
    { last: path, archive: archive }
  end

  def load_last_report(path: LAST_REPORT_PATH)
    return nil unless File.file?(path)
    JSON.parse(File.read(path), symbolize_names: true)
  rescue StandardError
    nil
  end

  def copyable_dna(report)
    drums = report[:drum_pattern] || {}
    grid = drums[:step_grid] || {}
    symbols = Array(report[:progression_symbols])
    insight = report[:progression_insight]
    hints = report[:engine_hints] || {}
    {
      drums: grid.any? ? {
        bpm: drums[:bpm_estimate] || hints[:bpm], swing: drums[:swing_hint],
        kicks: grid[:kicks], snares: grid[:snares], hats: grid[:hats], density: drums[:drum_density]
      }.compact : nil,
      harmony: { progression: symbols, notation: insight&.dig(:notation), scale: insight&.dig(:scale) }.compact,
      melody: Array(report[:pitch_classes]).first(8),
      engine: hints.slice(:track, :voicing, :sonitex_preset, :analog_chain, :groove_dna, :performer, :bpm)
    }
  end

  def load_playlist_catalog(path: PLAYLIST_CATALOG_PATH)
    return { "tracks" => [], "updated_at" => nil } unless File.file?(path)
    JSON.parse(File.read(path))
  rescue StandardError
    { "tracks" => [], "updated_at" => nil }
  end

  def save_playlist_entry!(entry, catalog_path: PLAYLIST_CATALOG_PATH)
    ensure_dir!
    FileUtils.mkdir_p(PLAYLIST_TRACKS_DIR)
    slug = entry[:id] || entry["id"] || "track_#{Time.now.to_i}"
    track_path = File.join(PLAYLIST_TRACKS_DIR, "#{slug}.json")
    File.write(track_path, JSON.pretty_generate(entry) + "\n")
    catalog = load_playlist_catalog(path: catalog_path)
    tracks = Array(catalog["tracks"]).reject { |t| t["id"] == slug.to_s }
    tracks << entry.transform_keys(&:to_s)
    catalog["tracks"] = tracks.sort_by { |t| [t["artist"].to_s, t["title"].to_s] }
    catalog["updated_at"] = Time.now.utc.iso8601
    catalog["track_count"] = tracks.length
    File.write(catalog_path, JSON.pretty_generate(catalog) + "\n")
    { track: track_path, catalog: catalog_path }
  end

  def load_batch_state(path: PLAYLIST_BATCH_STATE_PATH)
    return { "completed_ids" => [], "failed" => {} } unless File.file?(path)
    JSON.parse(File.read(path))
  rescue StandardError
    { "completed_ids" => [], "failed" => {} }
  end

  def save_batch_state!(state, path: PLAYLIST_BATCH_STATE_PATH)
    ensure_dir!
    File.write(path, JSON.pretty_generate(state) + "\n")
  end

  def apply_hints_to_env!(hints)
    return [] unless hints.is_a?(Hash)
    applied = []
    { track: "TRACK", voicing: "VOICING", sonitex_preset: "SONITEX_PRESET",
      analog_chain: "ANALOG_CHAIN", bpm: "BPM", groove_dna: "GROOVE_DNA", performer: "PERFORMER" }.each do |k, env|
      val = hints[k] || hints[k.to_s]
      next if val.nil? || val.to_s.empty?
      ENV[env] = val.to_s
      applied << "#{env}=#{val}"
    end
    applied
  end
end

# =============================================================================
# ENHANCEMENT LAYER — sonic profiles, extended harmony, eclectic drums,
# FlyLo sidechain, fugue structure, per-style mastering. (Merged in from the
# former dilla_enhancements.rb — kept as one file per project convention.)
# =============================================================================

# Measured reference sonic profiles (Radio Bergen clips) — inlined so dilla.rb
# has no runtime dependency on radio_bergen_sonic.yml or other sidecar files.
INLINE_SONIC_PROFILES = {
  dilla_timeless: {
    "harmonic" => {
      "engine_progression" => "maj7_minor_cycle",
      "engine_chords" => %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Bbm9 Ebmaj9],
      "melody_chop_hz" => [659.25, 587.33, 523.25, 440.0, 392.00, 349.23]
    },
    "synth" => {
      "bpm" => 86, "swing" => 0.16, "pad_lowpass_hz" => 3400, "master_lowpass_hz" => 2800,
      "bass_sustain_bar" => 0.94, "bass_shelf_db" => 9, "vinyl_noise" => 0.06,
      "texture" => "donuts_lowpass_warmth"
    }
  },
  flylo_camel: {
    "harmonic" => {
      "engine_progression" => "chromatic_mediant_drift",
      "engine_chords" => %w[Dm9 Cm11nc AbMaj13s11 Gm7 Eb7 A7nc Dmaj9nc DMaj7overG]
    },
    "synth" => {
      "bpm" => 84, "swing" => 0.12, "pad_lowpass_hz" => 3600, "master_lowpass_hz" => 3600,
      "bass_sustain_bar" => 0.88, "bass_shelf_db" => 6, "vinyl_noise" => 0.08,
      "sidechain_pump" => true, "texture" => "jazz_haze_sidechain"
    }
  },
  madlib_eye: {
    "harmonic" => {
      "engine_chords" => %w[Ebmaj7 Ebm7 Cm7 Eb7],
      "melody_chop_hz" => [659.25, 587.33, 523.25, 440.0, 392.00, 349.23]
    },
    "synth" => {
      "bpm" => 96, "swing" => 0.20, "pad_lowpass_hz" => 3200, "master_lowpass_hz" => 3200,
      "bass_sustain_bar" => 0.80, "bass_shelf_db" => 7, "vinyl_noise" => 0.10,
      "crush_mix" => 0.35, "texture" => "sp303_vinyl_grit"
    }
  },
  slum_players: {
    "harmonic" => {
      "engine_progression" => "players_measured",
      "engine_chords" => %w[Dm7 Eb7 Gm7 D7 Eb7 Gm7 Am7]
    },
    "synth" => {
      "bpm" => 93, "swing" => 0.18, "pad_lowpass_hz" => 3300, "master_lowpass_hz" => 3000,
      "bass_sustain_bar" => 0.92, "bass_shelf_db" => 8, "vinyl_noise" => 0.07,
      "texture" => "neo_soul_pocket"
    }
  },
  samiyam_rounded: {
    "harmonic" => {
      "engine_chords" => %w[Dm9 Em7 Ebmaj7 Dm]
    },
    "synth" => {
      "bpm" => 96, "swing" => 0.14, "pad_lowpass_hz" => 3000, "master_lowpass_hz" => 2800,
      "bass_sustain_bar" => 0.85, "bass_shelf_db" => 10, "vinyl_noise" => 0.05,
      "texture" => "modern_dry_punch"
    }
  },
  bergen_akmd_local: {
    "harmonic" => { "engine_progression" => "erykah_minor", "texture" => "bergen_night_rain" },
    "synth" => {
      "bpm" => 87, "swing" => 0.17, "pad_lowpass_hz" => 3100, "master_lowpass_hz" => 2700,
      "bass_shelf_db" => 9, "vinyl_noise" => 0.08, "texture" => "akmd_lofi_mastering"
    }
  },
  chase_swayze_traffic: {
    "harmonic" => { "engine_progression" => "minor_turnaround" },
    "synth" => { "bpm" => 88, "swing" => 0.16, "pad_lowpass_hz" => 3300, "vinyl_noise" => 0.07 }
  }
}.freeze

# playlist.brgen.no study output — inlined so stream mode works without sidecar YAML.
INLINE_RADIO_BERGEN_LEARNINGS = {
  "stream_rotation_weights" => {
    "maj7_minor_cycle" => 14, "neo_soul" => 10, "neo_soul_pocket" => 9, "electronium_loop" => 8,
    "minor_iv_loop" => 7, "players_measured" => 6, "aydin_modal_quartal" => 6, "aydin_jazz_turn" => 5,
    "bach_circle_descent" => 5, "bach_descending_bass" => 5, "warm_minor_arc" => 4,
    "slash_neo_soul" => 4, "erykah_minor" => 3, "timeless_authentic" => 3,
    "fourth_third_sixth_second_turn" => 2, "quartal_west_coast" => 2
  },
  "stream_env_defaults" => {
    "PERFORMER" => "yancey", "GROOVE_DNA" => "donuts", "SONITEX_PRESET" => "donuts_warm",
    "KICKS" => "1", "SPEAK" => "0" # speech overlay off for now — set SPEAK=1 to re-enable
  },
  "sonic_profiles" => {
    "bergen_akmd_local" => INLINE_SONIC_PROFILES[:bergen_akmd_local],
    "chase_swayze_traffic" => INLINE_SONIC_PROFILES[:chase_swayze_traffic]
  }
}.freeze

TRACK_SONIC_MAP = {
  timeless: :dilla_timeless,
  maj7_minor_cycle: :dilla_timeless,
  fourth_third_sixth_second_turn: :dilla_timeless,
  timeless_authentic: :dilla_timeless,
  time_donut: :dilla_timeless,
  chromatic_minor_descent: :dilla_timeless,
  neo_soul: :dilla_timeless,
  neo_soul_pocket: :slum_players,
  aydin_modal_quartal: :dilla_timeless,
  aydin_jazz_turn: :dilla_timeless,
  bach_circle_descent: :dilla_timeless,
  bach_descending_bass: :dilla_timeless,
  electronium_loop: :dilla_timeless,
  electronium_classic: :dilla_timeless,
  minor_soul_loop: :dilla_timeless,
  voice_led_minor_arc: :dilla_timeless,
  borrowed_dominant_turn: :dilla_timeless,
  soul: :dilla_timeless,
  chromatic_mediant: :flylo_camel,
  chromatic_mediant_drift: :flylo_camel,
  sus_add9_ballad: :madlib_eye,
  generated_mediant: :flylo_camel,
  generated_planing: :dilla_timeless,
  generated: :dilla_timeless,
  players: :slum_players,
  alternating_minor7_pair: :slum_players,
  major7_relative_minor_turn: :slum_players
}.freeze

# Researched progressions — loop cleanly; skip fugue development + heavy pedal/bitonal.
CURATED_PROGRESSIONS = %i[
  maj7_minor_cycle time_donut fall_in_love minor_iv_loop
  timeless_authentic players_measured fourth_third_sixth_second_turn
  voice_led_minor_arc neo_soul neo_soul_pocket soul minor_soul_loop borrowed_dominant_turn
  chromatic_minor_descent electronium_loop electronium_classic
  syncopated_slash_ninth syncopated_slash_alt sus_add9_ballad
  chromatic_mediant_drift major7_relative_minor_turn alternating_minor7_pair
  minor_dominant_slash_cycle minor_major_ninth_pair minor_ninth_cycle
  jazz baroque suspended_minor_close minor_cycle_descent
  aydin_modal_quartal aydin_jazz_turn bach_circle_descent bach_descending_bass
].freeze

FLYLO_TRACKS = %i[
  chromatic_mediant chromatic_mediant_drift sus_add9_ballad
  generated_mediant generated_polytonal generated_neapolitan
].freeze

DILLA_TRACKS = %i[
  timeless chromatic_minor_descent neo_soul syncopated_slash_ninth
  chromatic_planing minor_soul_loop generated_planing generated generated_negative
].freeze

# Pulled down ~3dB across the board + widened LRA — "way too loud" direct
# feedback. loudnorm's integrated-loudness target was landing every track
# at near-broadcast loudness with a tight LRA, which reads as fatiguing
# even when true-peak is technically safe.
MASTER_LUFS_BY_STYLE = {
  dilla: -19.0,
  flylo: -17.0,
  madlib: -18.0,
  neo_soul: -18.5,
  default: -17.0
}.freeze

LRA_BY_STYLE = {
  dilla: 13.0,
  flylo: 14.0,
  madlib: 13.0,
  neo_soul: 12.0,
  default: 11.0
}.freeze

CHORD_TEMPLATES_EXT = {
  "maj" => [0, 4, 7],
  "min" => [0, 3, 7],
  "7" => [0, 4, 7, 10],
  "maj7" => [0, 4, 7, 11],
  "m7" => [0, 3, 7, 10],
  "m9" => [0, 3, 7, 10, 2],
  "maj9" => [0, 4, 7, 11, 2],
  "sus" => [0, 5, 7],
  "dim" => [0, 3, 6],
  "7alt" => [0, 4, 7, 10, 1],
  "7#11" => [0, 4, 7, 10, 6],
  "m11" => [0, 3, 7, 10, 5],
  "sus4" => [0, 5, 7, 10],
  "aug" => [0, 4, 8],
  "6" => [0, 4, 7, 9]
}.freeze

VOICING_STYLES = %i[close spread drop2 drop3 quartal cluster].freeze

# Arpeggiator pattern library — each returns degree indices for a chord tone count.
ARP_PATTERN_BUILDERS = {
  up:           ->(n) { (0...n).to_a },
  down:         ->(n) { (0...n).to_a.reverse },
  updown:       ->(n) { seq = (0...n).to_a; seq + seq[1...-1].reverse },
  downup:       ->(n) { seq = (0...n).to_a.reverse; seq + seq[1...-1].reverse },
  skip_up:      ->(n) { (0...n).step(2).to_a + (1...n).step(2).to_a },
  fibonacci:    ->(n) { fib = [0, 1]; fib << fib[-1] + fib[-2] while fib.length < n; fib.first(n).map { |i| i % n } },
  pingpong:     ->(n) { (0...n * 2).map { |i| i < n ? i : (n * 2 - 1 - i) } },
  spiral:       ->(n) { (0...n).flat_map { |i| [i, (i + 2) % n] }.first(n * 2) },
  quint_spread: ->(n) { [0, 2, 4, 1, 3].first(n) },
  random_walk:  ->(n, rng = Random.new(42)) { cur = 0; Array.new(n * 2) { cur = (cur + rng.rand(-1..1)).clamp(0, n - 1) } },
  euclidean:    ->(n) { hits = 5; steps = n * 2; (0...steps).map { |i| ((i * hits) % steps) < hits ? i % n : nil }.compact },
  coltrane:     ->(n) { [0, 2, 1, 3, 2, 0, 1].first(n * 2) },
  donda_stab:   ->(n) { [0, 0, 2, 1].cycle.first(n * 2) },
  flylo_wobble: ->(n) { (0...n).flat_map { |i| [i, i, (i + 1) % n] }.first(n * 3) },
  stutter:      ->(n, rng = Random.new(17)) { (0...[n * 4, 24].max).filter_map { |i| i.even? ? (i / 2) % n : (rng.rand < 0.35 ? (i / 3) % n : nil) } },
  burst:        ->(n) { [0, 0, 1, 2, 1, 0, 3, 2].cycle.first([n * 3, 18].max) },
  ratchet:      ->(n, rng = Random.new(23)) { base = rng.rand(0...n); (0...[n * 3, 20].max).map { |i| (base + i) % n } }
}.freeze

# Rich synth patch catalog — GM programs, optional external sf2, native fallback timbres,
# and per-patch post-FX chains (tremolo/LFO/filter/delay) applied at render time.
def synth_patch(id, role:, program:, bank: 0, sf2: :default, weight: 1.0, native: nil, mix: 1.0, fx: nil,
                arp_styles: nil, octave: 2, gate: 0.82, color: nil, fs_gain: 1.5, midi_fx: nil, midi_arp: nil)
  { id: id, role: role, program: program, bank: bank, sf2: sf2, weight: weight, native: native,
    mix: mix, fx: fx, arp_styles: arp_styles || [:up, :updown], octave: octave, gate: gate, color: color,
    fs_gain: fs_gain, midi_fx: midi_fx, midi_arp: midi_arp }
end

# MIDI CC automation baked into SMF before FluidSynth — mod wheel, expression,
# filter, chorus, pan, and pitch-bend LFO (hardware-synth style movement).
# Held chord pads — gentle movement only; aggressive filter sweeps read as
# "horrible" on Rhodes/Moog/Prophet voicings (arp belongs on the lead layer).
MIDI_FX_PAD_EP = [
  { cc: 1, rate_hz: 0.14, depth: 10, base: 22, curve: :sine },
  { cc: 11, curve: :swell, depth: 22, base: 78 },
  { cc: 74, curve: :slow_open, start: 98, end: 108 }
].freeze
MIDI_FX_PAD_WARM = [
  { cc: 1, rate_hz: 0.1, depth: 14, base: 24, curve: :sine },
  { cc: 91, rate_hz: 0.08, depth: 12, base: 44, curve: :sine }
].freeze
# Lead MIDI automation — mod, portamento, pan, filter, chorus, reverb, pitch LFO.
MIDI_FX_LEAD = [
  { cc: 1, rate_hz: 0.48, depth: 48, base: 32, curve: :sine },      # mod wheel
  { cc: 5, rate_hz: 0.22, depth: 28, base: 52, curve: :sine },      # portamento time
  { cc: 10, rate_hz: 0.16, depth: 22, base: 64, curve: :sine },     # pan
  { cc: 11, rate_hz: 0.12, depth: 18, base: 88, curve: :swell },    # expression
  { cc: 71, rate_hz: 0.2, depth: 24, base: 62, curve: :sine },      # resonance
  { cc: 74, curve: :slow_open, start: 68, end: 118 },                 # filter cutoff
  { cc: 91, rate_hz: 0.09, depth: 20, base: 48, curve: :sine },     # reverb send
  { cc: 93, rate_hz: 0.14, depth: 18, base: 40, curve: :sine },     # chorus send
  { bend: true, rate_hz: 0.38, depth_cents: 18 }                     # pitch LFO
].freeze
MIDI_FX_SCALE_LEAD = [
  { cc: 1, rate_hz: 0.55, depth: 42, base: 36, curve: :sine },
  { cc: 5, rate_hz: 0.2, depth: 20, base: 50, curve: :sine },
  { cc: 10, rate_hz: 0.2, depth: 16, base: 64, curve: :sine },
  { cc: 74, curve: :slow_open, start: 70, end: 120 },
  { cc: 91, rate_hz: 0.1, depth: 16, base: 42, curve: :sine },
  { bend: true, rate_hz: 0.45, depth_cents: 14 }
].freeze
# Extra motion when STREAM_LEAD_MIDI_RICH=1 (default on stream).
MIDI_FX_LEAD_RICH = (
  MIDI_FX_LEAD + [
    { cc: 1, rate_hz: 0.9, depth: 22, base: 40, curve: :sine },
    { cc: 74, rate_hz: 0.35, depth: 30, base: 80, curve: :sine },
    { bend: true, rate_hz: 0.65, depth_cents: 24 }
  ]
).freeze

SYNTH_PATCH_CATALOG = [
  # --- Electric keys (EP / Rhodes family) ---
  synth_patch(:rhodes_mark1, role: :ep, program: 4, weight: 3.2, mix: 1.22, fs_gain: 1.72,
              color: "Mark I warm tine",
              midi_fx: MIDI_FX_PAD_EP,
              arp_styles: %i[skip_up euclidean quint_spread],
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.78, vel: 0.16 },
              fx: "tremolo=f=0.28:d=0.04,aecho=0.38:0.48:55|110:0.22|0.12,chorus=0.32:0.52:28|38:0.14|0.1:0.18|0.14:0.9|1.15,lowpass=f=5000,equalizer=f=280:t=o:w=1:g=1.8"),
  synth_patch(:rhodes_stage73, role: :ep, program: 4, weight: 2.8, mix: 1.1, fs_gain: 1.7,
              color: "stage Rhodes bark",
              fx: "chorus=0.42:0.62:28|38:0.18|0.14:0.22|0.18:0.95|1.25,aecho=0.32:0.4:70|130:0.2|0.1,equalizer=f=3200:t=h:w=1800:g=1.2"),
  synth_patch(:rhodes_tine_wurli, role: :ep, program: 2, weight: 2.2, mix: 1.05, fs_gain: 1.55,
              color: "Wurli bite + tine",
              fx: "equalizer=f=900:t=o:w=0.9:g=2.8,acrusher=bits=12:samples=1.2:mix=0.08,lowpass=f=5200"),
  synth_patch(:rhodes_dx_blend, role: :ep, program: 5, weight: 1.8, mix: 1.0, fs_gain: 1.5,
              color: "DX glass + Rhodes body",
              fx: "aecho=0.45:0.5:80|150:0.28|0.14,aphaser=speed=0.1:decay=0.55,equalizer=f=2400:t=h:w=1200:g=1.8"),
  synth_patch(:rhodes_bleeding_edge, role: :ep, program: 4, weight: 1.6, mix: 1.2, fs_gain: 1.75,
              color: "convolution-warm EP",
              fx: "aecho=0.55:0.65:110|220:0.35|0.18,chorus=0.5:0.7:35|45:0.22|0.18:0.28|0.22:1.1|1.45,vibrato=f=0.22:d=0.01,lowpass=f=4800"),
  synth_patch(:rhodes_bright, role: :ep, program: 0, weight: 1.2, color: "acoustic piano edge",
              fx: "highpass=f=120,equalizer=f=3500:t=h:w=2000:g=1.4"),
  synth_patch(:wurli_bite, role: :ep, program: 2, color: "electric grand",
              fx: "equalizer=f=1100:t=o:w=0.8:g=3.0,acrusher=bits=11:samples=1.4:mix=0.1"),
  synth_patch(:dx_ep_glass, role: :ep, program: 5, color: "FM bell EP",
              fx: "aecho=0.4:0.5:90|170:0.3|0.16,aphaser=speed=0.1:decay=0.6"),
  synth_patch(:clav_funk, role: :ep, program: 7, color: "clavinet"),
  synth_patch(:harpsi_pluck, role: :ep, program: 6, color: "harpsichord"),
  synth_patch(:vibes_mallet, role: :ep, program: 11, color: "vibraphone"),
  synth_patch(:marimba_chop, role: :ep, program: 12, color: "marimba"),
  synth_patch(:galaxy_ep1, role: :ep, program: 4, bank: 2, sf2: :galaxy, weight: 2.4, mix: 1.12, fs_gain: 1.6,
              color: "Galaxy EP",
              fx: "tremolo=f=0.35:d=0.08,aecho=0.4:0.5:60|120:0.25|0.12,lowpass=f=4500"),
  synth_patch(:galaxy_ep2, role: :ep, program: 5, bank: 3, sf2: :galaxy, weight: 2.0, mix: 1.08, fs_gain: 1.55,
              color: "Galaxy EP bright",
              fx: "equalizer=f=1800:t=h:w=1400:g=2.2,aecho=0.35:0.45:80|150:0.22|0.1"),
  synth_patch(:galaxy_ep_bleeding, role: :ep, program: 4, bank: 4, sf2: :galaxy, weight: 1.5, mix: 1.15,
              color: "Galaxy EP + chorus halo",
              fx: "chorus=0.55:0.75:40|50:0.28|0.22:0.3|0.25:1.15|1.55,aphaser=speed=0.12:decay=0.5"),
  synth_patch(:organ_drawbar, role: :ep, program: 16, weight: 1.8, mix: 1.05, fs_gain: 1.52,
              color: "drawbar soul", midi_fx: MIDI_FX_PAD_EP,
              fx: "chorus=0.32:0.48:28|36:0.14|0.1:0.18|0.14:0.9|1.1,lowpass=f=4600"),
  synth_patch(:organ_perc, role: :ep, program: 17, weight: 1.4, mix: 1.0, fs_gain: 1.48,
              color: "perc organ", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.42:d=0.08,lowpass=f=4200"),
  synth_patch(:rhodes_vintage_tape, role: :ep, program: 4, weight: 2.6, mix: 1.12, fs_gain: 1.62,
              color: "Rhodes + tape wobble", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.22:d=0.04,vibrato=f=0.12:d=0.008,lowpass=f=4400"),
  synth_patch(:rhodes_cafe_warm, role: :ep, program: 4, weight: 2.4, mix: 1.08, fs_gain: 1.58,
              color: "Rhodes cafe warmth", midi_fx: MIDI_FX_PAD_EP,
              fx: "aecho=0.38:0.42:70|130:0.22|0.1,lowpass=f=4800"),
  synth_patch(:wurli_soul_bite, role: :ep, program: 2, weight: 2.3, mix: 1.1, fs_gain: 1.56,
              color: "Wurli soul bite", midi_fx: MIDI_FX_PAD_EP,
              fx: "tremolo=f=0.35:d=0.06,aecho=0.32:0.38:50|90:0.18|0.08,lowpass=f=5200"),
  synth_patch(:clav_neo_funk, role: :ep, program: 7, weight: 2.0, mix: 1.02, fs_gain: 1.5,
              color: "neo-soul clav", midi_fx: MIDI_FX_PAD_EP,
              fx: "highpass=f=180,lowpass=f=4500,tremolo=f=0.48:d=0.05"),
  synth_patch(:dx7_bell_ep, role: :ep, program: 5, weight: 1.9, mix: 1.0, fs_gain: 1.48,
              color: "DX bell EP", midi_fx: MIDI_FX_PAD_EP,
              fx: "aecho=0.45:0.5:90|160:0.28|0.14,lowpass=f=5600"),
  synth_patch(:soul_piano_tack, role: :ep, program: 0, weight: 1.5, mix: 0.95, fs_gain: 1.42,
              color: "tacked upright soul", midi_fx: MIDI_FX_PAD_EP,
              fx: "lowpass=f=3800,acompressor=threshold=-26dB:ratio=2:attack=18:release=120"),
  synth_patch(:celeste_dust, role: :ep, program: 8, weight: 1.3, mix: 0.88, fs_gain: 1.38,
              color: "celeste dust", midi_fx: MIDI_FX_PAD_EP,
              fx: "aecho=0.5:0.55:120|220:0.24|0.12,lowpass=f=5000"),
  synth_patch(:ep_mark1_dark, role: :ep, program: 1, weight: 1.6, mix: 1.0, fs_gain: 1.45,
              color: "dark EP mark", midi_fx: MIDI_FX_PAD_EP,
              fx: "lowpass=f=3200,tremolo=f=0.18:d=0.03"),
  # --- Warm analog pads (Moog / Prophet / Juno) ---
  synth_patch(:moog_model_d, role: :warm, program: 91, weight: 3.0, mix: 0.78, fs_gain: 1.48,
              color: "Minimoog ladder pad",
              midi_fx: MIDI_FX_PAD_WARM,
              arp_styles: %i[up downup quint_spread],
              midi_arp: { style: :up, subdiv: 4, gate: 0.88, vel: 0.26 },
              fx: "lowpass=f=3000:width_type=q:width=0.75,tremolo=f=0.18:d=0.06,chorus=0.38:0.58:32|42:0.14|0.1:0.18|0.14:0.92|1.15,aecho=0.28:0.36:80|150:0.18|0.08,equalizer=f=180:t=o:w=1:g=1.6"),
  synth_patch(:moog_sub37_pad, role: :warm, program: 38, weight: 2.4, mix: 0.78, fs_gain: 1.4,
              color: "Moog sub harmonic pad",
              fx: "lowpass=f=2200,equalizer=f=95:t=o:w=0.8:g=3.5,aphaser=speed=0.1:decay=0.55"),
  synth_patch(:moog_bleeding_edge, role: :warm, program: 91, weight: 1.8, mix: 0.85, fs_gain: 1.5,
              color: "Moog + tape drift",
              fx: "vibrato=f=0.18:d=0.014,tremolo=f=0.55:d=0.12,aecho=0.42:0.52:100|190:0.28|0.14,lowpass=f=3000"),
  synth_patch(:prophet_5_pad, role: :warm, program: 89, weight: 3.2, mix: 0.78, fs_gain: 1.52,
              color: "Prophet-5 poly",
              midi_fx: MIDI_FX_PAD_WARM,
              arp_styles: %i[updown pingpong coltrane],
              midi_arp: { style: :updown, subdiv: 4, gate: 0.86, vel: 0.24 },
              fx: "chorus=0.48:0.68:34|44:0.2|0.16:0.24|0.2:1.05|1.3,vibrato=f=0.18:d=0.01,aecho=0.32:0.4:90|170:0.2|0.1,lowpass=f=4200"),
  synth_patch(:prophet_6_warm, role: :warm, program: 90, weight: 2.5, mix: 0.76, fs_gain: 1.45,
              color: "Prophet-6 stereo wash",
              fx: "chorus=0.52:0.72:38|48:0.24|0.2:0.28|0.24:1.1|1.4,aecho=0.35:0.45:90|170:0.25|0.12"),
  synth_patch(:prophet_rev2_bleeding, role: :warm, program: 87, weight: 1.7, mix: 0.74, fs_gain: 1.48,
              color: "Rev2 hybrid supersaw bed",
              fx: "chorus=0.55:0.75:42|52:0.28|0.22:0.3|0.25:1.2|1.5,aphaser=speed=0.14:decay=0.48,lowpass=f=4000"),
  synth_patch(:juno_strings, role: :warm, program: 50, weight: 2.2, mix: 0.72,
              fx: "chorus=0.55:0.75:40|55:0.3|0.25:0.35|0.3:1.1|1.5"),
  synth_patch(:solina_ensemble, role: :warm, program: 51, fx: "aphaser=speed=0.12:decay=0.5"),
  synth_patch(:prophet_pad, role: :warm, program: 89, weight: 2.0, mix: 0.78,
              fx: "vibrato=f=0.32:d=0.018,chorus=0.4:0.6:30|40:0.18|0.14:0.22|0.18:0.95|1.2"),
  synth_patch(:oberheim_pad, role: :warm, program: 90, fx: "tremolo=f=4.2:d=0.14"),
  synth_patch(:moog_pad, role: :warm, program: 91, weight: 2.2, mix: 0.8,
              fx: "lowpass=f=2600:width_type=q:width=0.75,tremolo=f=0.35:d=0.1,equalizer=f=160:t=o:w=1:g=2.0"),
  synth_patch(:cs80_ensemble, role: :warm, program: 92, fx: "aecho=0.35:0.45:120|200:0.28|0.14"),
  synth_patch(:pwm_sweep_pad, role: :warm, program: 93, fx: "tremolo=f=0.55:d=0.22,aphaser=speed=0.14:decay=0.55"),
  synth_patch(:choir_aahs, role: :warm, program: 52, fx: "aecho=0.45:0.55:80|140:0.28|0.14,lowpass=f=4200"),
  synth_patch(:voice_oohs, role: :warm, program: 53, fx: "vibrato=f=0.45:d=0.012"),
  synth_patch(:analog_pad1, role: :warm, program: 88),
  synth_patch(:analog_pad2, role: :warm, program: 94),
  synth_patch(:analog_pad3, role: :warm, program: 95),
  synth_patch(:string_orchestra, role: :warm, program: 48, fx: "lowpass=f=4200"),
  synth_patch(:slow_attack_pad, role: :warm, program: 49, fx: "acompressor=threshold=-24dB:ratio=1.8:attack=80:release=220"),
  synth_patch(:fm_bell_pad, role: :warm, program: 14, fx: "aecho=0.4:0.5:90|160:0.32|0.18"),
  synth_patch(:bowed_glass, role: :warm, program: 13, fx: "aphaser=speed=0.12:decay=0.7"),
  synth_patch(:memorymoon_pad, role: :warm, program: 88, weight: 2.1, mix: 0.74, fs_gain: 1.4,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.42:0.62:34|44:0.18|0.14:0.22|0.18:0.95|1.15,lowpass=f=3900"),
  synth_patch(:warm_analog_duo, role: :warm, program: 94, weight: 2.0, mix: 0.76, fs_gain: 1.38,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "tremolo=f=0.28:d=0.1,aphaser=speed=0.1:decay=0.52,lowpass=f=3400"),
  synth_patch(:tape_string_pad, role: :warm, program: 48, weight: 2.2, mix: 0.7, fs_gain: 1.36,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "vibrato=f=0.15:d=0.01,lowpass=f=3600,aecho=0.32:0.4:100|180:0.2|0.1"),
  synth_patch(:polysynth_soul, role: :warm, program: 89, weight: 2.3, mix: 0.72, fs_gain: 1.42,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.48:0.68:36|46:0.22|0.18:0.26|0.22:1.05|1.25,lowpass=f=4100"),
  synth_patch(:mellotron_flute_pad, role: :warm, program: 73, weight: 1.8, mix: 0.68, fs_gain: 1.34,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "aecho=0.42:0.48:140|260:0.24|0.12,lowpass=f=3800"),
  synth_patch(:analog_hollow, role: :warm, program: 95, weight: 1.9, mix: 0.74, fs_gain: 1.37,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "lowpass=f=3000,tremolo=f=0.32:d=0.08,equalizer=f=200:t=o:w=1:g=2.2"),
  synth_patch(:juno_chorus_wash, role: :warm, program: 50, weight: 2.4, mix: 0.7, fs_gain: 1.4,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.62:0.82:44|54:0.32|0.28:0.38|0.32:1.15|1.45,lowpass=f=4300"),
  synth_patch(:prophet_brass_wash, role: :warm, program: 62, weight: 1.7, mix: 0.66, fs_gain: 1.35,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "lowpass=f=3500,acompressor=threshold=-24dB:ratio=2.2:attack=14:release=110"),
  # --- Texture layers (quiet bed under EP+pad) ---
  synth_patch(:shimmer_organ, role: :texture, program: 19, mix: 0.22, fx: "lowpass=f=2400,volume=0.35"),
  synth_patch(:ethnic_flute, role: :texture, program: 75, mix: 0.18, fx: "aecho=0.5:0.6:200|380:0.25|0.12"),
  synth_patch(:soft_synth_str, role: :texture, program: 50, mix: 0.15, fx: "lowpass=f=1800"),
  synth_patch(:space_voice, role: :texture, program: 54, mix: 0.12, fx: "aphaser=speed=0.12:decay=0.8"),
  synth_patch(:music_box, role: :texture, program: 10, mix: 0.14, fx: "aecho=0.45:0.55:60|120:0.3|0.15"),
  synth_patch(:kalimba_dust, role: :texture, program: 108, mix: 0.16, fx: "highpass=f=400"),
  synth_patch(:reverse_pad_ghost, role: :texture, program: 95, mix: 0.1, fx: "areverse,lowpass=f=1600"),
  # --- Lead / arp voices ---
  synth_patch(:prophet_lead, role: :lead, program: 81, weight: 2.5, fs_gain: 1.35, arp_styles: %i[updown skip_up], octave: 2,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :skip_up, subdiv: 8, gate: 0.58, vel: 0.52 },
              fx: "chorus=0.42:0.62:32|42:0.18|0.14:0.22|0.18:0.95|1.2,aecho=0.5:0.4:150|280:0.3|0.18,lowpass=f=4800"),
  synth_patch(:big_lead_prophet5, role: :lead, program: 87, weight: 2.8, fs_gain: 1.4, arp_styles: %i[pingpong quint_spread], octave: 2,
              fx: "chorus=0.52:0.72:36|46:0.24|0.2:0.28|0.22:1.15|1.45,aecho=0.45:0.38:140|260:0.28|0.16,lowpass=f=5400"),
  synth_patch(:prophet_bleeding_lead, role: :lead, program: 87, sf2: :supersaw, weight: 1.6, fs_gain: 1.38,
              arp_styles: %i[spiral coltrane], octave: 2,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :spiral, subdiv: 8, gate: 0.54, vel: 0.54 },
              fx: "chorus=0.58:0.78:44|54:0.3|0.25:0.32|0.28:1.25|1.6,aphaser=speed=0.16:decay=0.5,vibrato=f=0.38:d=0.015"),
  synth_patch(:charang_bite, role: :lead, program: 84, arp_styles: %i[up fibonacci], octave: 2,
              fx: "tremolo=f=5.5:d=0.18,aecho=0.5:0.38:140|260:0.28|0.16"),
  synth_patch(:fifths_lead, role: :lead, program: 86, arp_styles: %i[updown coltrane], octave: 2,
              fx: "vibrato=f=0.55:d=0.02,lowpass=f=4800"),
  synth_patch(:saw_lead, role: :lead, program: 81, arp_styles: %i[random_walk flylo_wobble], octave: 2,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :pingpong, subdiv: 8, gate: 0.55, vel: 0.5 },
              fx: "tremolo=f=3.2:d=0.2,aphaser=speed=0.22:decay=0.45"),
  synth_patch(:square_lead, role: :lead, program: 80, arp_styles: %i[euclidean donda_stab], octave: 2,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :euclidean, subdiv: 8, gate: 0.52, vel: 0.46 },
              fx: "acrusher=bits=10:samples=2:mix=0.18,aecho=0.4:0.35:100|200:0.25|0.14"),
  synth_patch(:supersaw_1, role: :lead, program: 0, sf2: :supersaw, arp_styles: %i[spiral updown], octave: 2,
              fx: "chorus=0.6:0.8:45|55:0.3|0.25:0.3|0.25:1.2|1.6,lowpass=f=6000"),
  synth_patch(:supersaw_2, role: :lead, program: 3, sf2: :supersaw, arp_styles: %i[skip_up pingpong], octave: 2,
              fx: "tremolo=f=4.8:d=0.16,aecho=0.55:0.45:180|340:0.3|0.18"),
  synth_patch(:supersaw_3, role: :lead, program: 7, sf2: :supersaw, arp_styles: %i[flylo_wobble random_walk], octave: 2,
              fx: "aphaser=speed=0.18:decay=0.5,vibrato=f=0.4:d=0.015"),
  synth_patch(:brass_synth, role: :lead, program: 62, arp_styles: %i[up coltrane], octave: 1,
              fx: "acompressor=threshold=-20dB:ratio=3:attack=8:release=90,lowpass=f=3800"),
  synth_patch(:soft_synth_lead, role: :lead, program: 88, arp_styles: %i[updown downup], octave: 2,
              fx: "aecho=0.6:0.5:220|400:0.35|0.2,lowpass=f=3400"),
  synth_patch(:fm_lead_bell, role: :lead, program: 98, arp_styles: %i[fibonacci quint_spread], octave: 3,
              fx: "aecho=0.45:0.5:90|170:0.35|0.2,aphaser=speed=0.1:decay=0.65"),
  synth_patch(:oboe_solo, role: :lead, program: 68, arp_styles: %i[updown skip_up], octave: 2,
              fx: "vibrato=f=0.62:d=0.018,tremolo=f=2.2:d=0.08"),
  synth_patch(:clarinet_lead, role: :lead, program: 71, arp_styles: %i[downup pingpong], octave: 2,
              fx: "lowpass=f=3000,aecho=0.35:0.4:130|240:0.22|0.12"),
  synth_patch(:flute_airy, role: :lead, program: 73, arp_styles: %i[spiral random_walk], octave: 3,
              fx: "aecho=0.5:0.55:200|360:0.3|0.16,highpass=f=280"),
  synth_patch(:whistle_hook, role: :lead, program: 78, arp_styles: %i[up euclidean], octave: 3,
              fx: "tremolo=f=6.5:d=0.12,aecho=0.4:0.45:80|150:0.28|0.14"),
  synth_patch(:guitar_muted, role: :lead, program: 28, arp_styles: %i[skip_up donda_stab], octave: 2,
              fx: "lowpass=f=2600,acrusher=bits=11:samples=1.5:mix=0.12"),
  synth_patch(:dist_guitar, role: :lead, program: 30, arp_styles: %i[coltrane updown], octave: 1,
              fx: "acompressor=threshold=-18dB:ratio=4:attack=3:release=60,lowpass=f=4200"),
  synth_patch(:pluck_synth, role: :lead, program: 24, arp_styles: %i[up pingpong], octave: 2, gate: 0.55,
              fx: "aecho=0.35:0.4:60|110:0.25|0.12,highpass=f=200"),
  synth_patch(:banjo_pluck, role: :lead, program: 105, arp_styles: %i[skip_up fibonacci], octave: 2, gate: 0.5,
              fx: "aecho=0.3:0.35:50|90:0.2|0.1"),
  synth_patch(:koto_pluck, role: :lead, program: 107, arp_styles: %i[euclidean spiral], octave: 2, gate: 0.48,
              fx: "lowpass=f=3500,aecho=0.4:0.45:70|130:0.22|0.1"),
  synth_patch(:voice_lead, role: :lead, program: 54, arp_styles: %i[updown flylo_wobble], octave: 2,
              fx: "vibrato=f=0.5:d=0.014,aphaser=speed=0.1:decay=0.6"),
  synth_patch(:minimoog_lead, role: :lead, program: 81, weight: 2.4, fs_gain: 1.35, arp_styles: %i[up random_walk], octave: 1,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :updown, subdiv: 4, gate: 0.65, vel: 0.48 },
              fx: "lowpass=f=2200:width_type=q:width=0.8,tremolo=f=2.5:d=0.12,equalizer=f=140:t=o:w=0.9:g=2.5,aecho=0.42:0.35:110|200:0.22|0.1"),
  synth_patch(:moog_ladder_lead, role: :lead, program: 38, weight: 2.0, fs_gain: 1.32, arp_styles: %i[updown fibonacci], octave: 1,
              midi_fx: MIDI_FX_LEAD, midi_arp: { style: :fibonacci, subdiv: 4, gate: 0.6, vel: 0.5 },
              fx: "lowpass=f=2800,tremolo=f=3.5:d=0.14,chorus=0.35:0.55:28|36:0.14|0.1:0.18|0.14:0.85|1.1"),
  synth_patch(:cs_lead, role: :lead, program: 82, arp_styles: %i[downup quint_spread], octave: 2,
              fx: "chorus=0.4:0.6:35|45:0.2|0.15:0.2|0.2:0.9|1.2"),
  # --- Soul lead arp voices (LEAD_ARP stem — chord-tone figures up top) ---
  synth_patch(:donuts_wurli_lead, role: :lead, program: 5, weight: 3.0, fs_gain: 1.32, gate: 0.68, octave: 2,
              arp_styles: %i[skip_up euclidean quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.64, vel: 0.5 },
              fx: "tremolo=f=0.28:d=0.04,aecho=0.48:0.42:100|180:0.24|0.12,lowpass=f=5200"),
  synth_patch(:soul_prophet_arp, role: :lead, program: 81, weight: 3.2, fs_gain: 1.36, gate: 0.62, octave: 2,
              arp_styles: %i[pingpong skip_up updown], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :pingpong, subdiv: 6, gate: 0.6, vel: 0.52 },
              fx: "chorus=0.44:0.64:32|42:0.2|0.16:0.22|0.2:1.0|1.25,aecho=0.5:0.4:160|280:0.28|0.16,lowpass=f=4600"),
  synth_patch(:moog_dilla_pocket, role: :lead, program: 38, weight: 2.8, fs_gain: 1.34, gate: 0.66, octave: 1,
              arp_styles: %i[up downup quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 4, gate: 0.68, vel: 0.54 },
              fx: "lowpass=f=2600,tremolo=f=2.8:d=0.11,equalizer=f=180:t=o:w=1:g=2.8,aecho=0.38:0.32:90|160:0.18|0.1"),
  synth_patch(:neo_soul_pluck, role: :lead, program: 24, weight: 2.6, fs_gain: 1.28, gate: 0.58, octave: 2,
              arp_styles: %i[skip_up fibonacci donda_stab], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.54, vel: 0.48 },
              fx: "aecho=0.42:0.38:70|130:0.22|0.1,highpass=f=220,lowpass=f=4200"),
  synth_patch(:flylo_fm_shimmer, role: :lead, program: 98, weight: 2.4, fs_gain: 1.3, gate: 0.56, octave: 3,
              arp_styles: %i[spiral fibonacci random_walk], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 8, gate: 0.56, vel: 0.46 },
              fx: "aecho=0.5:0.45:110|200:0.3|0.16,aphaser=speed=0.12:decay=0.55,lowpass=f=5800"),
  synth_patch(:jazz_ballad_lead, role: :lead, program: 73, weight: 2.5, fs_gain: 1.26, gate: 0.7, octave: 2,
              arp_styles: %i[updown coltrane], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.72, vel: 0.44 },
              fx: "vibrato=f=0.45:d=0.012,aecho=0.55:0.48:200|360:0.28|0.14,lowpass=f=4000"),
  synth_patch(:gospel_brass_lead, role: :lead, program: 62, weight: 2.2, fs_gain: 1.3, gate: 0.64, octave: 1,
              arp_styles: %i[coltrane up quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :coltrane, subdiv: 6, gate: 0.62, vel: 0.5 },
              fx: "acompressor=threshold=-22dB:ratio=2.5:attack=12:release=100,lowpass=f=3600"),
  synth_patch(:erykah_dust_lead, role: :lead, program: 4, weight: 2.9, fs_gain: 1.3, gate: 0.6, octave: 2,
              arp_styles: %i[euclidean skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :euclidean, subdiv: 8, gate: 0.7, vel: 0.42 },
              fx: "tremolo=f=0.22:d=0.03,acrusher=bits=12:samples=2:mix=0.08,lowpass=f=4800"),
  synth_patch(:watermelon_glass, role: :lead, program: 88, weight: 2.7, fs_gain: 1.28, gate: 0.64, octave: 2,
              arp_styles: %i[updown quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :quint_spread, subdiv: 6, gate: 0.66, vel: 0.46 },
              fx: "aecho=0.52:0.46:140|260:0.26|0.14,lowpass=f=3800"),
  synth_patch(:rhodes_lead_comp, role: :lead, program: 4, weight: 2.5, fs_gain: 1.3, gate: 0.64, octave: 2,
              arp_styles: %i[updown skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 6, gate: 0.66, vel: 0.48 },
              fx: "tremolo=f=0.3:d=0.05,lowpass=f=4600"),
  synth_patch(:mark1_soul_lead, role: :lead, program: 5, weight: 2.4, fs_gain: 1.32, gate: 0.62, octave: 2,
              arp_styles: %i[skip_up quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.6, vel: 0.5 },
              fx: "aecho=0.4:0.38:80|150:0.22|0.1,lowpass=f=5000"),
  synth_patch(:dangelo_clav_lead, role: :lead, program: 7, weight: 2.3, fs_gain: 1.28, gate: 0.56, octave: 2,
              arp_styles: %i[skip_up donda_stab], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :skip_up, subdiv: 8, gate: 0.54, vel: 0.52 },
              fx: "highpass=f=200,lowpass=f=4200"),
  synth_patch(:stevie_organ_lead, role: :lead, program: 16, weight: 2.1, fs_gain: 1.3, gate: 0.68, octave: 2,
              arp_styles: %i[coltrane up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :coltrane, subdiv: 6, gate: 0.7, vel: 0.46 },
              fx: "chorus=0.36:0.52:28|36:0.14|0.1:0.16|0.14:0.9|1.1,lowpass=f=4000"),
  synth_patch(:glasper_ep_lead, role: :lead, program: 4, weight: 2.6, fs_gain: 1.34, gate: 0.6, octave: 2,
              arp_styles: %i[quint_spread coltrane], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :quint_spread, subdiv: 6, gate: 0.62, vel: 0.46 },
              fx: "aecho=0.45:0.4:110|200:0.26|0.14,lowpass=f=4400"),
  synth_patch(:warm_prophet_hook, role: :lead, program: 81, weight: 2.5, fs_gain: 1.36, gate: 0.6, octave: 2,
              arp_styles: %i[pingpong updown], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :pingpong, subdiv: 6, gate: 0.64, vel: 0.5 },
              fx: "chorus=0.4:0.58:30|40:0.18|0.14:0.2|0.18:0.95|1.15,lowpass=f=4200"),
  synth_patch(:questlove_moog_lead, role: :lead, program: 38, weight: 2.4, fs_gain: 1.33, gate: 0.66, octave: 1,
              arp_styles: %i[up downup], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 4, gate: 0.68, vel: 0.54 },
              fx: "lowpass=f=2800,tremolo=f=2.6:d=0.1"),
  synth_patch(:portishead_dust_lead, role: :lead, program: 4, weight: 2.2, fs_gain: 1.28, gate: 0.58, octave: 2,
              arp_styles: %i[euclidean skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :euclidean, subdiv: 8, gate: 0.68, vel: 0.42 },
              fx: "acrusher=bits=12:samples=2:mix=0.1,lowpass=f=4600"),
  synth_patch(:nord_stage_lead, role: :lead, program: 88, weight: 2.3, fs_gain: 1.3, gate: 0.62, octave: 2,
              arp_styles: %i[updown quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.66, vel: 0.48 },
              fx: "aecho=0.42:0.38:90|170:0.22|0.12,lowpass=f=4000"),
  synth_patch(:rhodes_skank_lead, role: :lead, program: 4, weight: 2.0, fs_gain: 1.26, gate: 0.52, octave: 2,
              arp_styles: %i[donda_stab skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :donda_stab, subdiv: 8, gate: 0.5, vel: 0.54 },
              fx: "highpass=f=220,tremolo=f=0.55:d=0.07"),
  synth_patch(:tame_wobble_lead, role: :lead, program: 81, weight: 2.0, fs_gain: 1.32, gate: 0.58, octave: 2,
              arp_styles: %i[flylo_wobble spiral], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 8, gate: 0.56, vel: 0.46 },
              fx: "tremolo=f=0.65:d=0.14,aphaser=speed=0.16:decay=0.5,lowpass=f=5200"),
  # --- Scale-locked arp lead (continuous, same scale as each pad chord) ---
  synth_patch(:scale_arp_prophet, role: :scale_lead, program: 81, weight: 3.2, fs_gain: 1.28, gate: 0.62,
              arp_styles: %i[updown skip_up pingpong], octave: 2, midi_fx: MIDI_FX_SCALE_LEAD,
              fx: "chorus=0.38:0.58:30|40:0.16|0.12:0.2|0.18:0.9|1.15,aecho=0.45:0.38:120|220:0.22|0.12,lowpass=f=4200"),
  synth_patch(:scale_arp_moog, role: :scale_lead, program: 38, weight: 2.8, fs_gain: 1.25, gate: 0.58,
              arp_styles: %i[up downup fibonacci], octave: 2,
              fx: "lowpass=f=3600:width_type=q:width=0.8,tremolo=f=2.8:d=0.1,aecho=0.38:0.32:100|180:0.18|0.1"),
  synth_patch(:scale_arp_rhodes, role: :scale_lead, program: 4, weight: 2.4, fs_gain: 1.3, gate: 0.55,
              arp_styles: %i[updown quint_spread spiral], octave: 2,
              fx: "tremolo=f=0.35:d=0.05,aecho=0.4:0.45:80|150:0.2|0.1,lowpass=f=4800"),
  synth_patch(:scale_arp_supersaw, role: :scale_lead, program: 0, sf2: :supersaw, weight: 1.8, fs_gain: 1.22,
              gate: 0.6, arp_styles: %i[spiral random_walk up], octave: 2,
              fx: "chorus=0.45:0.65:34|44:0.2|0.16:0.24|0.2:1.05|1.3,lowpass=f=5000"),
  # --- Native additive fallbacks (no soundfont) ---
  synth_patch(:native_rhodes, role: :native, program: 0, weight: 2.5, native: { wave: :rhodes, detune: 0.005, bloom: 0.34 }),
  synth_patch(:native_rhodes_bleeding, role: :native, program: 0, weight: 1.8, native: { wave: :rhodes, detune: 0.008, bloom: 0.42 }),
  synth_patch(:native_juno, role: :native, program: 0, native: { wave: :juno, detune: 0.006, bloom: 0.18 }),
  synth_patch(:native_prophet, role: :native, program: 0, weight: 2.2, native: { wave: :prophet, detune: 0.007, bloom: 0.26 }),
  synth_patch(:native_moog, role: :native, program: 0, weight: 2.2, native: { wave: :moog, detune: 0.005, bloom: 0.24 }),
  synth_patch(:native_fm_glass, role: :native, program: 0, weight: 2.4,
              native: { wave: :fm, detune: 0.002, bloom: 0.35, fm_index: 2.0, fm_feedback: 0.14 }),
  synth_patch(:native_organ, role: :native, program: 0, native: { wave: :organ, detune: 0.003, bloom: 0.12 }),
  synth_patch(:native_warm_pad, role: :native, program: 0, native: { wave: :triangle, detune: 0.007, bloom: 0.15 }),
  synth_patch(:native_string, role: :native, program: 0, native: { wave: :bowed, detune: 0.004, bloom: 0.2 }),
  synth_patch(:native_pwm, role: :native, program: 0, native: { wave: :pwm, detune: 0.008, bloom: 0.25 }),
  # --- Experimental electronic pads (musical, not noise) ---
  synth_patch(:glass_fm_pad, role: :warm, program: 98, weight: 2.6, mix: 0.72, fs_gain: 1.38,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "aecho=0.48:0.42:90|170:0.28|0.14,aphaser=speed=0.08:decay=0.55,lowpass=f=5200,equalizer=f=3200:t=h:w=1600:g=1.4"),
  synth_patch(:vapor_supersaw, role: :warm, program: 0, sf2: :supersaw, weight: 2.4, mix: 0.68, fs_gain: 1.36,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "chorus=0.55:0.75:40|50:0.28|0.24:0.32|0.28:1.2|1.5,lowpass=f=4800,aecho=0.4:0.36:140|260:0.22|0.12"),
  synth_patch(:crystal_pwm, role: :warm, program: 90, weight: 2.2, mix: 0.7, fs_gain: 1.34,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "tremolo=f=0.22:d=0.06,chorus=0.4:0.58:28|38:0.16|0.12:0.2|0.16:0.95|1.2,lowpass=f=4600"),
  synth_patch(:ice_string_pad, role: :warm, program: 50, weight: 2.3, mix: 0.66, fs_gain: 1.32,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "highpass=f=180,chorus=0.48:0.68:36|46:0.22|0.18:0.26|0.22:1.1|1.35,lowpass=f=4000"),
  synth_patch(:neon_ladder, role: :warm, program: 38, weight: 2.5, mix: 0.74, fs_gain: 1.4,
              midi_fx: MIDI_FX_PAD_WARM,
              fx: "lowpass=f=2400:width_type=q:width=0.85,tremolo=f=0.18:d=0.05,equalizer=f=160:t=o:w=1:g=2.4,aecho=0.36:0.3:80|150:0.16|0.08"),
  synth_patch(:acid_pluck_lead, role: :lead, program: 38, weight: 2.2, fs_gain: 1.3, gate: 0.48, octave: 1,
              arp_styles: %i[up skip_up euclidean], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 8, gate: 0.45, vel: 0.52 },
              fx: "lowpass=f=1800:width_type=q:width=1.1,tremolo=f=0.0:d=0,equalizer=f=400:t=o:w=1.2:g=2.0"),
  synth_patch(:glass_arp_lead, role: :lead, program: 98, weight: 2.6, fs_gain: 1.28, gate: 0.55, octave: 3,
              arp_styles: %i[spiral quint_spread pingpong], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 6, gate: 0.58, vel: 0.46 },
              fx: "aecho=0.5:0.44:100|190:0.28|0.14,highpass=f=400,lowpass=f=6200"),
  synth_patch(:vapor_lead, role: :lead, program: 3, sf2: :supersaw, weight: 2.3, fs_gain: 1.3, gate: 0.6, octave: 2,
              arp_styles: %i[updown flylo_wobble], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :updown, subdiv: 4, gate: 0.62, vel: 0.48 },
              fx: "chorus=0.5:0.7:38|48:0.26|0.22:0.3|0.26:1.15|1.4,lowpass=f=5000"),
  synth_patch(:crystal_scale_lead, role: :scale_lead, program: 98, weight: 2.4, fs_gain: 1.24, gate: 0.58,
              arp_styles: %i[spiral updown], octave: 2,
              fx: "aecho=0.46:0.4:110|200:0.24|0.12,lowpass=f=5400"),
  # --- Character leads (scale-locked arps + strong FX identity) ---
  synth_patch(:jupiter_superlead, role: :lead, program: 81, weight: 3.4, fs_gain: 1.42, gate: 0.58, octave: 2,
              arp_styles: %i[spiral pingpong skip_up flylo_wobble], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 8, gate: 0.56, vel: 0.56 },
              fx: "chorus=0.55:0.75:42|54:0.28|0.24:0.32|0.28:1.2|1.5,aecho=0.52:0.46:160|300:0.3|0.16,aphaser=speed=0.18:decay=0.48,equalizer=f=3000:t=o:w=1.4:g=3.5,lowpass=f=6800"),
  synth_patch(:obxr_sync_lead, role: :lead, program: 87, weight: 3.1, fs_gain: 1.4, gate: 0.52, octave: 2,
              arp_styles: %i[euclidean ratchet skip_up], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :euclidean, subdiv: 8, gate: 0.5, vel: 0.58 },
              fx: "tremolo=f=5.5:d=0.1,chorus=0.4:0.6:32|44:0.2|0.16:0.24|0.2:1.05|1.3,aecho=0.45:0.38:120|220:0.26|0.12,equalizer=f=2400:t=o:w=1.2:g=2.8,lowpass=f=5600"),
  synth_patch(:cs80_brass_lead, role: :lead, program: 62, weight: 2.9, fs_gain: 1.38, gate: 0.64, octave: 1,
              arp_styles: %i[coltrane updown quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :coltrane, subdiv: 6, gate: 0.66, vel: 0.54 },
              fx: "vibrato=f=0.48:d=0.014,chorus=0.42:0.62:28|38:0.18|0.14:0.2|0.18:1.0|1.25,aecho=0.48:0.42:180|320:0.28|0.14,equalizer=f=1800:t=o:w=1.1:g=2.2,lowpass=f=4800"),
  synth_patch(:mono_poly_lead, role: :lead, program: 80, weight: 3.0, fs_gain: 1.4, gate: 0.55, octave: 2,
              arp_styles: %i[up skip_up burst spiral], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :up, subdiv: 8, gate: 0.52, vel: 0.56 },
              fx: "lowpass=f=3200:width_type=q:width=0.9,tremolo=f=3.2:d=0.09,aecho=0.4:0.35:100|180:0.22|0.1,equalizer=f=900:t=o:w=1:g=1.8,equalizer=f=3500:t=h:w=1.3:g=2.5"),
  synth_patch(:dx7_glass_arp, role: :lead, program: 98, weight: 3.2, fs_gain: 1.36, gate: 0.5, octave: 3,
              arp_styles: %i[spiral fibonacci quint_spread], midi_fx: MIDI_FX_LEAD,
              midi_arp: { style: :spiral, subdiv: 6, gate: 0.52, vel: 0.5 },
              fx: "aecho=0.55:0.48:110|200:0.32|0.16,aphaser=speed=0.11:decay=0.55,highpass=f=420,equalizer=f=4800:t=h:w=1.4:g=2.2,lowpass=f=7200"),
  synth_patch(:jp8_brass_arp, role: :scale_lead, program: 63, weight: 3.0, fs_gain: 1.32, gate: 0.6, octave: 2,
              arp_styles: %i[updown pingpong coltrane], midi_fx: MIDI_FX_SCALE_LEAD,
              fx: "chorus=0.5:0.7:38|48:0.24|0.2:0.28|0.24:1.15|1.4,aecho=0.46:0.4:140|260:0.26|0.14,equalizer=f=2600:t=o:w=1.3:g=3.0,lowpass=f=6000"),
  synth_patch(:sh101_sequence, role: :scale_lead, program: 38, weight: 2.9, fs_gain: 1.3, gate: 0.48, octave: 2,
              arp_styles: %i[up euclidean skip_up], midi_fx: MIDI_FX_SCALE_LEAD,
              fx: "lowpass=f=2400:width_type=q:width=1.0,tremolo=f=0.0:d=0,aecho=0.38:0.32:80|150:0.2|0.1,equalizer=f=400:t=o:w=1.2:g=2.4,equalizer=f=2800:t=h:w=1.2:g=2.0")
].freeze

SYNTH_PATCH_BY_ROLE = SYNTH_PATCH_CATALOG.group_by { |p| p[:role] }.freeze
SYNTH_PATCH_BY_ID = SYNTH_PATCH_CATALOG.each_with_object({}) { |p, h| h[p[:id]] = p }.freeze

# Pad voice stacks — classic analog + curated experimental electronic.
# stack_soul = multi-preset layer (EP + Moog + Prophet + texture) for rich beds.
PAD_VOICE_PRESETS = {
  rhodes:  { ep: :rhodes_mark1, warm: :juno_chorus_wash },
  moog:    { ep: :rhodes_cafe_warm, warm: :moog_model_d },
  prophet: { ep: :rhodes_mark1, warm: :prophet_5_pad },
  blend:   { ep: :rhodes_stage73, warm: :moog_sub37_pad },
  glass:   { ep: :dx7_bell_ep, warm: :glass_fm_pad },
  vapor:   { ep: :rhodes_cafe_warm, warm: :vapor_supersaw },
  crystal: { ep: :galaxy_ep2, warm: :crystal_pwm },
  ice:     { ep: :rhodes_dx_blend, warm: :ice_string_pad },
  neon:    { ep: :rhodes_mark1, warm: :neon_ladder },
  pulse:   { ep: :clav_neo_funk, warm: :pwm_sweep_pad },
  # Multi-layer stacks (rendered as 3–4 FluidSynth passes when PAD_LAYERS=1).
  stack_soul: { ep: :rhodes_cafe_warm, warm: :moog_model_d, warm2: :prophet_5_pad, texture: :juno_chorus_wash },
  stack_glass: { ep: :dx7_bell_ep, warm: :glass_fm_pad, warm2: :prophet_6_warm, texture: :ice_string_pad },
  stack_vapor: { ep: :rhodes_mark1, warm: :vapor_supersaw, warm2: :moog_sub37_pad, texture: :soft_synth_str }
}.freeze

# Explicit multi-layer pad stacks: id + amix weight. Order = mix order.
# Weights favor distinct timbres (EP attack, Moog body, Prophet air, Juno sheen).
PAD_LAYER_STACKS = {
  stack_soul: [
    { id: :rhodes_cafe_warm, mix: 1.22, role: :ep },
    { id: :moog_model_d, mix: 0.95, role: :warm },
    { id: :prophet_5_pad, mix: 0.72, role: :warm },
    { id: :juno_chorus_wash, mix: 0.42, role: :texture }
  ],
  stack_glass: [
    { id: :dx7_bell_ep, mix: 1.08, role: :ep },
    { id: :glass_fm_pad, mix: 0.95, role: :warm },
    { id: :prophet_6_warm, mix: 0.62, role: :warm },
    { id: :ice_string_pad, mix: 0.38, role: :texture }
  ],
  stack_vapor: [
    { id: :rhodes_mark1, mix: 1.12, role: :ep },
    { id: :vapor_supersaw, mix: 0.88, role: :warm },
    { id: :moog_sub37_pad, mix: 0.62, role: :warm },
    { id: :soft_synth_str, mix: 0.36, role: :texture }
  ]
}.freeze

# Morph rotation includes experimental families (good-sounding only).
PAD_VOICE_MORPH_VOICES = %i[moog prophet glass vapor rhodes neon crystal].freeze

# Soft experimental lead morph — avoid shred/hard noise walls by default.
LEAD_MORPH_VOICES = %i[flylo prophet moog glass vapor soft].freeze
MORPH_LEAD_PATCH_POOL = {
  hard: %i[saw_lead square_lead dist_guitar charang_bite fm_lead_bell minimoog_lead fifths_lead],
  flylo: %i[flylo_fm_shimmer fm_lead_bell glass_arp_lead flute_airy prophet_bleeding_lead],
  glitch: %i[square_lead voice_lead whistle_hook charang_bite banjo_pluck koto_pluck],
  prophet: %i[prophet_lead big_lead_prophet5 soul_prophet_arp warm_prophet_hook prophet_bleeding_lead],
  moog: %i[moog_ladder_lead minimoog_lead moog_dilla_pocket questlove_moog_lead acid_pluck_lead],
  shred: %i[dist_guitar charang_bite saw_lead square_lead brass_synth pluck_synth],
  glass: %i[glass_arp_lead flylo_fm_shimmer fm_lead_bell],
  vapor: %i[vapor_lead supersaw_1 supersaw_2 tame_wobble_lead],
  soft: %i[soft_synth_lead jazz_ballad_lead nord_stage_lead watermelon_glass]
}.freeze
MORPH_LEAD_ARP_CYCLE = %i[flylo_spiral prophet_saw moog_rip soul_wash glass_spin vapor_wave neo_quartal].freeze

# FM synthesis — integer C:M = musical; irrational→rational morph stabilizes metallic timbres.
FM_RATIO_POOL = [
  { m: 1.0, c: 1.0, target_m: 1.0, irrational: false },
  { m: 2.0, c: 1.0, target_m: 2.0, irrational: false },
  { m: 3.0, c: 1.0, target_m: 3.0, irrational: false },
  { m: 3.0, c: 2.0, target_m: 3.0, irrational: false },
  { m: 5.0, c: 2.0, target_m: 5.0, irrational: false },
  { m: 1.37, c: 1.0, target_m: 1.0, irrational: true },
  { m: 2.71, c: 1.0, target_m: 2.0, irrational: true },
  { m: 3.87, c: 1.0, target_m: 3.0, irrational: true }
].freeze
FM_INDEX_BASE_PAD = 1.8
FM_INDEX_BASE_XLEAD = 2.6
FM_INDEX_VEL_SCALE = 3.2
FM_FEEDBACK_DEFAULT = 0.18
FM_XLEAD_NATIVE_MIX = 0.42

# Per-track pad character — applied on stream rotation and deep renders unless
# PAD_VOICE / PAD_ARP_MODE were set on the CLI before launch.
TRACK_SOUL_PAD_PROFILES = {
  glasper_quartal:     { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1100" },
  slow_ballad_wash:    { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3200" },
  suspended_ballad:    { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1300", "PAD_RELEASE" => "3400" },
  neo_soul_pocket:     { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "shimmer" },
  quartal_west_coast:  { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash" },
  maj7_minor_cycle:    { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1050", "PAD_RELEASE" => "2800" },
  minor_iv_loop:       { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "shimmer" },
  two_chord_hypnosis:  { "PAD_VOICE" => "moog", "PAD_ARP_MODE" => "pulse" },
  relative_major_turn: { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "shimmer" },
  minor_turnaround:    { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "blend" },
  warm_minor_arc:      { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "shimmer" },
  minor_triad_walk:    { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "figure" },
  major_lifting:       { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "blend" },
  slash_ninth_cycle:   { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "duo" },
  dorian_iv_loop:      { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash" },
  backdoor_resolve:    { "PAD_VOICE" => "moog", "PAD_ARP_MODE" => "pulse" },
  gospel_bIII:         { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "shimmer" },
  erykah_minor:        { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1000" },
  watermelon_turn:     { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "shimmer" },
  church_sus:          { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "held" },
  jazz_ballad_waltz:   { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1400" },
  slash_neo_soul:      { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "duo" },
  modal_safe:          { "PAD_VOICE" => "moog", "PAD_ARP_MODE" => "pulse" },
  minMaj_color:        { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash" },
  electronium_loop:    { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1100", "PAD_RELEASE" => "3200" },
  electronium_classic: { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "shimmer", "PAD_ATTACK" => "980", "PAD_RELEASE" => "2600" },
  fourth_third_sixth_second_turn: { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1400", "PAD_RELEASE" => "3800" },
  aydin_modal_quartal: { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3200", "VOICING" => "quartal" },
  aydin_jazz_turn:     { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "shimmer", "PAD_ATTACK" => "1050", "PAD_RELEASE" => "2800", "VOICING" => "bill_evans" },
  bach_circle_descent: { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "figure", "PAD_ATTACK" => "900", "PAD_RELEASE" => "2400", "VOICING" => "drop2" },
  bach_descending_bass: { "PAD_VOICE" => "blend", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1100", "PAD_RELEASE" => "3000", "VOICING" => "kenny_barron" },
  timeless_authentic:  { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1300", "PAD_RELEASE" => "3600" },
  long_soul:           { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "PAD_VOL" => "74" },
  golden:              { "PAD_VOICE" => "stack_soul", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "PAD_VOL" => "74" },
  chromatic_mediant_drift: { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3200" },
  # Expansion pack — Rhodes / Prophet / Moog pairings for new progressions.
  lydian_glass_cycle:      { "PAD_VOICE" => "glass", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3400" },
  pedal_upper_structures:  { "PAD_VOICE" => "neon", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1300", "PAD_RELEASE" => "3600" },
  bossa_major9_turn:       { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "shimmer", "PAD_ATTACK" => "900", "PAD_RELEASE" => "2600" },
  phrygian_gold_arc:       { "PAD_VOICE" => "vapor", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1100", "PAD_RELEASE" => "3000" },
  two_chord_luminous:      { "PAD_VOICE" => "crystal", "PAD_ARP_MODE" => "held", "PAD_ATTACK" => "1600", "PAD_RELEASE" => "4200" },
  mixo_sus_loop:           { "PAD_VOICE" => "pulse", "PAD_ARP_MODE" => "pulse", "PAD_ATTACK" => "800", "PAD_RELEASE" => "2200" },
  common_tone_drift:       { "PAD_VOICE" => "glass", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1150", "PAD_RELEASE" => "3200" },
  coltrane_lite_triad:     { "PAD_VOICE" => "ice", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1000", "PAD_RELEASE" => "2800" },
  drone_quartal_wash:      { "PAD_VOICE" => "vapor", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "VOICING" => "quartal" },
  waltz_relative_lift:     { "PAD_VOICE" => "rhodes", "PAD_ARP_MODE" => "wash", "PAD_ATTACK" => "1200", "PAD_RELEASE" => "3200" },
  half_time_gospel_plagal: { "PAD_VOICE" => "prophet", "PAD_ARP_MODE" => "held", "PAD_ATTACK" => "1400", "PAD_RELEASE" => "3800" },
  double_time_pocket:      { "PAD_VOICE" => "moog", "PAD_ARP_MODE" => "pulse", "PAD_ATTACK" => "700", "PAD_RELEASE" => "1800" },
  whole_tone_bridge:       { "PAD_VOICE" => "glass", "PAD_ARP_MODE" => "figure", "PAD_ATTACK" => "900", "PAD_RELEASE" => "2400" },
  upper_triad_tower:       { "PAD_VOICE" => "crystal", "PAD_ARP_MODE" => "duo", "PAD_ATTACK" => "1000", "PAD_RELEASE" => "2800" },
  minor_add9_lullaby:      { "PAD_VOICE" => "ice", "PAD_ARP_MODE" => "held", "PAD_ATTACK" => "1700", "PAD_RELEASE" => "4500" },
  dominant_chain_home:     { "PAD_VOICE" => "neon", "PAD_ARP_MODE" => "pulse", "PAD_ATTACK" => "850", "PAD_RELEASE" => "2200" }
}.freeze

# Per-track lead voice + arp figure — pairs with TRACK_SOUL_PAD_PROFILES.
TRACK_SOUL_LEAD_PROFILES = {
  glasper_quartal:     { "LEAD_VOICE" => "cs", "LEAD_ARP_MODE" => "neo_quartal" },
  slow_ballad_wash:    { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom" },
  suspended_ballad:    { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "soul_wash" },
  neo_soul_pocket:     { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "moog_funk" },
  quartal_west_coast:  { "LEAD_VOICE" => "flylo", "LEAD_ARP_MODE" => "flylo_spiral" },
  maj7_minor_cycle:    { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "LEAD_ARP" => "1", "HARMONY_LEAD" => "1" },
  minor_iv_loop:       { "LEAD_VOICE" => "donuts", "LEAD_ARP_MODE" => "donuts_shimmer" },
  two_chord_hypnosis:  { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "pocket_stab" },
  relative_major_turn: { "LEAD_VOICE" => "soft", "LEAD_ARP_MODE" => "donuts_shimmer" },
  minor_turnaround:    { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal" },
  warm_minor_arc:      { "LEAD_VOICE" => "soft", "LEAD_ARP_MODE" => "soul_wash" },
  minor_triad_walk:    { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "flylo_spiral" },
  major_lifting:       { "LEAD_VOICE" => "prophet", "LEAD_ARP_MODE" => "neo_quartal" },
  slash_ninth_cycle:   { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "prophet_glass" },
  dorian_iv_loop:      { "LEAD_VOICE" => "prophet", "LEAD_ARP_MODE" => "soul_wash" },
  backdoor_resolve:    { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "moog_funk" },
  gospel_bIII:         { "LEAD_VOICE" => "gospel", "LEAD_ARP_MODE" => "gospel_lift" },
  erykah_minor:        { "LEAD_VOICE" => "erykah", "LEAD_ARP_MODE" => "erykah_dust" },
  watermelon_turn:     { "LEAD_VOICE" => "watermelon", "LEAD_ARP_MODE" => "donuts_shimmer" },
  church_sus:          { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom" },
  jazz_ballad_waltz:   { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom" },
  slash_neo_soul:      { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal" },
  modal_safe:          { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "pocket_stab" },
  minMaj_color:        { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash" },
  electronium_loop:    { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "LEAD_ARP" => "1", "HARMONY_LEAD" => "1" },
  electronium_classic: { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal" },
  fourth_third_sixth_second_turn: { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1" },
  aydin_modal_quartal: { "LEAD_VOICE" => "cs", "LEAD_ARP_MODE" => "neo_quartal", "HARMONY_LEAD" => "1" },
  aydin_jazz_turn:     { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom", "HARMONY_LEAD" => "1" },
  bach_circle_descent: { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal", "HARMONY_LEAD" => "1" },
  bach_descending_bass: { "LEAD_VOICE" => "soft", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1" },
  timeless_authentic:  { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "prophet_glass", "HARMONY_LEAD" => "1" },
  long_soul:           { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  golden:              { "LEAD_VOICE" => "soul_prophet", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  chromatic_mediant_drift: { "LEAD_VOICE" => "flylo", "LEAD_ARP_MODE" => "flylo_spiral", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  lydian_glass_cycle:      { "LEAD_VOICE" => "glass", "LEAD_ARP_MODE" => "glass_spin", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  pedal_upper_structures:  { "LEAD_VOICE" => "neon", "LEAD_ARP_MODE" => "soul_wash", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  bossa_major9_turn:       { "LEAD_VOICE" => "neo_pluck", "LEAD_ARP_MODE" => "neo_quartal", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  phrygian_gold_arc:       { "LEAD_VOICE" => "vapor", "LEAD_ARP_MODE" => "vapor_wave", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  two_chord_luminous:      { "LEAD_VOICE" => "crystal", "LEAD_ARP_MODE" => "crystal_scatter", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  mixo_sus_loop:           { "LEAD_VOICE" => "acid", "LEAD_ARP_MODE" => "acid_run", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  common_tone_drift:       { "LEAD_VOICE" => "glass", "LEAD_ARP_MODE" => "glass_spin", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  coltrane_lite_triad:     { "LEAD_VOICE" => "flylo", "LEAD_ARP_MODE" => "flylo_spiral", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  drone_quartal_wash:      { "LEAD_VOICE" => "vapor", "LEAD_ARP_MODE" => "vapor_wave", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  waltz_relative_lift:     { "LEAD_VOICE" => "ballad", "LEAD_ARP_MODE" => "ballad_bloom", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  half_time_gospel_plagal: { "LEAD_VOICE" => "gospel", "LEAD_ARP_MODE" => "gospel_lift", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  double_time_pocket:      { "LEAD_VOICE" => "moog", "LEAD_ARP_MODE" => "pocket_stab", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  whole_tone_bridge:       { "LEAD_VOICE" => "glass", "LEAD_ARP_MODE" => "crystal_scatter", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  upper_triad_tower:       { "LEAD_VOICE" => "crystal", "LEAD_ARP_MODE" => "neo_quartal", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  minor_add9_lullaby:      { "LEAD_VOICE" => "soft", "LEAD_ARP_MODE" => "ballad_bloom", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" },
  dominant_chain_home:     { "LEAD_VOICE" => "acid", "LEAD_ARP_MODE" => "acid_run", "HARMONY_LEAD" => "1", "LEAD_ARP" => "1" }
}.freeze

LEAD_VOICE_PRESETS = {
  donuts: :donuts_wurli_lead,
  soul_prophet: :soul_prophet_arp,
  prophet: :soul_prophet_arp,
  moog: :moog_dilla_pocket,
  neo_pluck: :neo_soul_pluck,
  flylo: :flylo_fm_shimmer,
  ballad: :jazz_ballad_lead,
  gospel: :gospel_brass_lead,
  erykah: :erykah_dust_lead,
  watermelon: :watermelon_glass,
  soft: :soft_synth_lead,
  cs: :cs_lead,
  minimoog: :minimoog_lead,
  pluck: :neo_soul_pluck,
  glass: :glass_arp_lead,
  vapor: :vapor_lead,
  crystal: :glass_arp_lead,
  acid: :acid_pluck_lead,
  neon: :moog_ladder_lead
}.freeze

# Lush + experimental electronic cycles (SYNTH_CYCLE=1).
LUSH_PATCH_CYCLE_EP = {
  rhodes: %i[rhodes_mark1 rhodes_bleeding_edge rhodes_vintage_tape rhodes_cafe_warm rhodes_stage73 galaxy_ep1],
  moog: %i[rhodes_mark1 rhodes_vintage_tape rhodes_bleeding_edge galaxy_ep1],
  prophet: %i[rhodes_mark1 rhodes_cafe_warm rhodes_bleeding_edge galaxy_ep1 galaxy_ep2],
  blend: %i[rhodes_mark1 rhodes_bleeding_edge rhodes_vintage_tape rhodes_cafe_warm rhodes_stage73 galaxy_ep1 galaxy_ep2],
  glass: %i[dx7_bell_ep galaxy_ep2 rhodes_dx_blend celeste_dust],
  vapor: %i[rhodes_cafe_warm galaxy_ep1 ep_mark1_dark],
  crystal: %i[galaxy_ep2 dx_ep_glass vibes_mallet],
  ice: %i[rhodes_dx_blend galaxy_ep1 celeste_dust],
  neon: %i[rhodes_mark1 clav_neo_funk],
  pulse: %i[clav_neo_funk wurli_bite dx7_bell_ep]
}.freeze

LUSH_PATCH_CYCLE_WARM = {
  rhodes: %i[juno_chorus_wash prophet_6_warm tape_string_pad polysynth_soul memorymoon_pad string_orchestra],
  moog: %i[moog_model_d moog_sub37_pad moog_pad moog_bleeding_edge warm_analog_duo neon_ladder],
  prophet: %i[prophet_5_pad prophet_6_warm prophet_pad polysynth_soul juno_chorus_wash cs80_ensemble],
  blend: %i[prophet_5_pad moog_model_d prophet_6_warm moog_sub37_pad juno_chorus_wash polysynth_soul],
  glass: %i[glass_fm_pad crystal_pwm ice_string_pad],
  vapor: %i[vapor_supersaw prophet_rev2_bleeding juno_chorus_wash],
  crystal: %i[crystal_pwm glass_fm_pad pwm_sweep_pad],
  ice: %i[ice_string_pad solina_ensemble tape_string_pad],
  neon: %i[neon_ladder moog_bleeding_edge analog_hollow],
  pulse: %i[pwm_sweep_pad crystal_pwm analog_pad1]
}.freeze

LUSH_LEAD_VOICE_POOLS = {
  donuts: %i[mark1_soul_lead rhodes_lead_comp donuts_wurli_lead],
  soul_prophet: %i[soul_prophet_arp prophet_lead warm_prophet_hook big_lead_prophet5],
  prophet: %i[soul_prophet_arp prophet_lead warm_prophet_hook glasper_ep_lead],
  moog: %i[moog_dilla_pocket questlove_moog_lead minimoog_lead moog_ladder_lead],
  neo_pluck: %i[neo_soul_pluck dangelo_clav_lead rhodes_skank_lead],
  flylo: %i[flylo_fm_shimmer fm_lead_bell glass_arp_lead],
  ballad: %i[jazz_ballad_lead nord_stage_lead glasper_ep_lead soft_synth_lead],
  gospel: %i[gospel_brass_lead stevie_organ_lead],
  erykah: %i[erykah_dust_lead rhodes_lead_comp mark1_soul_lead],
  watermelon: %i[watermelon_glass nord_stage_lead glasper_ep_lead],
  soft: %i[soft_synth_lead nord_stage_lead rhodes_lead_comp],
  cs: %i[glasper_ep_lead soul_prophet_arp rhodes_lead_comp],
  minimoog: %i[minimoog_lead moog_ladder_lead questlove_moog_lead],
  pluck: %i[neo_soul_pluck dangelo_clav_lead],
  glass: %i[glass_arp_lead flylo_fm_shimmer fm_lead_bell],
  vapor: %i[vapor_lead supersaw_1 tame_wobble_lead],
  crystal: %i[glass_arp_lead fm_lead_bell],
  acid: %i[acid_pluck_lead moog_ladder_lead],
  neon: %i[moog_ladder_lead minimoog_lead acid_pluck_lead]
}.freeze

# Per-voice families — random cycle picks within these pools each render (SYNTH_CYCLE=1).
PATCH_CYCLE_EP = {
  rhodes: %i[
    rhodes_mark1 rhodes_stage73 rhodes_tine_wurli rhodes_dx_blend rhodes_bleeding_edge
    rhodes_vintage_tape rhodes_cafe_warm wurli_soul_bite clav_neo_funk dx7_bell_ep
    galaxy_ep1 galaxy_ep2 galaxy_ep_bleeding organ_drawbar organ_perc vibes_mallet celeste_dust
  ],
  moog: %i[
    rhodes_mark1 rhodes_stage73 rhodes_vintage_tape dx7_bell_ep galaxy_ep1 ep_mark1_dark
    clav_neo_funk wurli_soul_bite
  ],
  prophet: %i[
    rhodes_mark1 rhodes_stage73 rhodes_tine_wurli rhodes_cafe_warm galaxy_ep1 galaxy_ep2
    organ_drawbar dx_ep_glass vibes_mallet
  ],
  blend: %i[
    rhodes_mark1 rhodes_stage73 rhodes_tine_wurli rhodes_dx_blend rhodes_vintage_tape
    rhodes_cafe_warm wurli_soul_bite clav_neo_funk dx7_bell_ep galaxy_ep1 galaxy_ep2
    galaxy_ep_bleeding organ_drawbar organ_perc vibes_mallet soul_piano_tack
  ],
  glass: %i[dx7_bell_ep galaxy_ep2 rhodes_dx_blend celeste_dust],
  vapor: %i[rhodes_cafe_warm galaxy_ep1 ep_mark1_dark],
  crystal: %i[galaxy_ep2 dx_ep_glass vibes_mallet],
  ice: %i[rhodes_dx_blend galaxy_ep1 celeste_dust],
  neon: %i[rhodes_mark1 clav_neo_funk],
  pulse: %i[clav_neo_funk wurli_bite dx7_bell_ep]
}.freeze

PATCH_CYCLE_WARM = {
  rhodes: %i[
    juno_strings juno_chorus_wash solina_ensemble string_orchestra tape_string_pad
    prophet_6_warm slow_attack_pad cs80_ensemble pwm_sweep_pad analog_pad1 mellotron_flute_pad
    polysynth_soul memorymoon_pad warm_analog_duo
  ],
  moog: %i[
    moog_model_d moog_sub37_pad moog_pad moog_bleeding_edge prophet_rev2_bleeding
    warm_analog_duo analog_hollow analog_pad2 prophet_brass_wash neon_ladder
  ],
  prophet: %i[
    prophet_5_pad prophet_6_warm prophet_pad prophet_rev2_bleeding cs80_ensemble
    oberheim_pad pwm_sweep_pad polysynth_soul memorymoon_pad juno_chorus_wash
    analog_pad1 tape_string_pad
  ],
  blend: %i[
    prophet_5_pad moog_model_d prophet_6_warm moog_sub37_pad juno_strings juno_chorus_wash
    prophet_pad moog_pad cs80_ensemble solina_ensemble string_orchestra warm_analog_duo
    memorymoon_pad tape_string_pad polysynth_soul mellotron_flute_pad analog_hollow
    slow_attack_pad oberheim_pad
  ],
  glass: %i[glass_fm_pad crystal_pwm ice_string_pad],
  vapor: %i[vapor_supersaw prophet_rev2_bleeding juno_chorus_wash],
  crystal: %i[crystal_pwm glass_fm_pad pwm_sweep_pad],
  ice: %i[ice_string_pad solina_ensemble tape_string_pad],
  neon: %i[neon_ladder moog_bleeding_edge analog_hollow],
  pulse: %i[pwm_sweep_pad crystal_pwm analog_pad1]
}.freeze

LEAD_VOICE_POOLS = {
  donuts: %i[donuts_wurli_lead mark1_soul_lead wurli_soul_bite rhodes_skank_lead jupiter_superlead],
  soul_prophet: %i[soul_prophet_arp jupiter_superlead warm_prophet_hook prophet_bleeding_lead mono_poly_lead],
  prophet: %i[jupiter_superlead soul_prophet_arp warm_prophet_hook mono_poly_lead obxr_sync_lead],
  moog: %i[moog_dilla_pocket mono_poly_lead questlove_moog_lead minimoog_lead sh101_sequence],
  neo_pluck: %i[neo_soul_pluck dx7_glass_arp dangelo_clav_lead glass_arp_lead],
  flylo: %i[flylo_fm_shimmer dx7_glass_arp glass_arp_lead tame_wobble_lead jupiter_superlead],
  ballad: %i[jazz_ballad_lead cs80_brass_lead nord_stage_lead soft_synth_lead],
  gospel: %i[cs80_brass_lead gospel_brass_lead stevie_organ_lead jp8_brass_arp],
  erykah: %i[erykah_dust_lead portishead_dust_lead rhodes_lead_comp mark1_soul_lead],
  watermelon: %i[watermelon_glass nord_stage_lead dx7_glass_arp rhodes_lead_comp],
  soft: %i[soft_synth_lead jazz_ballad_lead nord_stage_lead rhodes_lead_comp],
  cs: %i[cs80_brass_lead cs_lead glasper_ep_lead soul_prophet_arp],
  minimoog: %i[minimoog_lead mono_poly_lead questlove_moog_lead moog_dilla_pocket],
  pluck: %i[neo_soul_pluck dx7_glass_arp dangelo_clav_lead glass_arp_lead],
  glass: %i[dx7_glass_arp glass_arp_lead flylo_fm_shimmer jupiter_superlead],
  vapor: %i[vapor_lead jupiter_superlead tame_wobble_lead obxr_sync_lead],
  crystal: %i[dx7_glass_arp glass_arp_lead crystal_scale_lead],
  acid: %i[acid_pluck_lead sh101_sequence mono_poly_lead moog_ladder_lead],
  neon: %i[obxr_sync_lead mono_poly_lead jupiter_superlead acid_pluck_lead]
}.freeze

PATCH_CYCLE_TEXTURE = %i[
  soft_synth_str shimmer_organ ethnic_flute kalimba_dust space_voice reverse_pad_ghost music_box
].freeze

PATCH_CYCLE_SCALE_LEAD = %i[
  scale_arp_rhodes scale_arp_prophet scale_arp_moog scale_arp_supersaw crystal_scale_lead
  jp8_brass_arp sh101_sequence dx7_glass_arp jupiter_superlead glass_arp_lead
  rhodes_lead_comp glasper_ep_lead soul_prophet_arp
].freeze

# Named lead-arp figures — tuned for lead register (louder/clearer than legacy pad arp).
LEAD_ARP_PRESETS = {
  donuts_shimmer: { style: :skip_up, subdiv: 8, gate: 0.66, vel: 0.48,
                    arp_styles: %i[skip_up euclidean quint_spread] },
  soul_wash:      { style: :updown, subdiv: 2, gate: 0.88, vel: 0.48,
                    arp_styles: %i[updown motif] },
  # Sparse chord-tone melody (quarter / half notes) — not dense random soup.
  melodic_soul:   { style: :motif, subdiv: 1, gate: 0.92, vel: 0.52,
                    arp_styles: %i[motif updown] },
  moog_funk:      { style: :up, subdiv: 4, gate: 0.7, vel: 0.54,
                    arp_styles: %i[up downup quint_spread] },
  prophet_glass:  { style: :pingpong, subdiv: 6, gate: 0.62, vel: 0.52,
                    arp_styles: %i[pingpong skip_up updown] },
  flylo_spiral:   { style: :spiral, subdiv: 8, gate: 0.58, vel: 0.46,
                    arp_styles: %i[spiral fibonacci random_walk] },
  neo_quartal:    { style: :quint_spread, subdiv: 6, gate: 0.68, vel: 0.46,
                    arp_styles: %i[quint_spread updown coltrane] },
  ballad_bloom:   { style: :updown, subdiv: 4, gate: 0.76, vel: 0.44,
                    arp_styles: %i[updown coltrane] },
  pocket_stab:    { style: :donda_stab, subdiv: 8, gate: 0.52, vel: 0.56,
                    arp_styles: %i[donda_stab skip_up euclidean] },
  erykah_dust:    { style: :euclidean, subdiv: 8, gate: 0.72, vel: 0.42,
                    arp_styles: %i[euclidean skip_up] },
  gospel_lift:    { style: :coltrane, subdiv: 6, gate: 0.64, vel: 0.5,
                    arp_styles: %i[coltrane up quint_spread] },
  # Experimental electronic figures (musical, not chaotic).
  glass_spin:     { style: :spiral, subdiv: 6, gate: 0.58, vel: 0.46,
                    arp_styles: %i[spiral quint_spread pingpong] },
  vapor_wave:     { style: :updown, subdiv: 4, gate: 0.7, vel: 0.44,
                    arp_styles: %i[updown flylo_wobble] },
  acid_run:       { style: :up, subdiv: 8, gate: 0.42, vel: 0.52,
                    arp_styles: %i[up skip_up euclidean] },
  crystal_scatter: { style: :fibonacci, subdiv: 6, gate: 0.55, vel: 0.45,
                     arp_styles: %i[fibonacci spiral skip_up] }
}.freeze

# Aggressive xlead arp figures — per-chord morph when LEAD_MORPH=1.
EXPERIMENTAL_LEAD_ARP_PRESETS = {
  hard_stab:     { style: :donda_stab, subdiv: 8, gate: 0.44, vel: 0.64,
                   arp_styles: %i[donda_stab euclidean flylo_wobble stutter burst] },
  flylo_spiral:  { style: :spiral, subdiv: 8, gate: 0.52, vel: 0.56,
                   arp_styles: %i[spiral fibonacci random_walk flylo_wobble ratchet] },
  glitch_walk:   { style: :random_walk, subdiv: 12, gate: 0.4, vel: 0.58,
                   arp_styles: %i[random_walk stutter ratchet euclidean burst] },
  prophet_saw:   { style: :pingpong, subdiv: 6, gate: 0.5, vel: 0.58,
                   arp_styles: %i[pingpong skip_up coltrane quint_spread] },
  moog_rip:      { style: :up, subdiv: 4, gate: 0.62, vel: 0.6,
                   arp_styles: %i[up downup quint_spread ratchet stutter] },
  shred_burst:   { style: :burst, subdiv: 8, gate: 0.38, vel: 0.66,
                   arp_styles: %i[burst stutter donda_stab flylo_wobble] },
  stutter_gate:  { style: :stutter, subdiv: 12, gate: 0.35, vel: 0.62,
                   arp_styles: %i[stutter ratchet euclidean skip_up burst] },
  ratchet_funk:  { style: :ratchet, subdiv: 6, gate: 0.48, vel: 0.64,
                   arp_styles: %i[ratchet updown coltrane burst flylo_wobble] }
}.freeze

PAD_TO_LEAD_ARP = {
  wash: :soul_wash, shimmer: :donuts_shimmer, pulse: :moog_funk, blend: :neo_quartal,
  duo: :prophet_glass, figure: :flylo_spiral, held: nil
}.freeze

def synth_patch_by_id(id)
  SYNTH_PATCH_BY_ID[id]
end

def galaxy_ep_available?
  File.exist?(patch_sf2_path(:galaxy))
end

def prefer_galaxy_ep(patch)
  return patch unless patch && galaxy_ep_available?
  return synth_patch_by_id(:galaxy_ep1) if %i[rhodes_mark1 rhodes_stage73 rhodes_tine_wurli].include?(patch[:id])
  patch
end

def pad_texture_enabled?
  ENV.fetch("PAD_TEXTURE", "0") == "1"
end

def experimental_leads_enabled?
  ENV.fetch("EXPERIMENTAL_LEADS", "1") != "0"
end

# Arp figure presets — PAD_ARP_MODE selects the lead-arp character; chord pads
# (EP/warm) always render held. Former per-layer routing (arp on Rhodes/Moog
# pads) moved to lead_arp.wav so pads stay lush and the figure sits up top.
PAD_ARP_LAYER_MODES = {
  held:   { ep: :held,    warm: :held },
  shimmer: { ep: :shimmer, warm: :held },
  pulse:  { ep: :held,    warm: :arp },
  blend:  { ep: :shimmer, warm: :arp },
  duo:    { ep: :arp,     warm: :arp },
  wash:   { ep: :held,    warm: :arp },
  figure: { ep: :arp,     warm: :held }
}.freeze

PAD_ARP_PRESETS = {
  ep_shimmer: { style: :skip_up, subdiv: 8, gate: 0.78, vel: 0.16,
                arp_styles: %i[skip_up euclidean quint_spread] },
  ep_figure:  { style: :fibonacci, subdiv: 6, gate: 0.74, vel: 0.22,
                arp_styles: %i[fibonacci spiral coltrane] },
  warm_pulse: { style: :updown, subdiv: 4, gate: 0.86, vel: 0.24,
                arp_styles: %i[updown pingpong] },
  warm_wash:  { style: :pingpong, subdiv: 3, gate: 0.9, vel: 0.28,
                arp_styles: %i[pingpong coltrane quint_spread] },
  warm_moog:  { style: :up, subdiv: 4, gate: 0.88, vel: 0.26,
                arp_styles: %i[up downup quint_spread] }
}.freeze

def pad_arp_mode
  raw = ENV["PAD_ARP_MODE"]&.downcase
  sym = raw&.to_sym
  return sym if sym && PAD_ARP_LAYER_MODES.key?(sym)
  return :blend if ENV.fetch("PAD_CHORD_ARP", "0") != "0"
  fallback = (ENV["PAD_ARP"] || "held").to_s.downcase.to_sym
  PAD_ARP_LAYER_MODES.key?(fallback) ? fallback : :held
end

def lead_arp_mode
  raw = ENV["LEAD_ARP_MODE"]&.downcase
  sym = raw&.to_sym
  return sym if sym && LEAD_ARP_PRESETS.key?(sym)
  PAD_TO_LEAD_ARP[pad_arp_mode]
end

def lead_arp_preset_key
  lead_arp_mode ||
    (lead_arp_preset_for_pad_mode_legacy if pad_arp_mode != :held)
end

# Legacy PAD_ARP_MODE → PAD_ARP_PRESETS key (fallback when LEAD_ARP_MODE unset).
def lead_arp_preset_for_pad_mode_legacy(mode = nil)
  mode ||= pad_arp_mode
  case mode
  when :held then nil
  when :shimmer then :ep_shimmer
  when :pulse then :warm_pulse
  when :blend then :warm_pulse
  when :duo then :ep_figure
  when :wash then :warm_wash
  when :figure then :ep_figure
  else :warm_pulse
  end
end

def synth_cycle_enabled?
  ENV.fetch("SYNTH_CYCLE", "1") != "0"
end

def synth_morph_enabled?
  return false if ENV["SYNTH_MORPH"] == "0"
  return true if ENV["SYNTH_MORPH"] == "1"
  ENV["STREAM_SOUL"] == "1" || stream_iterate_enabled?
end

def pad_synth_cycle_enabled?
  synth_cycle_enabled? || synth_morph_enabled?
end

def morph_voice_at(event_idx)
  voices = PAD_VOICE_MORPH_VOICES
  base = ENV["PAD_VOICE"]&.downcase&.to_sym
  offset = voices.index(base) || 0
  voices[(offset + event_idx) % voices.length]
end

def morph_patch_pool(role:, voice:)
  pool = role == :ep ? ep_patch_pool(voice) : warm_patch_pool(voice)
  return pool unless role == :ep && synth_morph_enabled?
  Array(pool).reject { |id| id.to_s.start_with?("galaxy_") }
end

def morph_patch_for_chord(event_idx, role:)
  voice = morph_voice_at(event_idx)
  pool = morph_patch_pool(role: role, voice: voice)
  preset = PAD_VOICE_PRESETS[voice] || PAD_VOICE_PRESETS[:moog]
  fallback_id = role == :ep ? preset[:ep] : preset[:warm]
  pick_patch_from_pool(pool, seed: event_idx * 311 + (role == :ep ? 0 : 17)) ||
    (fallback_id && synth_patch_by_id(fallback_id))
end

def lead_morph_enabled?
  return false if ENV["LEAD_MORPH"] == "0"
  return true if ENV["LEAD_MORPH"] == "1"
  synth_morph_enabled?
end

def morph_lead_voice_at(event_idx)
  voices = LEAD_MORPH_VOICES
  base = (ENV["LEAD_MORPH_VOICE"] || ENV["LEAD_VOICE"])&.downcase&.to_sym
  offset = voices.index(base) || 0
  voices[(offset + event_idx) % voices.length]
end

def morph_lead_patch_for_chord(event_idx)
  voice = morph_lead_voice_at(event_idx)
  pool = Array(MORPH_LEAD_PATCH_POOL[voice] || MORPH_LEAD_PATCH_POOL[:hard])
              .reject { |id| (p = synth_patch_by_id(id)) && p[:sf2] != :default }
  pick_patch_from_pool(pool, seed: event_idx * 503 + 91) || synth_patch_by_id(:saw_lead)
end

def morph_lead_arp_cfg_for_chord(event_idx, patch)
  preset_key = MORPH_LEAD_ARP_CYCLE[event_idx % MORPH_LEAD_ARP_CYCLE.length]
  base = EXPERIMENTAL_LEAD_ARP_PRESETS[preset_key]&.dup ||
         LEAD_ARP_PRESETS[:flylo_spiral]&.dup ||
         { style: :spiral, subdiv: 8, gate: 0.52, vel: 0.56, arp_styles: %i[spiral flylo_wobble] }
  styles = (base[:arp_styles] || []) + arp_styles_for_patch(patch, base[:style])
  base.merge(arp_styles: styles.uniq)
end

def patch_cycle_seed(base = 0)
  base + (@render_seed || 0) + (@stream_iterate_count || 0) * 7919 + Process.pid
end

def pick_patch_from_pool(pool, seed: 0)
  ids = Array(pool).compact.uniq
  return nil if ids.empty?
  rng = Random.new(patch_cycle_seed(seed))
  synth_patch_by_id(ids[rng.rand(ids.length)])
end

def lush_synth_pools?
  ENV.fetch("LUSH_SYNTH", "1") != "0"
end

def ep_patch_pool(voice)
  lush_synth_pools? ? (LUSH_PATCH_CYCLE_EP[voice] || PATCH_CYCLE_EP[voice]) : PATCH_CYCLE_EP[voice]
end

def warm_patch_pool(voice)
  lush_synth_pools? ? (LUSH_PATCH_CYCLE_WARM[voice] || PATCH_CYCLE_WARM[voice]) : PATCH_CYCLE_WARM[voice]
end

def lead_patch_pool(voice)
  lush_synth_pools? ? (LUSH_LEAD_VOICE_POOLS[voice] || LEAD_VOICE_POOLS[voice]) : LEAD_VOICE_POOLS[voice]
end

def apply_lead_voice_preset!(seed: 0)
  voice = ENV["LEAD_VOICE"]&.downcase&.to_sym
  return unless voice
  if synth_cycle_enabled? && lead_patch_pool(voice)
    @render_lead_patch = pick_patch_from_pool(lead_patch_pool(voice), seed: seed + 41) ||
                        synth_patch_by_id(LEAD_VOICE_PRESETS[voice])
  else
    id = LEAD_VOICE_PRESETS[voice]
    @render_lead_patch = synth_patch_by_id(id) if id
  end
end

def pad_arp_cfg_for(patch, role:, mode: nil)
  mode ||= pad_arp_mode
  patch_arp = patch&.dig(:midi_arp)
  preset = lead_arp_preset_for_pad_mode(mode) ||
           (role == :warm ? :warm_pulse : :ep_shimmer)
  preset = :warm_moog if role == :warm && patch&.dig(:id).to_s.start_with?("moog")
  base = PAD_ARP_PRESETS[preset].dup
  base.merge(patch_arp || {}).merge(arp_styles: patch&.dig(:arp_styles) || base[:arp_styles])
end

def apply_pad_voice_preset!(seed: 0)
  voice = ENV["PAD_VOICE"]&.downcase&.to_sym
  # Multi-layer stacks pin patches from PAD_LAYER_STACKS (rendered together).
  if voice && PAD_LAYER_STACKS[voice] && ENV.fetch("PAD_LAYERS", "1") != "0"
    stack = PAD_LAYER_STACKS[voice]
    @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(stack[0][:id])) if stack[0]
    @render_warm_patch = synth_patch_by_id(stack[1][:id]) if stack[1]
    @render_warm2_patch = synth_patch_by_id(stack[2][:id]) if stack[2]
    @render_texture_patch = synth_patch_by_id(stack[3][:id]) if stack[3]
    @render_skip_warm_pad = false
    return
  end
  if voice && PAD_VOICE_PRESETS[voice]
    preset = PAD_VOICE_PRESETS[voice]
    if pad_synth_cycle_enabled? && !PAD_LAYER_STACKS.key?(voice)
      ep_pool = ep_patch_pool(voice)
      warm_pool = warm_patch_pool(voice)
      if ep_pool&.any?
        @render_ep_patch = prefer_galaxy_ep(pick_patch_from_pool(ep_pool, seed: seed) ||
                                            synth_patch_by_id(preset[:ep]))
      elsif preset[:ep]
        @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(preset[:ep]))
      end
      if warm_pool&.any?
        @render_warm_patch = pick_patch_from_pool(warm_pool, seed: seed + 17)
        @render_skip_warm_pad = @render_warm_patch.nil?
      elsif preset[:warm]
        @render_warm_patch = synth_patch_by_id(preset[:warm])
        @render_skip_warm_pad = false
      else
        @render_skip_warm_pad = true
      end
      @render_warm2_patch = synth_patch_by_id(preset[:warm2]) if preset[:warm2]
    else
      @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(preset[:ep])) if preset[:ep]
      @render_warm_patch = synth_patch_by_id(preset[:warm]) if preset[:warm]
      @render_warm2_patch = synth_patch_by_id(preset[:warm2]) if preset[:warm2]
      @render_skip_warm_pad = preset[:warm].nil?
    end
    return
  end
  # Soul defaults: Rhodes + Moog + Prophet stack
  return if ENV["CREEPY_PATCHES"] == "1"
  @render_ep_patch = prefer_galaxy_ep(synth_patch_by_id(:rhodes_cafe_warm))
  @render_warm_patch = synth_patch_by_id(:moog_model_d)
  @render_warm2_patch = synth_patch_by_id(:prophet_5_pad)
  @render_skip_warm_pad = false
end

# Soulful EP/pad palette — no voices, supersaws, music boxes, or horror textures.
BEAUTIFUL_PATCH_IDS = {
  ep: PATCH_CYCLE_EP.values.flatten.uniq,
  warm: PATCH_CYCLE_WARM.values.flatten.uniq,
  scale_lead: PATCH_CYCLE_SCALE_LEAD,
  lead: LEAD_VOICE_POOLS.values.flatten.uniq,
  texture: PATCH_CYCLE_TEXTURE,
  native: %i[
    native_rhodes native_rhodes_bleeding native_juno native_prophet native_moog
    native_fm_glass native_organ native_warm_pad native_string native_pwm
  ]
}.freeze

# Experimental but musical leads — Flylo/Prophet/Moog/FM; not horror/novelty.
EXPERIMENTAL_LEAD_IDS = {
  lead: (LEAD_VOICE_POOLS.values.flatten + %i[
    jupiter_superlead obxr_sync_lead cs80_brass_lead mono_poly_lead dx7_glass_arp
    fifths_lead saw_lead supersaw_1 supersaw_2 prophet_bleeding_lead tame_wobble_lead
  ]).uniq,
  scale_lead: PATCH_CYCLE_SCALE_LEAD
}.freeze

CREEPY_PATCH_IDS = %i[
  space_voice reverse_pad_ghost voice_lead whistle_hook charang_bite supersaw_1 supersaw_2
  supersaw_3 scale_arp_supersaw scale_arp_prophet prophet_bleeding_lead music_box fm_lead_bell
  dist_guitar banjo_pluck koto_pluck brass_synth square_lead ethnic_flute kalimba_dust
  choir_aahs voice_oohs bowed_glass harpsi_pluck
].freeze

def lead_patch_allowlist(role)
  return nil if ENV["CREEPY_PATCHES"] == "1"
  base = BEAUTIFUL_PATCH_IDS[role] || []
  if experimental_leads_enabled? && EXPERIMENTAL_LEAD_IDS[role]
    (base + EXPERIMENTAL_LEAD_IDS[role]).uniq
  else
    base
  end
end

def weighted_patch_pick(role, seed: nil, soulful: true)
  pool = SYNTH_PATCH_BY_ROLE.fetch(role, [])
  return nil if pool.empty?
  if soulful && ENV["CREEPY_PATCHES"] != "1"
    allowed = %i[lead scale_lead].include?(role) ? lead_patch_allowlist(role) : BEAUTIFUL_PATCH_IDS[role]
    if allowed&.any?
      pool = pool.select { |p| allowed.include?(p[:id]) }
      pool = SYNTH_PATCH_BY_ROLE.fetch(role, []).select { |p| allowed.include?(p[:id]) } if pool.empty?
    end
    pool = pool.reject { |p| CREEPY_PATCH_IDS.include?(p[:id]) }
  end
  return nil if pool.empty?
  rng = Random.new(seed || @render_seed || rand(1_000_000))
  total = pool.sum { |p| p[:weight] || 1.0 }
  roll = rng.rand * total
  pool.each do |patch|
    roll -= (patch[:weight] || 1.0)
    return patch if roll <= 0
  end
  pool.last
end

def pick_synth_patches!(cfg, bar: 0, n_bars: nil)
  seed = (cfg[:track].to_s.hash.abs % 100_000) + (@render_seed || 0) +
         (pad_synth_cycle_enabled? ? (@stream_iterate_count || 0) * 997 + bar * 13 : 0)
  @render_skip_warm_pad = false
  roles = nil
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    section = @composition_session.section_at(bar)
    roles = @composition_session.ensemble_roles(section)
  end
  pick_role = ->(role) { roles.nil? || roles.include?(role) }
  if pick_role.call(:ep) || pick_role.call(:warm)
    apply_pad_voice_preset!(seed: seed)
  end
  unless ENV["PAD_VOICE"] || ENV["CREEPY_PATCHES"] == "1"
    @render_ep_patch = weighted_patch_pick(:ep, seed: seed) if pick_role.call(:ep) && !@render_ep_patch
    @render_warm_patch = weighted_patch_pick(:warm, seed: seed + 17) if pick_role.call(:warm) && !@render_warm_patch
  end
  @render_texture_patch = nil
  if pad_texture_enabled? && pick_role.call(:texture)
    @render_texture_patch = weighted_patch_pick(:texture, seed: seed + 29)
  end
  apply_lead_voice_preset!(seed: seed) if ENV["LEAD_VOICE"] && !ENV["LEAD_VOICE"].empty?
  @render_lead_patch = weighted_patch_pick(:lead, seed: seed + 41) if pick_role.call(:lead) && !@render_lead_patch
  if pick_role.call(:scale_lead)
    @render_scale_lead_patch = weighted_patch_pick(:scale_lead, seed: seed + 79) ||
                               weighted_patch_pick(:lead, seed: seed + 79)
  end
  voice = ENV["PAD_VOICE"]&.downcase
  native_id = case voice
              when "moog" then :native_moog
              when "prophet" then :native_prophet
              when "rhodes", "blend", nil then :native_rhodes
              else nil
              end
  @render_native_patch = (native_id && synth_patch_by_id(native_id)) ||
                         weighted_patch_pick(:native, seed: seed + 53)
  @render_ep_patch ||= weighted_patch_pick(:ep, seed: seed)
  @render_warm_patch ||= weighted_patch_pick(:warm, seed: seed + 17)
  @render_lead_patch ||= weighted_patch_pick(:lead, seed: seed + 41)
  @render_scale_lead_patch ||= weighted_patch_pick(:scale_lead, seed: seed + 79) ||
                               weighted_patch_pick(:lead, seed: seed + 79)
  @render_arp_style = (@render_lead_patch&.dig(:arp_styles) || [:updown]).sample(random: Random.new(seed + 67))
  @render_scale_arp_style = (@render_scale_lead_patch&.dig(:arp_styles) || [:updown]).sample(random: Random.new(seed + 83))
end

def patch_sf2_path(sf2_key)
  case sf2_key
  when :galaxy
    File.join(File.expand_path("~/.cache/dilla-soundfonts"), "galaxy-electric-pianos.sf2")
  when :supersaw
    File.join(File.expand_path("~/.cache/dilla-soundfonts"), "supersaw-collection.sf2")
  else
    pad_soundfont_path
  end
end

def patch_voice_for(patch)
  return nil unless patch
  sf2 = patch[:sf2]
  path = if sf2 == :galaxy || sf2 == :supersaw
           p = patch_sf2_path(sf2)
           File.exist?(p) ? p : pad_soundfont_path
         else
           pad_soundfont_path
         end
  { sf2: path, bank: patch[:bank], program: patch[:program], patch: patch }
end

RADIO_BERGEN_SONIC_PATH = File.expand_path("../audio/radio_bergen_sonic.yml", ROOT).freeze
RADIO_BERGEN_MANIFEST_PATH = File.expand_path("../audio/radio_bergen_tracks.yml", ROOT).freeze

# Study playlist.brgen.no manifest → sonic learnings (also: ruby dilla.rb radio-bergen-study).
module RadioBergenStudy
  AUDIO_ROOT = File.expand_path("../audio", ROOT).freeze

  ARTIST_AFFINITY = {
    /j dilla/i => { producer: "dilla", performer: "yancey", groove_dna: "donuts",
                    dilla_track: "maj7_minor_cycle", sonic_key: "dilla_timeless", bpm: 86..92 },
    /slum village/i => { producer: "dilla", performer: "questlove", groove_dna: "donuts",
                         dilla_track: "neo_soul_pocket", sonic_key: "slum_players", bpm: 90..96 },
    /flying lotus/i => { producer: "flylo", performer: "glasper", groove_dna: "wonky",
                         dilla_track: "quartal_west_coast", sonic_key: "flylo_camel", bpm: 82..88 },
    /madlib/i => { producer: "madlib", performer: "karriem_riggins", groove_dna: "dust",
                   dilla_track: "minor_triad_walk", sonic_key: "madlib_eye", bpm: 92..98 },
    /samiyam/i => { producer: "dilla", performer: "yancey", groove_dna: "donuts",
                    dilla_track: "minor_iv_loop", sonic_key: "samiyam_rounded", bpm: 94..98 },
    /jay electronica/i => { producer: "dilla", performer: "yancey", groove_dna: "donuts",
                            dilla_track: "warm_minor_arc", sonic_key: "dilla_timeless", bpm: 84..90 },
    /afta-?1/i => { producer: "dilla", performer: "chris_dave", groove_dna: "donuts",
                    dilla_track: "slash_neo_soul", sonic_key: "slum_players", bpm: 88..94 },
    /chase swayze/i => { producer: "dilla", performer: "yancey", groove_dna: "donuts",
                         dilla_track: "minor_turnaround", sonic_key: "dilla_timeless", bpm: 86..92 },
    /akmd|mike t|angelo reira|jan hakim|haisam|johann/i => {
      producer: "bergen", performer: "yancey", groove_dna: "donuts",
      dilla_track: "erykah_minor", sonic_key: "dilla_timeless", bpm: 84..90,
      mix: "akmd_lofi_mastering"
    },
    /mochi|itoh/i => { producer: "flylo", performer: "glasper", groove_dna: "wonky",
                       dilla_track: "modal_safe", sonic_key: "flylo_camel", bpm: 120..128 }
  }.freeze

  module_function

  def load_manifest
    YAML.safe_load(File.read(RADIO_BERGEN_MANIFEST_PATH), permitted_classes: [Symbol], aliases: true) || {}
  end

  def catalog_rows(manifest = load_manifest)
    local = Array(manifest["local_mp3"]).map do |row|
      { artist: row["artist"].to_s, title: row["title"].to_s, source: "local_mp3",
        src: row["src"].to_s, youtube_id: nil }
    end
    youtube = Array(manifest.dig("external_reference", "youtube")).map do |row|
      { artist: row["artist"].to_s, title: row["title"].to_s, source: "youtube_reference",
        src: nil, youtube_id: row["id"].to_s, start: row["start"] }
    end
    local + youtube
  end

  def affinity_for(artist)
    ARTIST_AFFINITY.each { |pattern, profile| return profile if artist.match?(pattern) }
    { producer: "dilla", performer: "yancey", groove_dna: "donuts",
      dilla_track: "maj7_minor_cycle", sonic_key: "dilla_timeless", bpm: 86..92 }
  end

  def slug(artist, title)
    "#{artist}-#{title}".downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
  end

  def analyze_audio(path)
    return nil unless path && File.file?(path)
    return nil unless system("which", "ffprobe", out: File::NULL, err: File::NULL)

    duration_out, = Open3.capture2(
      "ffprobe", "-v", "error", "-show_entries", "format=duration",
      "-of", "default=noprint_wrappers=1:nokey=1", path
    )
    duration = duration_out.to_f
    return { duration_seconds: duration.round(2) } if duration <= 0

    stats, = Open3.capture2(
      "ffmpeg", "-hide_banner", "-nostats", "-i", path,
      "-af", "astats=metadata=1:reset=1,ametadata=print:file=-",
      "-f", "null", "-", err: File::NULL
    )
    rms = stats.scan(/RMS level dB:\s*([-\d.]+)/).flatten.map(&:to_f)
    peak = stats.scan(/Peak level dB:\s*([-\d.]+)/).flatten.map(&:to_f)
    {
      duration_seconds: duration.round(2),
      rms_db: rms.empty? ? nil : (rms.sum / rms.length).round(2),
      peak_db: peak.empty? ? nil : peak.max.round(2)
    }
  rescue StandardError
    nil
  end

  def study!(audio_root: nil)
    manifest = load_manifest
    rows = catalog_rows(manifest)
    studied = rows.map do |row|
      aff = affinity_for(row[:artist])
      audio_path = resolve_local_path(row, audio_root: audio_root)
      analysis = analyze_audio(audio_path)
      {
        id: slug(row[:artist], row[:title]), artist: row[:artist], title: row[:title],
        source: row[:source], youtube_id: row[:youtube_id], local_src: row[:src],
        # Keep generated study data portable; the resolved path can point into a
        # developer's local audio cache outside this repository.
        audio_analyzed: audio_path ? row[:src] : nil, analysis: analysis,
        learnings: {
          producer: aff[:producer], performer: aff[:performer], groove_dna: aff[:groove_dna],
          dilla_track: aff[:dilla_track], sonic_key: aff[:sonic_key],
          bpm_range: aff[:bpm] ? "#{aff[:bpm].begin}-#{aff[:bpm].end}" : nil, mix: aff[:mix]
        }.compact
      }
    end

    weights = Hash.new(0)
    studied.each do |row|
      track = row.dig(:learnings, :dilla_track)
      weights[track] += 1 if track
    end
    studied.select { |r| r[:source] == "local_mp3" }.each do |row|
      track = row.dig(:learnings, :dilla_track)
      weights[track] += 1 if track
    end

    {
      "meta" => {
        "source" => "playlist.brgen.no", "manifest" => RADIO_BERGEN_MANIFEST_PATH,
        "studied_at" => Time.now.utc.iso8601, "track_count" => studied.length,
        "local_count" => studied.count { |r| r[:source] == "local_mp3" },
        "youtube_count" => studied.count { |r| r[:source] == "youtube_reference" },
        "policy" => manifest.dig("external_reference", "policy"),
        "note" => "Reference metadata + optional local ffprobe analysis. YouTube rows are lineage only until rights review."
      },
      "artist_counts" => studied.group_by { |r| r[:artist] }.transform_values(&:length)
                                .sort_by { |_, c| -c }.to_h,
      "playlist_tracks" => studied,
      "stream_rotation_weights" => weights.sort_by { |_, c| -c }.to_h,
      "stream_env_defaults" => INLINE_RADIO_BERGEN_LEARNINGS["stream_env_defaults"],
      "mix_notes" => [
        "AKMD local_mp3 rows use pub2 lofi mastering chain (60Hz HPF, 11.5kHz LPF, 80/200Hz boosts, soft clip).",
        "Playlist rotation is Dilla/Slum/FlyLo weighted — bias stream TRACK toward stream_rotation_weights.",
        "Bergen local artists → erykah_minor / warm pad wash; beat references → mapped producer DNA.",
        "Never autoplay YouTube in production without rights review — manifest is reference_only_until_rights_review."
      ],
      "sonic_profiles" => INLINE_RADIO_BERGEN_LEARNINGS["sonic_profiles"]
    }
  end


  AUDIO_SEARCH_ROOTS = [
    File.expand_path("../../../../pub2", AUDIO_ROOT),
    File.expand_path("../../../../pub3/.index.html", AUDIO_ROOT),
    File.expand_path("../../../pub2/public", AUDIO_ROOT),
    File.expand_path("../../public", AUDIO_ROOT)
  ].freeze

  LOCAL_NAME_ALIASES = {
  "/audio/akmd/akmd-stailings.mp3" => %w[akmd-stailings.mp3],
  "/audio/akmd/akmd_mike_t-alt_kan_skje.mp3" => %w[akmd_mike_t-alt_kan_skje.mp3 mike_t_and_johann-alt_kan_skje.mp3],
  "/audio/akmd/akmd_mike_t_jan_hakim-diverse.mp3" => %w[akmd_mike_t_jan_hakim-diverse.mp3],
  "/audio/akmd/angelo_reira_and_johann-sandviken_hotell_a.mp3" => %w[angelo_reira_and_johann-sandviken_hotell_a.mp3],
  "/audio/akmd/angelo_reira_and_johann-sandviken_hotell_b.mp3" => %w[angelo_reira_and_johann-sandviken_hotell_b.mp3],
  "/audio/akmd/chase_swayze-traffic.mp3" => %w[chase_swayze-traffic.mp3 chase_swayze-underated.mp3],
  "/audio/akmd/haisam_and_johann-pb1.mp3" => %w[haisam_and_johann-pb1.mp3],
  "/audio/akmd/jan_hakim_and_johann-stailings_a.mp3" => %w[jan_hakim_and_johann-stailings_a.mp3],
  "/audio/akmd/mike_t_jr-rauingar.mp3" => %w[mike_t_jr-rauingar.mp3 johann-rauingar.mp3]
}.freeze

  TRACK_DOSSIERS = {
  "j_dilla_microphone_master" => {
    bpm: 90, key: "Fm / Ab", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "MPC3000 swing ~57%; kick anchors 1 + late 3 (steps 0,6,10); snare 4/12 with early push; 8th-note hats with lazy upbeats; ghost snares on 2/10.",
    texture: "Dusty vinyl crackle, low-passed sample chop, warm sub; Donuts-era mono-stacked sample + live kit hybrid.",
    harmony: "Minor 7 → IV → bVII loop; sample-led melody with horn stab punctuation.",
    mix: "Soft clip + gentle compression; hats sit behind sample; kick/sub unified ~80–120 Hz.",
    dilla_engine: { track: "maj7_minor_cycle", performer: "yancey", kicks: "1", speak: "0" }
  },
  "j_dilla_in_space" => {
    bpm: 88, key: "Dm", drum_preset: :dilla_drunk, groove_dna: "donuts",
    drums: "Sparse pocket; kick drift on 0,3,6,13; snare 4/12 + ghost 7; hats staggered 16ths with wide humanize.",
    texture: "Spacey reverb tail on sample; filtered noise bed; minimal low end until hook.",
    harmony: "Two-chord hypnosis (Ebm7–Bbm7 feel); modal vamps with pitch-bent sample.",
    mix: "Wide stereo sample, dry center kick; high shelf rolled ~9 kHz.",
    dilla_engine: { track: "two_chord_hypnosis", performer: "yancey" }
  },
  "j_dilla_timeless" => {
    bpm: 86, key: "Fm9", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Canonical Dilla swing; kick 0,6,10; snare 4/12 early; 8th hats; occasional open hat on 14.",
    texture: "Timeless sample warmth, vinyl noise, bass shelf +9 dB; pad lowpass ~3.4 kHz.",
    harmony: "Fm9–Dbmaj9–Cm9 cycle; melody chop on 5th/9th tones.",
    mix: "Donuts lowpass warmth; integrated ~-19 LUFS feel; never harsh top.",
    dilla_engine: { track: "maj7_minor_cycle", performer: "yancey", sonic_key: "dilla_timeless" }
  },
  "afta_1_due_time" => {
    bpm: 91, key: "Bb", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Neo-soul slash grid; kick syncopated on 0,4,8; snare 4/12; clap layer; shaker on off-16ths.",
    texture: "Clean but swung; Rhodes-like midrange; round bass.",
    harmony: "Slash voicings Dm7/F–Fmaj9/A–Gm7/Bb; so-what voicing family.",
    mix: "Chris Dave pocket — drums slightly late, bass ahead.",
    dilla_engine: { track: "slash_neo_soul", performer: "chris_dave" }
  },
  "flying_lotus_massage_situation" => {
    bpm: 85, key: "Cm", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Broken 16ths; kicks on 0,5,8,13; snares displaced 2,6,10,15; heavy ghost layer.",
    texture: "Glitch clicks, sidechain pump, stereo pan on hats; sub drops out for air.",
    harmony: "Quartal stacks; chromatic mediant drift.",
    mix: "Jazz haze sidechain; master lowpass ~3.6 kHz; vinyl 0.08.",
    dilla_engine: { track: "quartal_west_coast", performer: "glasper", groove_dna: "wonky" }
  },
  "madlib_eye" => {
    bpm: 96, key: "Dm", drum_preset: :sp303, groove_dna: "dust",
    drums: "SP-303 grit; straight-ish 8th hats; kick four-on-floor variant 0,4,8,12; snare 4/12.",
    texture: "Bitcrush 35% mix; vinyl 0.10; accordion/sample midrange dominant.",
    harmony: "Minor triad walk Dm–Gm–Am; simple loop hypnosis.",
    mix: "Dusty, mid-forward; limited highs; SP-1200 punch.",
    dilla_engine: { track: "minor_triad_walk", performer: "karriem_riggins" }
  },
  "slum_village_players" => {
    bpm: 93, key: "Dm", drum_preset: :mpc3000, groove_dna: "donuts",
    drums: "Players pocket: kick 0,6,10; snare 4/12; 8th hats; ghost 2/9; MPC swing 62%.",
    texture: "Neo-soul clean punch; bass sustain 0.92 bar; pad lowpass 3.3 kHz.",
    harmony: "Dm7–Eb7–Gm7–Am7; measured players progression.",
    mix: "Slum pocket — snare slightly early, hats late.",
    dilla_engine: { track: "neo_soul_pocket", performer: "questlove", sonic_key: "slum_players" }
  },
  "jay_electronica_exhibit_a" => {
    bpm: 86, key: "Bb / Dm", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Slow drunk swing; kick 0,3,6,10,13; snare 4/7/12; sparse hats.",
    texture: "Cinematic strings sample + warm minor arc; vinyl 0.07.",
    harmony: "Dm7–Cm7–Fmaj9–Gm7 warm minor arc.",
    mix: "Wide sample, centered drums; long release tails.",
    dilla_engine: { track: "warm_minor_arc", performer: "yancey" }
  },
  "slum_village_la_la_instrumental" => {
    bpm: 94, key: "F minor", drum_preset: :dilla_drunk, groove_dna: "donuts",
    drums: "Donda-style drunk grid; kick 0,3,6,10,13; dense hat 16ths.",
    texture: "Dark minor loop; heavy bass shelf.",
    harmony: "Fm7–Abmaj7–Bbm7 loop.",
    dilla_engine: { track: "donda_minor", performer: "questlove" }
  },
  "slum_village_get_it_together" => {
    bpm: 92, key: "C minor", drum_preset: :mpc3000, groove_dna: "donuts",
    drums: "Classic boom-bap; kick four-on; snare 4/12; clap double.",
    texture: "Soul sample flip; filtered intro.",
    harmony: "Cm9–Fm7–Bbmaj7–Ebmaj9 neo-IV cycle.",
    dilla_engine: { track: "neo_iv_cycle", performer: "questlove" }
  },
  "slum_village_fantastic" => {
    bpm: 95, key: "Ab", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Upbeat swing; kick syncopated; open hat accents.",
    texture: "Bright soul sample; less vinyl than Donuts.",
    harmony: "Maj7 minor cycle variant.",
    dilla_engine: { track: "maj7_minor_cycle", performer: "questlove" }
  },
  "flying_lotus_me_yesterday_corded" => {
    bpm: 83, key: "D", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Broken beat; irregular kick; snare clusters; glitch percussion.",
    texture: "Chopped vocal fragments; heavy stereo motion.",
    harmony: "Suspended ballad / chromatic drift.",
    dilla_engine: { track: "suspended_ballad", performer: "glasper" }
  },
  "flying_lotus_camel" => {
    bpm: 84, key: "C", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Off-kilter 16ths; kick 0,5,8,13; snare 2,6,10,15; sidechain pump.",
    texture: "Quartal jazz haze; sidechain; vinyl 0.08; pan on arps.",
    harmony: "Cmaj9–Am9–Fmaj9–G6 quartal west coast.",
    mix: "FlyLo camel preset — master LP 3.6 kHz.",
    dilla_engine: { track: "quartal_west_coast", performer: "glasper", sonic_key: "flylo_camel" }
  },
  "flying_lotus_golden_diva" => {
    bpm: 82, key: "Eb", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Slow loose pocket; minimal kick; brush-like hats.",
    texture: "Glasper quartal keys; long reverb.",
    harmony: "Ebmaj9–Cm9–Abmaj9–Bb6.",
    dilla_engine: { track: "glasper_quartal", performer: "glasper" }
  },
  "slum_village_worlds_full_of_sadness" => {
    bpm: 88, key: "G minor", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Melancholy swing; sparse kicks; rimshot ghosts.",
    texture: "Waterfall pad wash; minor soul loop.",
    harmony: "Gm9–Cm7–Fmaj9–Bbm7 watermelon turn.",
    dilla_engine: { track: "watermelon_turn", performer: "questlove" }
  },
  "a_mochi_takaaki_itoh_sarria_s_mind" => {
    bpm: 124, key: "D mixolydian", drum_preset: :mpc3000, groove_dna: "wonky",
    drums: "Techno-influenced 4/4 with swing overlay; driving hats.",
    texture: "Modal safe loop; cleaner digital top.",
    harmony: "Dmaj9–Cm9–Gmaj9–A7 modal safe.",
    dilla_engine: { track: "modal_safe", performer: "glasper", bpm: 124 }
  },
  "samiyam_rounded" => {
    bpm: 96, key: "Dm", drum_preset: :sp303, groove_dna: "donuts",
    drums: "Dry modern punch; kick 0,4,8,12; tight snare; minimal ghosts.",
    texture: "Rounded sub; low vinyl; modern dry punch texture.",
    harmony: "Dm9–Em7–Ebmaj7–Dm.",
    dilla_engine: { track: "minor_iv_loop", performer: "yancey", sonic_key: "samiyam_rounded" }
  },
  "chase_swayze_traffic" => {
    bpm: 88, key: "G", drum_preset: :mpc3000, groove_dna: "donuts",
    drums: "Minor turnaround grid; kick 0,6,10; snare 4/12; steady 8th hats.",
    texture: "Bergen night rain pad; vinyl 0.07; pad LP 3.3 kHz.",
    harmony: "Bm7–Bm7–Cmaj9–Em7.",
    dilla_engine: { track: "minor_turnaround", performer: "yancey" }
  },
  "chase_swayze_underrated" => {
    bpm: 90, key: "F minor", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Slightly drunk hat pattern; kick syncopation.",
    texture: "Lo-fi crunch; AKMD-family mastering.",
    harmony: "Minor IV loop.",
    dilla_engine: { track: "minor_iv_loop", performer: "yancey" }
  },
  "akmd_stailings" => {
    bpm: 87, key: "F# minor", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Bergen lofi grid; kick 0,4,8,12 with humanize; swung hats; sparse clap.",
    texture: "AKMD mastering chain; night-rain pad; vinyl 0.08; LP 3.1 kHz.",
    harmony: "erykah_minor bill-evans voicing.",
    dilla_engine: { track: "erykah_minor", performer: "yancey", mix: "akmd_lofi_mastering" }
  },
  "akmd_mike_t_alt_kan_skje" => {
    bpm: 88, key: "F# minor", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Same family as Stailings; slightly busier hat 16ths.",
    texture: "Lo-fi warmth; boosted 80/200 Hz per AKMD chain.",
    harmony: "erykah_minor cycle.",
    dilla_engine: { track: "erykah_minor", performer: "yancey" }
  },
  "akmd_mike_t_jan_hakim_diverse" => {
    bpm: 86, key: "C minor", drum_preset: :mpc3000, groove_dna: "donuts",
    drums: "Neo-IV pocket; kick 0,6,10; ghost snares.",
    texture: "Diverse arrangement — filter sweeps between sections.",
    harmony: "Cm9–Fm7–Bbmaj7–Ebmaj9 neo_iv_cycle.",
    dilla_engine: { track: "neo_iv_cycle", performer: "yancey" }
  },
  "angelo_reira_johann_sandviken_hotell_a" => {
    bpm: 85, key: "F# minor", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Slow bergen swing; long kick sustain; rim ghosts.",
    texture: "Hotel-room ambience; heavy reverb on pad; AKMD LP.",
    harmony: "erykah_minor / keys_woman blend.",
    dilla_engine: { track: "erykah_minor", performer: "yancey" }
  },
  "angelo_reira_johann_sandviken_hotell_b" => {
    bpm: 84, key: "Eb", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Companion to A; softer kick velocity; more pad-forward.",
    texture: "Warmer, less drum-forward than A.",
    harmony: "keys_woman Ebmaj9–Cm9–Fm7–Bb7.",
    dilla_engine: { track: "keys_woman", performer: "yancey" }
  },
  "haisam_johann_pb1" => {
    bpm: 89, key: "F# minor", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "PB-series pocket; crisp snare; tight hats.",
    texture: "Cleaner top than Sandviken; still AKMD-mastered body.",
    harmony: "erykah_minor with iv_borrow_minor color.",
    dilla_engine: { track: "erykah_minor", performer: "yancey" }
  },
  "jan_hakim_johann_stailings_a" => {
    bpm: 87, key: "F# minor", drum_preset: :madlib_dusty, groove_dna: "donuts",
    drums: "Stailings variant; drunk hat stagger on 3,9,15.",
    texture: "Canonical Bergen stailings timbre — reference for local rotation.",
    harmony: "erykah_minor.",
    dilla_engine: { track: "erykah_minor", performer: "yancey" }
  },
  "mike_t_jr_rauingar" => {
    bpm: 90, key: "A minor", drum_preset: :dilla_slight, groove_dna: "donuts",
    drums: "Rauingar drive; kick syncopation 0,4,7,10; open hat on 14.",
    texture: "Slightly brighter hats; more energy in 4–8 kHz.",
    harmony: "iv_borrow_minor Am9–Dm9–Fmaj9–Em7.",
    dilla_engine: { track: "iv_borrow_minor", performer: "yancey" }
  },
  "flying_lotus_bts_radio_2006" => {
    bpm: 86, key: "varies", drum_preset: :flylo_abstract, groove_dna: "wonky",
    drums: "Live mix: long blends; percussion overdubs; tempo drift.",
    texture: "Radio collage; reverb throws; DJ-style filter sweeps.",
    harmony: "Multi-track medley — quartal + suspended ballads.",
    note: "Manifest start offset 1364s — deep in mix; treat as texture reference not grid template.",
    dilla_engine: { track: "quartal_west_coast", performer: "glasper" }
  }
}.freeze

  DOSSIERS_PATH = File.expand_path("../../reports/radio_bergen_track_dossiers.yml", ROOT).freeze

  module DeepAudio
      module_function
    
      def ffprobe(path)
        out, = Open3.capture2(
          "ffprobe", "-v", "error", "-show_entries", "format=duration,bit_rate:stream=sample_rate,channels",
          "-of", "json", path
        )
        JSON.parse(out)
      rescue StandardError
        {}
      end
    
      def band_rms(path, filter, window: 0.05, max_sec: 120)
        out, = Open3.capture2(
          "ffmpeg", "-hide_banner", "-loglevel", "error", "-t", max_sec.to_s, "-i", path,
          "-af", "#{filter},astats=metadata=1:reset=1:length=#{window},ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-",
          "-f", "null", "-"
        )
        out.lines.filter_map do |line|
          next unless line.include?("RMS_level=")
          val = line.split("=").last.to_f
          val.finite? ? val : nil
        end.compact
      end
    
      def detect_onsets(rms_series, threshold_db: -18.0, min_gap: 3)
        onsets = []
        rms_series.each_with_index do |rms, i|
          next if rms < threshold_db
          prev = rms_series[i - 1] if i.positive?
          next if prev && prev >= threshold_db
          onsets << i if onsets.empty? || (i - onsets.last) >= min_gap
        end
        onsets
      end
    
      def estimate_bpm(onsets, window_sec: 0.05)
        return nil if onsets.length < 4
        intervals = onsets.each_cons(2).map { |a, b| (b - a) * window_sec }
        median = intervals.sort[intervals.length / 2]
        return nil if median.nil? || median <= 0
        raw = 60.0 / median
        # fold to common hip-hop range
        while raw < 70
          raw *= 2
        end
        while raw > 105
          raw /= 2
        end
        raw.round(1)
      end
    
      def analyze(path)
        return nil unless path && File.file?(path)
    
        meta = ffprobe(path)
        duration = meta.dig("format", "duration").to_f
        stream = Array(meta["streams"]).first || {}
        analyze_sec = [duration * 0.85, 120].min
        analyze_sec = duration if duration.positive? && duration < 120
    
        full = band_rms(path, "aformat=channel_layouts=stereo", window: 0.05, max_sec: analyze_sec)
        sub = band_rms(path, "lowpass=f=80", window: 0.05, max_sec: analyze_sec)
        kick = band_rms(path, "lowpass=f=200,highpass=f=60", window: 0.05, max_sec: analyze_sec)
        snare = band_rms(path, "lowpass=f=4000,highpass=f=800", window: 0.05, max_sec: analyze_sec)
        hats = band_rms(path, "lowpass=f=12000,highpass=f=4000", window: 0.05, max_sec: analyze_sec)
    
        avg = ->(arr) { arr.empty? ? nil : (arr.sum / arr.length).round(2) }
        max = ->(arr) { arr.empty? ? nil : arr.max.round(2) }
    
        kick_onsets = detect_onsets(kick, threshold_db: -14.0, min_gap: 4)
        bpm_kick = estimate_bpm(kick_onsets)
        snare_onsets = detect_onsets(snare, threshold_db: -16.0, min_gap: 4)
        bpm_snare = estimate_bpm(snare_onsets)
    
        crest = if full.any?
                  peak = full.max
                  rms = avg.call(full)
                  rms ? (peak - rms).round(2) : nil
                end
    
        swing_hint = if kick_onsets.length >= 8
                       eighths = kick_onsets.each_cons(2).map { |a, b| b - a }
                       even = eighths.each_with_index.filter_map { |v, i| v if i.even? }
                       odd = eighths.each_with_index.filter_map { |v, i| v if i.odd? }
                       if even.any? && odd.any?
                         ratio = odd.sum.to_f / even.sum
                         ratio > 1.05 ? "laid_back" : ratio < 0.95 ? "pushed" : "straight"
                       end
                     end
    
        {
          measured: true,
          duration_seconds: duration.round(2),
          bit_rate: meta.dig("format", "bit_rate").to_i,
          sample_rate: stream["sample_rate"].to_i,
          channels: stream["channels"].to_i,
          bpm_estimate_kick: bpm_kick,
          bpm_estimate_snare: bpm_snare,
          bpm_estimate: [bpm_kick, bpm_snare].compact.then { |a| a.empty? ? nil : (a.sum / a.length).round(1) },
          loudness: {
            full_rms_db: avg.call(full), full_peak_db: max.call(full),
            sub_rms_db: avg.call(sub), kick_rms_db: avg.call(kick),
            snare_rms_db: avg.call(snare), hats_rms_db: avg.call(hats)
          },
          dynamics: { crest_factor_db: crest, swing_hint: swing_hint },
          drum_density: {
            kick_transients_per_min: kick_onsets.length * (60.0 / [analyze_sec, 1].max).round(1),
            snare_transients_per_min: snare_onsets.length * (60.0 / [analyze_sec, 1].max).round(1)
          },
          spectral_balance: spectral_balance(sub, kick, snare, hats),
          texture_hints: texture_hints(avg.call(sub), avg.call(kick), avg.call(hats), crest)
        }
      rescue StandardError => e
        { measured: false, error: e.message }
      end
    
      def spectral_balance(sub, kick, snare, hats)
        sub_a = sub.select { |v| v > -50 }
        kick_a = kick.select { |v| v > -50 }
        snare_a = snare.select { |v| v > -50 }
        hats_a = hats.select { |v| v > -50 }
        return {} if kick_a.empty?
    
        k = kick_a.sum / kick_a.length
        profile = {}
        profile[:sub_kick_ratio] = ratio(sub_a, k)
        profile[:snare_kick_ratio] = ratio(snare_a, k)
        profile[:hats_kick_ratio] = ratio(hats_a, k)
        profile[:brightness] = case profile[:hats_kick_ratio]
                               when nil then "unknown"
                               when ..-18 then "dark"
                               when -18..-12 then "warm"
                               else "bright"
                               end
        profile
      end
    
      def ratio(num_band, kick_avg)
        return nil if num_band.empty? || kick_avg.zero?
        n = num_band.sum / num_band.length
        (n - kick_avg).round(2)
      end
    
      def texture_hints(sub_rms, kick_rms, hats_rms, crest)
        hints = []
        hints << "heavy_sub" if sub_rms && sub_rms > -22
        hints << "lofi_rolled" if hats_rms && hats_rms < -28
        hints << "punchy_transients" if crest && crest > 12
        hints << "compressed_glue" if crest && crest < 8
        hints
      end
  end

  def resolve_local_path(row, audio_root: nil)
    src = row[:src].to_s
    return nil if src.empty?
    names = LOCAL_NAME_ALIASES[src] || [File.basename(src)]
    candidates = []
    candidates << File.join(audio_root, src.delete_prefix("/")) if audio_root
    AUDIO_SEARCH_ROOTS.each do |root|
      names.each { |n| candidates << File.join(root, n) }
    end
    candidates << File.expand_path("../../../pub2/public#{src}", AUDIO_ROOT)
    candidates << File.expand_path("../../public#{src}", AUDIO_ROOT)
    candidates.find { |p| File.file?(p) }
  end

  def dossier_for(id)
    TRACK_DOSSIERS[id.to_s] || TRACK_DOSSIERS[id.to_sym]
  end

  def apply_dossier_env!(id)
    d = dossier_for(id)
    return unless d
    eng = d[:dilla_engine]
    return unless eng.is_a?(Hash)
    eng.each { |k, v| ENV[k.to_s] = v.to_s if v && !v.to_s.empty? }
  end

  def dossier_for_engine_track(track_name)
    TRACK_DOSSIERS.each_value.find { |d| d.dig(:dilla_engine, :track).to_s == track_name.to_s }
  end

  def apply_engine_track_dossier!(track_name)
    d = dossier_for_engine_track(track_name)
    return unless d
    eng = d[:dilla_engine]
    return unless eng.is_a?(Hash)
    eng.each { |k, v| ENV[k.to_s] = v.to_s if v && !v.to_s.empty? }
  end

  def engine_study(path)
    return {} unless path && File.file?(path)
    rhythm_data = frame_energy(path, highpass: 90, lowpass: 8_000)
    peaks = peak_frames(rhythm_data.fetch(:frames), rhythm_data.fetch(:hop_seconds))
    profile = pitch_profile(path)
    ranking = chord_candidates(profile.fetch(:pitch_classes)).first(6)
    sem = semantics_tags_for(path)
    {
      duration_seconds: rhythm_data.fetch(:duration_seconds),
      rhythm_peaks: peaks.first(48),
      pitch_classes: profile.fetch(:pitch_classes),
      top_chords: ranking,
      semantics: sem,
      bands: {
        sub: band_rms(path, highpass: 28, lowpass: 180),
        kick: band_rms(path, highpass: 60, lowpass: 200),
        snare: band_rms(path, highpass: 800, lowpass: 4000),
        hats: band_rms(path, highpass: 4000, lowpass: 12_000)
      }
    }
  end

  def semantics_tags_for(path)
    rhythm_data = frame_energy(path, highpass: 60, lowpass: 12_000)
    loudness = rhythm_data.fetch(:frames).map(&:last)
    brightness = frame_energy(path, highpass: 2_400, lowpass: 12_000).fetch(:frames).map(&:last)
    density = peak_frames(rhythm_data.fetch(:frames), rhythm_data.fetch(:hop_seconds)).length.to_f /
              [rhythm_data.fetch(:duration_seconds), 1.0].max
    semantic_tags(loudness, brightness, density)
  end

  def cross_track_learnings
    {
      "bergen_local" => {
        "drum_pattern" => "madlib_dusty / mpc3000 hybrid; kicks 0,6,10; swung 8th hats; AKMD chain HPF 60 LPF 11.5k",
        "texture" => "bergen_night_rain pad wash; vinyl 0.07–0.08; bass shelf +9; master LP 2.7–3.1 kHz",
        "harmony" => "erykah_minor (F#m9–Bm7–Emaj7–C#m7); bill_evans voicing; swing 58%",
        "bpm_cluster" => "84–90"
      },
      "dilla_canon" => {
        "drum_pattern" => "MPC swing 54–62%; kick late-3 anchor; snare early on 4/12; ghost on 2/10",
        "texture" => "donuts_lowpass_warmth; vinyl 0.06; never harsh above 3.4 kHz on pads",
        "harmony" => "maj7_minor_cycle + minor_iv_loop family",
        "bpm_cluster" => "86–94"
      },
      "flylo_canon" => {
        "drum_pattern" => "flylo_abstract broken 16ths; kick 0,5,8,13; displaced snares",
        "texture" => "sidechain pump + jazz haze; quartal voicings; stereo pan hats",
        "harmony" => "quartal_west_coast / glasper_quartal",
        "bpm_cluster" => "82–88"
      },
      "slum_canon" => {
        "drum_pattern" => "neo_soul_pocket / mpc3000; players progression Dm7–Eb7–Gm7–Am7",
        "texture" => "cleaner punch than Donuts; bass sustain 0.92",
        "bpm_cluster" => "90–96"
      }
    }
  end

  def dossiers!(audio_root: nil)
    rows = catalog_rows
    tracks = rows.map do |row|
      id = slug(row[:artist], row[:title])
      audio = resolve_local_path(row, audio_root: audio_root)
      measured = audio ? DeepAudio.analyze(audio) : nil
      reference = dossier_for(id)
      entry = {
        id: id, artist: row[:artist], title: row[:title], source: row[:source],
        youtube_id: row[:youtube_id], audio_file: audio, analysis: measured,
        production_dossier: reference,
        engine_recommendation: reference&.dig(:dilla_engine) || {
          track: "erykah_minor", performer: "yancey", groove_dna: "donuts",
          kicks: "1", speak: "1", mix: "akmd_lofi_mastering"
        }
      }
      if measured && reference && measured[:bpm_estimate] && reference[:bpm]
        delta = (measured[:bpm_estimate] - reference[:bpm]).abs
        if delta > 4
          entry[:calibration_notes] = ["BPM delta #{delta.round(1)} (#{measured[:bpm_estimate]} measured vs #{reference[:bpm]} curated)"]
        end
        entry[:calibration_notes] ||= []
        entry[:calibration_notes] << "Swing: #{measured.dig(:dynamics, :swing_hint)}" if measured.dig(:dynamics, :swing_hint)
      end
      entry
    end
    {
      "meta" => {
        "generated_at" => Time.now.utc.iso8601,
        "manifest" => RADIO_BERGEN_MANIFEST_PATH,
        "tracks" => tracks.length,
        "measured_local" => tracks.count { |t| t[:analysis]&.dig(:measured) },
        "reference_curated" => tracks.count { |t| t[:production_dossier] }
      },
      "cross_track_learnings" => cross_track_learnings,
      "tracks" => tracks
    }
  end

  def write_dossiers!(audio_root: nil, path: DOSSIERS_PATH)
    data = stringify_keys(dossiers!(audio_root: audio_root))
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, data.to_yaml)
    path
  end

  def stringify_keys(obj)
    case obj
    when Hash then obj.each_with_object({}) { |(k, v), h| h[k.to_s] = stringify_keys(v) }
    when Array then obj.map { |v| stringify_keys(v) }
    else obj
    end
  end

  def write!(audio_root: nil, path: RADIO_BERGEN_SONIC_PATH)
    data = stringify_keys(study!(audio_root: audio_root))
    File.write(path, data.to_yaml)
    path
  end
end

def load_radio_bergen_learnings
  return @radio_bergen_learnings if defined?(@radio_bergen_learnings)
  base = Marshal.load(Marshal.dump(INLINE_RADIO_BERGEN_LEARNINGS))
  if File.file?(RADIO_BERGEN_SONIC_PATH)
    file_data = YAML.safe_load(File.read(RADIO_BERGEN_SONIC_PATH), permitted_classes: [Symbol], aliases: true)
    base = merge_sonic_profile_hashes(base, file_data) if file_data.is_a?(Hash)
  end
  if File.file?(PROMOTED_PROFILES_PATH)
    promoted = JSON.parse(File.read(PROMOTED_PROFILES_PATH))
    weights = (base["stream_rotation_weights"] || {}).dup
    promoted.each do |track, count|
      next if track.start_with?("_")
      weights[track.to_s] = (weights[track.to_s] || 0) + count.to_i.clamp(1, 8)
    end
    base["stream_rotation_weights"] = weights
  end
  @radio_bergen_learnings = base
rescue StandardError => e
  warn "radio bergen learnings: #{e.message}"
  @radio_bergen_learnings = Marshal.load(Marshal.dump(INLINE_RADIO_BERGEN_LEARNINGS))
end

def merge_sonic_profile_hashes(base, extra)
  return extra if base.nil?
  return base if extra.nil?
  base.merge(extra) do |_k, left, right|
    left.is_a?(Hash) && right.is_a?(Hash) ? merge_sonic_profile_hashes(left, right) : right
  end
end

def load_sonic_profiles
  return @sonic_profiles if defined?(@sonic_profiles) && @sonic_profiles
  merged = INLINE_SONIC_PROFILES.transform_keys(&:to_sym).transform_values(&:dup)
  extras = load_radio_bergen_learnings["sonic_profiles"]
  if extras.is_a?(Hash)
    extras.each do |key, profile|
      sym = key.to_sym
      merged[sym] = merge_sonic_profile_hashes(merged[sym], profile)
    end
  end
  @sonic_profiles = merged.freeze
end

def radio_bergen_stream_enabled?
  ENV.fetch("RADIO_BERGEN", "1") != "0" && ENV["DILLA_STREAMING"] == "1"
end

def pick_radio_bergen_stream_track!
  return unless radio_bergen_stream_enabled?
  weights = load_radio_bergen_learnings["stream_rotation_weights"]
  return unless weights.is_a?(Hash) && weights.any?
  pool = weights.flat_map { |track, count| Array.new(count.to_i.clamp(1, 12), track.to_s) }
  return if pool.empty?
  picked = pool.sample
  ENV["TRACK"] = picked
  defaults = load_radio_bergen_learnings["stream_env_defaults"]
  if defaults.is_a?(Hash)
    defaults.each do |key, value|
      ENV[key] = value.to_s if ENV[key].nil? || ENV[key].empty?
    end
  end
  RadioBergenStudy.apply_engine_track_dossier!(picked)
  picked
end

def sonic_profile_for(track)
  sym = track.to_sym
  key = TRACK_SONIC_MAP.fetch(sym, nil)
  base = key ? load_sonic_profiles[key] : nil
  return base unless DillaLofiMachine.harmony_profile?(sym)
  synth = (base&.dig("synth") || {}).merge(DillaLofiMachine.lofi_sonic_overlay(sym))
  { "synth" => synth, "harmonic" => base&.dig("harmonic") || {} }
end

def style_family(track, feel: nil)
  if (entry = DillaLofiMachine.profile_entry(track))
    return :flylo if entry[:producer] == :flylo
    return :madlib if entry[:producer] == :madlib
    return :dilla
  end
  return :flylo if FLYLO_TRACKS.include?(track.to_sym) || feel == :loose_pocket
  return :dilla if DILLA_TRACKS.include?(track.to_sym) ||
                   %i[timeless organic chromatic_planing syncopated_slash_ninth
                      dilla_slight dilla_drunk madlib_dusty flylo_abstract mpc3000 sp303 sp1200].include?(feel)
  return :madlib if track.to_s.include?("madlib")
  :default
end

def resolve_bpm(preset, track, sonic)
  env_bpm = ENV["BPM"]&.to_f
  return env_bpm if env_bpm&.positive?
  sonic_bpm = sonic&.dig("synth", "bpm")&.to_f
  return sonic_bpm if sonic_bpm&.positive?
  preset.fetch(:bpm, DEFAULT_BPM).to_f
end

def resolve_swing(preset, sonic, time_offset)
  return 62.5 if ENV["GOLDEN_SWING"] == "1"
  return ENV["SWING"].to_f if ENV["SWING"]
  sonic_swing = sonic&.dig("synth", "swing")&.to_f
  if DillaLofiMachine.harmony_profile?((ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym)
    return preset.fetch(:swing, 54).to_f + time_offset
  end
  base = if sonic_swing && sonic_swing < 1.0
           DillaLofiMachine.mpc_swing_from_sonic_fraction(sonic_swing) + time_offset
         else
           preset.fetch(:swing, 54).to_f + time_offset
         end
  base.clamp(50.0, 66.0)
end

def track_preset(track)
  prod = DillaLofiMachine.profile_preset(track)
  return prod if prod
  return TRACK_PRESETS[track] if TRACK_PRESETS.key?(track)
  base = TRACK_PRESETS[:timeless].dup
  base[:progression] = track if CHORD_PROGRESSIONS.key?(track)
  base
end

def curated_progression?(cfg)
  CURATED_PROGRESSIONS.include?(cfg[:progression].to_sym) ||
    DillaLofiMachine::CURATED_PROGRESSIONS.include?(cfg[:progression].to_sym)
end

def enhanced_resolve_config
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym
  preset = track_preset(track)
  prog = (ENV["PROGRESSION"] || preset.fetch(:progression, track)).to_s.downcase.tr("-", "_").to_sym
  sonic = sonic_profile_for(track)
  feel = preset[:feel] || :default
  family = style_family(track, feel:)
  {
    track: track,
    bpm: resolve_bpm(preset, track, sonic),
    progression: prog,
    chord_bars: preset.fetch(:chord_bars, 4),
    phrase_bars: preset[:phrase_bars],
    swing: resolve_swing(preset, sonic, time_of_day_swing_offset),
    feel: feel,
    stereo_pan: preset[:stereo_pan] || false,
    timing: preset[:timing],
    quintuplet: ENV["QUINTUPLET"] ? ENV["QUINTUPLET"] != "0" : (preset[:quintuplet] || false),
    sonic: sonic,
    style_family: family,
    sidechain: ENV["SIDECHAIN"] != "0" && (family == :flylo || preset[:sidechain] || sonic&.dig("synth", "sidechain_pump")),
    no_quantize: ENV["NO_QUANTIZE"] == "1" || (family == :flylo && ENV["NO_QUANTIZE"] != "0"),
    golden_swing: ENV["GOLDEN_SWING"] == "1",
    voicing: (ENV["VOICING"] || preset[:voicing] || (family == :flylo ? :quartal : :spread)).to_sym,
    engine_progression: sonic&.dig("harmonic", "engine_progression")&.to_sym,
    half_time_bars: preset[:half_time_bars],
    intro_bars: preset.fetch(:intro_bars, family == :flylo ? 8 : 4),
    master_lufs: resolve_master_lufs(family, sonic),
    master_lra: resolve_master_lra(family, sonic),
    # Full darken (1.0) on FlyLo was muting kick beater + snare air under pads.
    mood_darken_strength: if family == :dilla
                            deep_render? ? 0.36 : 0.55
                          elsif family == :flylo || camel_mode?
                            0.42
                          else
                            0.75
                          end
  }
end

def resolve_master_lufs(family, sonic)
  texture = sonic&.dig("synth", "texture").to_s
  return -20.0 if family == :dilla && texture.include?("donuts")
  MASTER_LUFS_BY_STYLE.fetch(family, MASTER_LUFS_BY_STYLE[:default])
end

def resolve_master_lra(family, sonic)
  texture = sonic&.dig("synth", "texture").to_s
  return 14.5 if family == :dilla && texture.include?("donuts")
  LRA_BY_STYLE.fetch(family, LRA_BY_STYLE[:default])
end

def chord_from_quality(root_hz, quality, voices: 5)
  intervals = CHORD_TEMPLATES_EXT.fetch(quality) { CHORD_TEMPLATES.fetch(quality) }
  hz = intervals.map { |iv| (root_hz * (2**(iv / 12.0))).round(2) }
  extra = intervals.max + 2
  hz << (root_hz * (2**(extra / 12.0))).round(2) while hz.length < voices
  hz.sort.first(voices)
end

def chord_intervals_from_hz(hz)
  midis = hz.map { |h| hz_to_midi(h) }.sort
  root = midis.first
  midis.map { |m| ((m - root) % 12).round }.uniq
end

def apply_voicing(hz, style)
  midis = hz.map { |h| hz_to_midi(h) }.sort
  case style
  when :quartal
    base = midis.first
    [base, base + 5, base + 10, base + 15, base + 17].map { |m| midi_to_hz(m) }
  when :drop2
    return hz if midis.length < 4
    ordered = midis
    drop = ordered.dup
    drop[-2] = ordered[-2] - 12.0 if ordered[-2] > 48
    drop.map { |m| midi_to_hz(m) }
  when :drop3
    return hz if midis.length < 4
    ordered = midis
    drop = ordered.dup
    drop[-3] = ordered[-3] - 12.0 if ordered[-3] > 48
    drop.map { |m| midi_to_hz(m) }
  when :spread
    return hz if midis.length < 2
    root = midis.first
    ivs = chord_intervals_from_hz(hz)
    third_iv = ivs.find { |i| [3, 4].include?(i) } || 4
    fifth_iv = ivs.find { |i| [7, 6].include?(i) } || 7
    seventh_iv = ivs.find { |i| [10, 11].include?(i) }
    ninth_iv = ivs.find { |i| [2, 14].include?(i) }
    voiced = [root, root + fifth_iv, root + third_iv + 12]
    voiced << (root + seventh_iv + 12) if seventh_iv
    voiced << (root + (ninth_iv == 2 ? 14 : ninth_iv) + 12) if ninth_iv
    voiced = [root, root + fifth_iv, root + third_iv + 12, root + (seventh_iv || 10) + 12, root + 14] if voiced.length < 4
    voiced.map { |m| midi_to_hz(m) }.uniq.first(5)
  when :cluster
    base = midis.first
    [base, base + 1, base + 2, base + 6, base + 7].map { |m| midi_to_hz(m) }
  else
    hz
  end.uniq.first(5)
end

def decorate_chord(chord, voicing: :spread)
  hz = apply_voicing(chord[:hz], voicing)
  { name: chord[:name], hz: hz }
end

def generate_coltrane_changes(root_hz:, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  offsets = [0, 4, 8] # major thirds
  start = offsets.sample(random: rng)
  Array.new(length) do |i|
    semitone = start + offsets[i % 3]
    root = root_hz * (2**(semitone / 12.0))
    q = %w[maj9 m9 7].sample(random: rng)
    { name: "coltrane#{semitone}#{q}", hz: chord_from_quality(root, q) }
  end
end

def generate_backdoor_progression(root_hz:, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  semitones = SCALE_SEMITONES.fetch(mode)
  degree = 1
  transitions = DEGREE_TRANSITIONS.merge(5 => { 1 => 2, 6 => 4, 4 => 1, 3 => 3 })
  quality_for = SCALE_DEGREE_QUALITY.fetch(mode).merge(4 => "7alt", 7 => "7#11")
  Array.new(length) do
    quality = quality_for.fetch(degree, "m9")
    quality = "7alt" if degree == 5 && rng.rand < 0.35
    chord_root = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
    chord = { name: "bk#{degree}#{quality}", hz: chord_from_quality(chord_root, quality) }
    degree = weighted_pick(rng, transitions.fetch(degree, { 1 => 1 }))
    chord
  end
end

def generate_slash_progression(root_hz:, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  pedal = root_hz
  semitones = SCALE_SEMITONES.fetch(mode)
  degree = 0
  Array.new(length) do
    step = semitones[degree % semitones.length] + (degree / semitones.length) * 12
    upper_root = root_hz * (2**(step / 12.0))
    q = rng.rand < 0.5 ? "maj9" : "m9"
    hz = chord_from_quality(upper_root, q, voices: 4)
    hz[0] = pedal
    degree += weighted_pick(rng, PLANING_STEP_WEIGHTS)
    { name: "slash#{step}#{q}", hz: hz.sort }
  end
end

def generate_modal_interchange(root_hz:, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  pool = mode == :minor ? [1, 4, 5, 6, 3, 2, 7, 4, 6] : [1, 2, 3, 4, 5, 6, 7, 6, 4]
  semitones = SCALE_SEMITONES.fetch(mode)
  borrow = { 4 => "maj9", 6 => "maj9", 3 => "aug", 7 => "dim" }
  Array.new(length) do |i|
    degree = pool[i % pool.length]
    q = borrow[degree] || SCALE_DEGREE_QUALITY.fetch(mode).fetch(degree, "m9")
    q = PLANING_QUALITIES.sample(random: rng) if rng.rand < 0.2
    root = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
    { name: "mod#{degree}#{q}", hz: chord_from_quality(root, q) }
  end
end

def root_motion_semitones(a, b)
  a_root = hz_to_midi(a[:hz].min)
  b_root = hz_to_midi(b[:hz].min)
  diff = (b_root - a_root) % 12
  [diff, 12 - diff].min
end

def passing_cluster_between(a, b, rng)
  a_root = hz_to_midi(a[:hz].min)
  b_root = hz_to_midi(b[:hz].min)
  mid_midi = ((a_root + b_root) / 2.0).round
  cluster = [mid_midi - 1, mid_midi, mid_midi + 1, mid_midi + 4].map { |m| midi_to_hz(m + 12) }
  { name: "pass_#{mid_midi}", hz: cluster.uniq.first(4) }
end

# A fugue's recapitulation restating the exposition note-for-note in the
# same voicing reads as static — real recaps land the same material in a
# different register/spacing so the return feels like arrival, not replay.
CONTRAST_VOICINGS = {
  quartal: :drop2, drop2: :cluster, cluster: :spread,
  spread: :quartal, drop3: :spread
}.freeze

def enrich_progression(pads, cfg, phases: [])
  DillaHarmony.enrich_progression(pads, cfg, phases: phases)
end

def progression_from_engine(sonic, _fallback_mode)
  chord_names = sonic&.dig("harmonic", "engine_chords")
  if chord_names&.any?
    return chord_names.map do |n|
      PAD_CHORD_LOOKUP[n] || MODAL_MINOR_CHORDS.find { |c| c[:name] == n }
    end.compact
  end
  name = sonic&.dig("harmonic", "engine_progression")&.to_sym
  return nil unless name && CHORD_PROGRESSIONS.key?(name)
  CHORD_PROGRESSIONS.fetch(name).map do |n|
    PAD_CHORD_LOOKUP[n] || MODAL_MINOR_CHORDS.find { |c| c[:name] == n }
  end.compact
end

def arrange_fugue_progression(pads, needed_chords, cfg)
  return pads if pads.empty?
  hook = pads
  exposition = [(needed_chords * 0.25 / hook.length).ceil, 2].max
  development_len = [(needed_chords * 0.35).round, 2].max
  recapitulation = [(needed_chords * 0.25).round, hook.length].max
  coda = [needed_chords - (exposition * hook.length) - development_len - recapitulation, 0].max

  dev_root = hook.last[:hz].min * (cfg[:style_family] == :flylo ? (2**(3.0 / 12.0)) : 1.0)
  dev_style = case cfg[:progression]
              when :planing then :planing
              when :chromatic_mediant then :chromatic_mediant
              else :functional
              end
  development = case dev_style
                when :planing
                  generate_planing_progression(root_hz: dev_root, length: development_len, seed: cfg[:track].hash.abs)
                when :chromatic_mediant
                  generate_chromatic_mediant_progression(root_hz: dev_root, length: development_len, seed: cfg[:track].hash.abs)
                else
                  generate_progression(root_hz: dev_root, mode: :minor, length: development_len, seed: cfg[:track].hash.abs)
                end

  intro_hook = Array.new(exposition) { hook }.flatten
  recap = hook.first(recapitulation)
  outro = coda.positive? ? (hook * (coda / hook.length.to_f).ceil).first(coda) : []
  arranged = intro_hook + development + recap + outro

  phases = []
  intro_hook.length.times { phases << :exposition }
  development.length.times { phases << :development }
  recap.length.times { phases << :recapitulation }
  outro.length.times { phases << :coda }

  [arranged.first(needed_chords), phases.first(needed_chords)]
end

LA_BEAT_SECTION_STYLES = %i[hook functional chromatic_mediant neo_soul quartal].freeze
# No :planing — generate_planing_progression names like planing0m9 sound random/ugly.
CAMEL_LA_BEAT_STYLES = %i[hook chromatic_mediant functional bridge].freeze
CAMEL_BRIDGE_SYMS = %w[Gm7 Cm11nc Fm9 Bbm9 Eb7 AbMaj13s11 Dmaj9nc DMaj7overG].freeze
CAMEL_FUNCTIONAL_SYMS = %w[Dm9 Gm9 Cm9 Fmaj9 Bbm9 Ebmaj9 Abmaj9 Dbmaj9].freeze
LA_BEAT_MIDI_FX_ROTATE = [
  { cc: 1, rate_hz: 0.22, depth: 52, base: 38, curve: :sine },
  { cc: 74, rate_hz: 0.16, depth: 42, base: 28, curve: :swell },
  { cc: 91, rate_hz: 0.12, depth: 30, base: 22, curve: :sine },
  { cc: 5, rate_hz: 0.18, depth: 24, base: 48, curve: :sine },
  { bend: true, rate_hz: 0.14, depth_cents: 18 }
].freeze

def camel_mode?
  m = ENV["RENDER_MODE"]&.downcase
  m == "camel" || m == "dilla"
end

def camel_drum_entry_bar
  ENV.fetch("CAMEL_DRUM_ENTRY_BAR", "0").to_i
end

def camel_keep_flylo_on_breakdown?
  ENV.fetch("CAMEL_KEEP_FLYLO", camel_mode? ? "1" : "0") != "0"
end

def la_beat_progression_enabled?
  # Do NOT force LA-beat on Camel — that injected random planing0m9-style
  # chords and made streams sound broken. Opt in: LA_BEAT_PROGRESSION=1.
  ENV.fetch("LA_BEAT_PROGRESSION", "0") != "0"
end

def soul_progression_locked?
  ENV["STREAM_SOUL"] == "1" && ENV.fetch("STREAM_LOCK", "0") == "1"
end

# LA beat / FlyLo stream — stitch random long sections with variable bar lengths
# instead of looping the first four bars forever.
def arrange_la_beat_progression(pads, needed_chords, cfg)
  return arrange_loop_progression(pads, needed_chords, cfg) + [nil] if pads.empty?

  rng = Random.new(patch_cycle_seed(needed_chords + cfg[:track].to_s.hash.abs))
  hook = pads
  out = []
  phases = []
  chord_lens = []

  while out.length < needed_chords
    style = LA_BEAT_SECTION_STYLES[rng.rand(LA_BEAT_SECTION_STYLES.length)]
    take = rng.rand(3..8)
    root_hz = (out.last || hook.first)[:hz].min
    section = case style
              when :hook
                hook
              when :functional
                generate_progression(root_hz: root_hz, mode: :minor, length: take, seed: rng.rand(1..99_999))
              when :planing
                generate_planing_progression(root_hz: root_hz, length: take, seed: rng.rand(1..99_999))
              when :chromatic_mediant
                generate_chromatic_mediant_progression(root_hz: root_hz, length: take, seed: rng.rand(1..99_999))
              when :neo_soul, :quartal
                voice_lead_chords(generate_progression(root_hz: root_hz, mode: :minor, length: take,
                                                       seed: rng.rand(1..99_999)))
              else
                hook
              end
    section.each do |ch|
      break if out.length >= needed_chords
      out << ch
      phases << %i[exposition main development recapitulation].sample(random: rng)
      chord_lens << rng.rand(1..4)
    end
  end
  [out.first(needed_chords), phases.first(needed_chords), chord_lens.first(needed_chords)]
end

def camel_section_pads(style, hook, root_hz, take, rng)
  case style
  when :hook
    hook
  when :bridge
    bridge = CAMEL_BRIDGE_SYMS.filter_map { |n| learned_chord_pad(n) }
    bridge.length >= 2 ? bridge : hook
  when :chromatic_mediant
    generate_chromatic_mediant_progression(root_hz: root_hz, length: take, seed: rng.rand(1..99_999))
  when :functional
    base = CAMEL_FUNCTIONAL_SYMS.filter_map { |n| learned_chord_pad(n) }
    base = curated_progression_pads(:timeless_authentic) if base.length < 4
    base = curated_progression_pads(:maj7_minor_cycle) if base.length < 4
    if base&.length.to_i >= 2
      base.cycle.take(take).to_a
    else
      generate_progression(root_hz: root_hz, mode: :minor, length: take, seed: rng.rand(1..99_999))
    end
  when :planing
    generate_planing_progression(root_hz: root_hz, length: take, seed: rng.rand(1..99_999))
  else
    hook
  end
end

# Camel stream — chromatic mediant hook + D-minor functional/planing bridges (never 4-bar loop lock).
def arrange_camel_beat_progression(pads, needed_chords, cfg)
  hook = if pads.empty?
           curated_progression_pads(:chromatic_mediant_drift) || []
         else
           pads
         end
  return arrange_loop_progression(hook, needed_chords, cfg) + [nil] if hook.length < 2

  rng = Random.new(patch_cycle_seed(needed_chords + cfg[:track].to_s.hash.abs + 86))
  out = []
  phases = []
  chord_lens = []
  styles = CAMEL_LA_BEAT_STYLES

  while out.length < needed_chords
    style = styles[rng.rand(styles.length)]
    style = :hook if out.empty?
    take = rng.rand(4..10)
    root_hz = (out.last || hook.first)[:hz].min
    section = camel_section_pads(style, hook, root_hz, take, rng)
    section.each do |ch|
      break if out.length >= needed_chords
      out << ch
      phases << case style
                when :hook then :exposition
                when :bridge then :turn
                when :chromatic_mediant then :development
                when :planing then :build
                else :main
                end
      chord_lens << rng.rand(1..4)
    end
  end
  [out.first(needed_chords), phases.first(needed_chords), chord_lens.first(needed_chords)]
end

# Curated hooks loop as written — no random generative development section
# wedged into the middle of a Donuts/Slum transcription.
def arrange_loop_progression(pads, needed_chords, _cfg)
  return [pads, []] if pads.empty?
  hook = pads
  looped = (hook * (needed_chords.to_f / hook.length).ceil).first(needed_chords)
  total_cycles = (needed_chords.to_f / hook.length).ceil
  phases = looped.each_with_index.map do |_chord, i|
    cycle = i / hook.length
    pos = i % hook.length
    if cycle.zero?
      :exposition
    elsif cycle >= total_cycles - 1 && pos >= [hook.length - 2, 0].max
      :recapitulation
    else
      :main
    end
  end
  [looped, phases]
end

def log_progression_phases!(track, bpm, pads, phases)
  return if pads.empty?
  lines = pads.each_with_index.map do |chord, i|
    phase = phases&.[](i) || "—"
    notes = chord[:hz].map { |hz| nearest_note(hz) }.join(" ")
    "  [#{phase}] #{chord[:name]}: #{notes}"
  end
  File.open(PROGRESSION_LOG_PATH, "a") do |f|
    f.puts "=== #{Time.now.iso8601} — TRACK=#{track} BPM=#{bpm.round(1)} (fugue) ==="
    f.puts lines
    f.puts
  end
rescue StandardError => e
  warn "progression log write failed: #{e.message}"
end

def cyclic_timing_offset(role, bar_index, step_index, timing, beat_p, cycle: 4)
  range = timing&.fetch(role, nil) || MICROTIMING_MS.fetch(role)
  cyclic_bar = bar_index % cycle
  seed = (cyclic_bar * 97) + (step_index * 31) + role.hash.abs
  raw = range.begin + (seed % (range.end - range.begin + 1))
  return raw unless beat_p
  tick_ms = (beat_p * 1000.0) / 96.0
  quantized = ((raw / tick_ms).round * tick_ms).round(3)
  if ENV["NO_QUANTIZE"] == "1"
    jitter = Random.new(seed).rand(-2.0..2.0)
    return (quantized + jitter).round(3)
  end
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym
  ticks = DillaLofiMachine.humanize_ticks_for(track)
  if ticks.positive?
    bpm = 60.0 / beat_p
    h_ms = DillaLofiMachine.humanize_ms(bpm, ticks)
    jitter = Random.new(seed + 17).rand(-h_ms..h_ms)
    return (quantized + jitter).round(3)
  end
  quantized
end

def phase_gain_multiplier(phase)
  case phase
  when :exposition then 0.94
  when :development then 0.78
  when :recapitulation then 1.0
  when :coda then 0.68
  else 1.0
  end
end

def chord_phase_at(bar, pad_chords, chord_phases, chord_bars:, phrase_bars: nil)
  return nil if pad_chords.nil? || pad_chords.empty? || chord_phases.nil? || chord_phases.empty?
  idx = dilla_chord_index(bar, pad_chords, chord_bars: chord_bars, phrase_bars: phrase_bars)
  chord_phases[idx]
end

def section_density(bar, n_bars, chord_phases: nil, pad_chords: nil, chord_bars: 2, phrase_bars: nil)
  base = if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
           prof = @composition_session.profile_at(bar)
           tension = @composition_session.tension_at(bar)
           (prof[:drums] * 0.5 + tension * 0.5).clamp(0.2, 1.0)
         else
           sec = dilla_section_legacy(bar, n_bars)
           case sec
           when :intro then 0.55
           when :breakdown then 0.45
           when :build
             build_start = (n_bars * 0.82).to_i
             0.72 + 0.28 * ((bar - build_start).to_f / [n_bars * 0.18, 1].max).clamp(0.0, 1.0)
           when :outro then 0.5
           else 1.0
           end
         end
  phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars: chord_bars, phrase_bars: phrase_bars)
  base * (phase ? phase_gain_multiplier(phase) : 1.0)
end

def schedule_eclectic_percussion!(events, duration, beat_p, bar_p, cfg, n_bars)
  rng = Random.new(cfg[:track].to_s.hash.abs + 909)
  step_p = beat_p / 4.0
  family = cfg[:style_family]

  # Polyrhythm 5:4 layer
  poly5 = bar_p / 5.0
  (0...(duration / poly5).floor).each do |i|
    next if family != :flylo && i % 5 != 0
    t = (i * poly5).round(6)
    events[:poly5] ||= []
    events[:poly5] << [t, (0.12 + 0.06 * Math.sin(i * 0.9)).clamp(0.06, 0.28), :rim]
  end

  # Clap on 2&4 is scheduled in dilla_schedule (snare unison) when BACKBEAT_CLAP=1.
  unless backbeat_clap_enabled?
    (0...(duration / bar_p).floor).each do |bar|
      base = bar * bar_p
      density = section_density(bar, n_bars, chord_phases: @chord_phases, pad_chords: @progression_chords,
                                chord_bars: @render_chord_bars, phrase_bars: @render_phrase_bars)
      next if density < 0.5
      [1, 3].each do |beat|
        t = (base + beat * beat_p).round(6)
        events[:clap] ||= []
        events[:clap] << [t, dilla_velocity(0.42 * density, bar, beat, spread: 0.08), :clap]
      end
    end
  end

  # Rim / brush / woodblock / agogo / glitch / tabla / tambourine — both
  # style families now get the eclectic layer (was FlyLo-only, which left
  # :dilla-family tracks — most of STREAM_TRACKS — with almost nothing
  # here beyond sparse woodblock/agogo; real critique was "not intricate
  # or dynamic"). :dilla family gets a calmer rate, not zero.
  (0...(duration / step_p).floor).each do |i|
    bar = (i / 16).floor
    density = section_density(bar, n_bars, chord_phases: @chord_phases, pad_chords: @progression_chords,
                              chord_bars: @render_chord_bars, phrase_bars: @render_phrase_bars)
    t = (i * step_p).round(6)
    r = rng.rand
    if family == :flylo || family == :dilla
      wild = family == :flylo ? 1.0 : 0.6
      events[:rim] ||= []
      events[:rim] << [t, dilla_velocity(0.28, bar, i % 16, spread: 0.1), 0.35] if r < 0.04 * density * wild
      events[:glitch] ||= []
      events[:glitch] << [t + rng.rand * step_p * 0.5, dilla_velocity(0.35, bar, i, spread: 0.12), :ind_stab] if r < 0.02 * wild
      events[:tabla] ||= []
      events[:tabla] << [t, dilla_velocity(0.32, bar, i, spread: 0.15)] if r < 0.018 * density * wild
      events[:tambourine] ||= []
      events[:tambourine] << [t, dilla_velocity(0.22, bar, i, spread: 0.1)] if i.even? && r < 0.08 * density * wild
    end
    events[:woodblock] ||= []
    events[:woodblock] << [t, dilla_velocity(0.2, bar, i, spread: 0.06)] if r < 0.01
    events[:agogo] ||= []
    events[:agogo] << [t, dilla_velocity(0.18, bar, i, spread: 0.05)] if r < 0.008
  end

  # Wall-of-noise bar every 32
  (0...(duration / bar_p).floor).each do |bar|
    next unless bar.positive? && bar % 32 == 31
    base = bar * bar_p
    16.times do |step|
      t = (base + step * step_p).round(6)
      events[:glitch] ||= []
      events[:glitch] << [t, dilla_velocity(0.55, bar, step, spread: 0.05), :ind_clap]
    end
  end

  # Trigger-finger miss (intentional dropout)
  %i[kick snare hat].each do |key|
    next unless events[key]
    events[key] = events[key].reject { |hit| rng.rand < 0.04 } if family == :flylo
  end

  events
end

def synth_rim_sample
  len = (0.06 * SAMPLE_RATE).round
  rng = Random.new(42)
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 55.0)
    out[i] = env * (rng.rand * 2.0 - 1.0) * 0.7
  end
  out
end

def synth_clap_sample
  len = (0.14 * SAMPLE_RATE).round
  rng = Random.new(17)
  out = Array.new(len, 0.0)
  3.times do |layer|
    offset = (layer * 0.003 * SAMPLE_RATE).round
    len.times do |i|
      next if i < offset
      t = (i - offset).to_f / SAMPLE_RATE
      env = Math.exp(-t * (30.0 + layer * 8))
      out[i] += env * (rng.rand * 2.0 - 1.0) * (0.35 - layer * 0.08)
    end
  end
  peak = out.map(&:abs).max || 1.0
  out.map { |s| s / [peak, 0.01].max * 0.85 }
end

def synth_tabla_sample
  len = (0.22 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 18.0) * (1.0 - Math.exp(-t * 120.0))
    f = 180.0 + 90.0 * Math.exp(-t * 40.0)
    out[i] = env * Math.sin(2 * Math::PI * f * t) * 0.6
  end
  out
end

# Every voice below used to be one exp(-t*k) shape at a different rate —
# correct that a rim, a woodblock and an agogo bell decay at different
# SPEEDS, wrong that they decay the same SHAPE. Real struck objects
# don't share one physical behavior; each gets the envelope its actual
# physical characteristics: a woodblock has ~zero ring (transient click,
# then silence), a tambourine's metal jingles shimmer well after the
# hand-hit decays (two-stage, not one), a bell's higher partials lose
# energy faster than its fundamental (independent per-partial decay).
def synth_tambourine_sample
  len = (0.16 * SAMPLE_RATE).round
  rng = Random.new(88)
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    hit = Math.exp(-t * 60.0)
    shimmer = Math.exp(-t * 9.0) * 0.35
    out[i] = (rng.rand * 2.0 - 1.0) * (hit * 0.5 + shimmer)
  end
  out
end

def synth_woodblock_sample
  len = (0.04 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    click = t < 0.0015 ? 1.0 : 0.0
    body = Math.exp(-t * 140.0) * Math.sin(2 * Math::PI * 1200.0 * t)
    out[i] = click * 0.4 + body * 0.55
  end
  out
end

def synth_agogo_sample
  len = (0.12 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    fundamental = Math.exp(-t * 16.0) * Math.sin(2 * Math::PI * 660.0 * t)
    overtone = Math.exp(-t * 34.0) * Math.sin(2 * Math::PI * 990.0 * t)
    out[i] = (fundamental * 0.5 + overtone * 0.5) * 0.45
  end
  out
end

def extended_drum_kit(base_kit)
  base_kit.merge(
    rim: synth_rim_sample,
    clap: synth_clap_sample,
    tabla: synth_tabla_sample,
    tambourine: synth_tambourine_sample,
    woodblock: synth_woodblock_sample,
    agogo: synth_agogo_sample,
    ind_kick: load_mono_sample(drum_sample_path("ind_kick.wav")),
    ind_clap: load_mono_sample(drum_sample_path("ind_clap.wav")),
    ind_hat: load_mono_sample(drum_sample_path("ind_hat.wav")),
    ind_stab: load_mono_sample(drum_sample_path("ind_stab.wav"))
  )
rescue StandardError
  base_kit
end

def flylo_primary_drums?
  camel_mode? && flylo_drum_overlay_enabled?
end

# Under Camel/FlyLo primary, default to FlyLo grid ONLY.
# Hybrid pocket+overlay doubled kicks/snares (~10 kicks + ~9 snares/bar) and
# sounded like broken machine-gun drums — set FLYLO_DRUMS_ONLY=0 to re-enable pocket.
def flylo_drums_only?
  flylo_primary_drums? && ENV.fetch("FLYLO_DRUMS_ONLY", "1") != "0"
end

def dilla_pocket_drums_enabled?
  !flylo_drums_only?
end

def kicks_enabled?
  # Pocket kit kicks when overlay-only is off. Prefer POCKET_KICKS;
  # KICKS=1 alone does not force pocket when FLYLO_DRUMS_ONLY=1.
  return false if flylo_drums_only?
  return ENV.fetch("POCKET_KICKS", "1") != "0" if ENV.key?("POCKET_KICKS")
  ENV.fetch("KICKS", "1") != "0"
end

def kick_velocity_scale
  # FlyLo overlay kicks used to inherit the quiet 808 KICK_GAIN (0.38) and vanish.
  default = flylo_primary_drums? ? "0.92" : "0.38"
  ENV.fetch("KICK_GAIN", default).to_f.clamp(0.08, 1.35)
end

def flylo_kick_velocity_scale
  ENV.fetch("FLYLO_KICK_GAIN", flylo_primary_drums? ? "1.15" : "0.85").to_f.clamp(0.2, 2.0)
end

def halftime?
  ENV.fetch("HALFTIME", "0") == "1"
end

def bass_slide_enabled?
  ENV.fetch("BASS_SLIDE", "1") != "0"
end

def backbeat_clap_enabled?
  ENV.fetch("BACKBEAT_CLAP", "1") != "0"
end

def flylo_drum_overlay_enabled?
  ENV.fetch("FLYLO_DRUM_OVERLAY", ENV["STREAM_SOUL"] == "1" ? "1" : "0") != "0"
end

def flylo_overlay_rotate_steps(steps, rot)
  Array(steps).map { |s| (s + rot) % 16 }.uniq.sort
end

def flylo_overlay_grids_for(section)
  @flylo_overlay_grid_cache ||= {}
  bias = ENV.fetch("FLYLO_GRID_BIAS", section.to_s).to_sym
  cache_key = [section, bias, @render_seed || 0]
  return @flylo_overlay_grid_cache[cache_key] if @flylo_overlay_grid_cache.key?(cache_key)
  base = DillaLofiMachine::DRUM_PRESETS[:flylo_abstract]
  shift = FLYLO_OVERLAY_SECTION_SHIFT.fetch(section, 2)
  grids = FLYLO_OVERLAY_GRID_COUNT.times.map do |variant|
    rot = shift + variant
    {
      kicks: flylo_overlay_rotate_steps(base[:kicks], rot),
      snares: flylo_overlay_rotate_steps(base[:snares], rot * 2),
      hats: flylo_overlay_rotate_steps(base[:hats], rot + variant),
      perc: flylo_overlay_rotate_steps(base[:perc], rot + 1)
    }
  end
  @flylo_overlay_grid_cache[cache_key] = grids
end

def flylo_overlay_grid_pick(bar, section, role)
  grids = flylo_overlay_grids_for(section)
  seed = (@render_seed || 0) + section.hash.abs
  idx = (bar + seed + (bar / 4)) % grids.length
  Array(grids[idx].fetch(role, [])).dup
end

def flylo_drum_grid_for(track)
  t = track.to_s
  return nil if t.empty?
  eng = load_learned_engine
  alias_key = eng.dig("track_aliases", t)
  eng.dig("drum_grids", t) ||
    (alias_key && eng.dig("drum_grids", alias_key)) ||
    BUILTIN_LEARNED_ENGINE.dig("drum_grids", t) ||
    (alias_key && BUILTIN_LEARNED_ENGINE.dig("drum_grids", alias_key))
end

def flylo_overlay_grid_hash
  # Camel/dilla style always uses the hip-hop pocket reduction of the Camel stem.
  # Project JSON may supply per-track grids when not in camel/dilla mode.
  grid = if camel_mode?
           FLYLO_CAMEL_DRUM_GRID
         else
           flylo_drum_grid_for(ENV["TRACK"] || "")
         end
  grid = FLYLO_CAMEL_DRUM_GRID if (grid.nil? || !grid.is_a?(Hash)) && flylo_drum_overlay_enabled?
  grid.is_a?(Hash) ? grid : nil
end

def learned_flylo_overlay_steps(role)
  grid = flylo_overlay_grid_hash
  return nil unless grid
  case role
  when :kicks then Array(grid["flylo_kicks"] || grid["kicks"] || grid[:kicks])
  when :snares then Array(grid["flylo_snares"] || grid["snares"] || grid[:snares])
  when :ghost_snares then Array(grid["flylo_ghost_snares"] || grid["ghost_snares"] || [])
  when :hats then Array(grid["flylo_hats"] || grid["hats"] || grid[:hats])
  when :hat_ghosts then Array(grid["flylo_hat_ghosts"] || grid["hat_ghosts"] || [])
  when :perc then Array(grid["flylo_perc"] || grid["perc"] || grid[:perc])
  when :claps then Array(grid["flylo_claps"] || grid["claps"] || [])
  end
end

def flylo_wobble_velocity_mul(bar, step, n: 5)
  seq = (0...n).flat_map { |i| [i, i, (i + 1) % n] }
  idx = (bar * 16 + step) % seq.length
  case seq[idx] % 3
  when 0 then 0.84
  when 1 then 1.0
  else 1.12
  end
end

def flylo_chord_change_duck(bar, chord_bars)
  return 1.0 unless bar.positive? && chord_bars.positive? && (bar % chord_bars).zero?
  ENV.fetch("FLYLO_CHORD_DUCK", "0.72").to_f.clamp(0.45, 1.0)
end

def camel_drum_lock?
  camel_mode? && ENV.fetch("CAMEL_DRUM_LOCK", "1") != "0"
end

def flylo_overlay_density(bar, n_bars, chord_bars:, pad_chords: nil, chord_phases: nil, phrase_bars: nil)
  # Camel lock: always full kit — section density (intro 0.42 × form 0.55 ≈ 0.23)
  # was the main reason the grid felt "missing" / wrong vs Camel.
  return ENV.fetch("FLYLO_OVERLAY_GAIN", "1.2").to_f.clamp(0.9, 1.45) if camel_drum_lock?

  section = dilla_section(bar, n_bars)
  form = form_section_at(bar, n_bars)
  base = FLYLO_OVERLAY_SECTION_DENSITY.fetch(section, 0.85)
  form_mul = form ? FLYLO_OVERLAY_FORM_MUL.fetch(form, 1.0) : 1.0
  phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars: chord_bars, phrase_bars: phrase_bars)
  phase_mul = phase ? phase_gain_multiplier(phase) : 1.0
  duck = flylo_chord_change_duck(bar, chord_bars)
  gain = ENV.fetch("FLYLO_OVERLAY_GAIN", flylo_primary_drums? ? "1.12" : "0.55").to_f
  (base * form_mul * phase_mul * duck * gain).clamp(0.12, 1.45)
end

def flylo_chord_perc_hz(chord)
  return 440.0 unless chord && chord[:hz]&.any?
  root = chord[:hz].min
  # Map chord root into cowbell/agogo register (MIDI 72–84).
  midi = hz_to_midi(root) + 24
  midi_to_hz(midi.clamp(72, 84))
end

# Split roles — snare was on BOTH buses and hit twice (muddy / flammed).
def flylo_sub_bus_mapping
  { flylo_kick: :kick, flylo_perc: :cowbell }
end

def flylo_top_bus_mapping
  { flylo_hat: :hat, flylo_quint: :hat, flylo_snare: :snare, flylo_rim: :rim, flylo_glitch: :ind_stab }
end

def dilla_render_tmp(tag)
  File.join(ROOT, ".dilla_#{tag}.#{Process.pid}.wav")
end

# PID-scoped temp files (drums/harmonic/flylo_*/pads.wav.L0/.smf.mid/etc.)
# are reused across every track iteration within one long-running stream
# process, not just within a single render. If a write is ever interrupted
# (disk full, a signal mid-write) a stale/corrupt derived file can silently
# survive and poison a later, otherwise-unrelated track's render — a
# multi-minute stream then starts failing its final ffmpeg mixdown on every
# track. Wiping this process's own scratch files at the top of every render
# makes each track start from a guaranteed-clean slate instead of trusting
# leftovers from whatever the last track did.
def cleanup_render_scratch!
  Dir.glob(File.join(ROOT, ".dilla_*.#{Process.pid}.*")).each { |f| FileUtils.rm_f(f) }
end

STREAM_LOCK_PATH = File.join(ROOT, ".dilla_stream.lock").freeze

def acquire_stream_lock!
  if File.exist?(STREAM_LOCK_PATH)
    holder = File.read(STREAM_LOCK_PATH).strip.to_i
    if holder.positive?
      begin
        Process.kill(0, holder)
        dmesg_warn("stream lock held by pid #{holder} — exit")
        exit 0
      rescue Errno::ESRCH
        FileUtils.rm_f(STREAM_LOCK_PATH)
      end
    end
  end
  File.write(STREAM_LOCK_PATH, Process.pid.to_s)
  at_exit do
    FileUtils.rm_f(STREAM_LOCK_PATH) if File.exist?(STREAM_LOCK_PATH) &&
                                        File.read(STREAM_LOCK_PATH).strip.to_i == Process.pid
  rescue StandardError
    nil
  end
end

def merge_flylo_dual_bus!(drum_path, sub_path, top_path)
  unless File.file?(drum_path)
    warn "flylo merge: missing drum bus — skipping overlay"
    return
  end
  unless File.file?(sub_path) && File.file?(top_path)
    warn "flylo merge: overlay bus missing (sub=#{File.file?(sub_path)} top=#{File.file?(top_path)}) — skipping"
    return
  end
  merged = "#{drum_path}.merged.#{Process.pid}.wav"
  boost = ENV.fetch("FLYLO_MERGE_BOOST", flylo_primary_drums? ? "1.85" : "1.22").to_f
  sub_vol = (ENV.fetch("FLYLO_SUB_MIX", flylo_primary_drums? ? "1.05" : "0.38").to_f * boost).round(3)
  top_vol = (ENV.fetch("FLYLO_TOP_MIX", flylo_primary_drums? ? "0.88" : "0.32").to_f * boost).round(3)
  # Empty pocket base under FlyLo-only — don't pad-mix silence that dilutes the kit.
  base_vol = ENV.fetch("FLYLO_BASE_DRUM_VOL", flylo_primary_drums? ? "0.15" : "1.0").to_f.round(3)
  # Sub bus used to lowpass @ 220Hz and kill kick click/body (150Hz+beater).
  # Keep boom + mid punch so kicks read on laptop speakers.
  sh! "ffmpeg", "-y", "-i", drum_path, "-i", sub_path, "-i", top_path,
      "-filter_complex",
      "[0:a]volume=#{base_vol}[base];" \
      "[1:a]highpass=f=28,lowpass=f=520,equalizer=f=55:t=o:w=0.75:g=6.5," \
      "equalizer=f=110:t=o:w=1.0:g=4.0,equalizer=f=180:t=o:w=1.1:g=3.0," \
      "volume=#{sub_vol}[sub];" \
      "[2:a]highpass=f=700,equalizer=f=3500:t=o:w=1.3:g=5.5," \
  "equalizer=f=6500:t=o:w=1.4:g=6.5,equalizer=f=9000:t=h:w=1.2:g=4.0," \
  "volume=#{top_vol}[top];" \
      "[base][sub][top]amix=inputs=3:duration=first:normalize=0," \
      "alimiter=limit=0.97:level_out=0.98",
      "-c:a", "pcm_s16le", merged
  FileUtils.mv(merged, drum_path)
end

def drum_drop_enabled?
  ENV.fetch("DRUM_DROP", "1") != "0"
end

def drum_drop_bar?(bar, section)
  return false unless drum_drop_enabled?
  return true if section == :breakdown && bar % 8 == 0
  bar.positive? && bar % 32 == 31
end

def drum_bus_mapping
  # Bass/sub stay on the harmonic bus only — routing them here too doubled
  # the low end on every kick and buried the pad chords in the mix.
  map = {
    snare: :snare, ghost: :ghost, hat: :hat, open: :open_hat,
    poly: :ghost, shaker: :shaker, cowbell: :cowbell,
    poly5: :rim, clap: :clap, rim: :rim, glitch: :ind_stab, tabla: :tabla,
    tambourine: :tambourine, woodblock: :woodblock, agogo: :agogo
  }
  map[:kick] = :kick if kicks_enabled?
  map
end

def sonic_pad_lowpass(sonic)
  sonic&.dig("synth", "pad_lowpass_hz")&.to_i || 3400
end

def sonic_vinyl_level(sonic)
  # VINYL=0 disables the pink-noise bed. VINYL=1..100 scales intensity (default ~35 → mild).
  if ENV.key?("VINYL")
    v = ENV["VINYL"].to_f
    return 0.0 if v <= 0
    return (v / 100.0 * 0.18).clamp(0.0, 0.12).round(3)
  end
  sonic&.dig("synth", "vinyl_noise")&.to_f || 0.08
end

def sonic_bass_shelf(sonic)
  sonic&.dig("synth", "bass_shelf_db")&.to_f || 6.0
end

def build_harm_bus_filter(idx, duration, _cfg, sonic, harm_fade_start, harm_fade_dur, beat_p, _n_bars)
  lp = sonic_pad_lowpass(sonic)
  build_start = (duration * 0.82).round(2)
  # 16 beats, but never longer than the render itself — short (preview/smoke)
  # renders would otherwise produce a negative afade start, which ffmpeg
  # rejects as out of range.
  outro_fade = [(beat_p * 4.0 * 4).round(2), duration].min
  # Pads are the character of the stream — keep them warm and present.
  # Kick space is a gentle HP + sidechain, not stripping pad body (165 Hz HP
  # + −5.5 dB sub cut made progressions inaudible).
  default_vol = if flylo_primary_drums?
                  "1.72"
                elsif deep_render?
                  "1.82"
                else
                  "1.68"
                end
  harm_vol = ENV["DEBUG_HARM_WEIGHT"] || ENV.fetch("HARM_BUS_VOL", default_vol)
  deep = deep_render?
  sub_cut = ENV.fetch("HARM_SUB_CUT_DB", deep ? "-1.8" : (flylo_primary_drums? ? "-2.4" : "-2.2"))
  body_boost = ENV.fetch("HARM_BODY_DB", deep ? "3.2" : (flylo_primary_drums? ? "2.6" : "2.8"))
  mid_boost = ENV.fetch("HARM_MID_DB", deep ? "2.9" : (flylo_primary_drums? ? "2.4" : "2.6"))
  # Chord presence: body + gentle silk shelf (progressions read on small speakers).
  # HARM_PRESENCE_DB / HARM_AIR_DB are crit cherry-pick knobs (defaults keep prior character).
  presence = ENV.fetch("HARM_PRESENCE_DB", flylo_primary_drums? ? "2.2" : "2.4").to_f
  air_g = ENV.fetch("HARM_AIR_DB", flylo_primary_drums? ? "1.6" : "1.2").to_f
  silk_g = flylo_primary_drums? ? [presence * 0.9, 2.0].min : [presence * 0.55, 1.2].min
  air = if flylo_primary_drums?
          "equalizer=f=2400:t=h:w=1800:g=#{silk_g.round(1)},equalizer=f=5200:t=h:w=2800:g=#{air_g.round(1)},"
        else
          "equalizer=f=2800:t=h:w=1800:g=#{air_g.round(1)},"
        end
  harm_hp = ENV.fetch("HARM_HP_HZ", deep ? "95" : (flylo_primary_drums? ? "98" : "110")).to_i
  sub_shelf = ENV.fetch("HARM_SUB_SHELF_DB", deep ? "2.2" : (flylo_primary_drums? ? "1.8" : "1.0")).to_f
  # Longer, smoother pad bloom (qsin) so chords arrive as wash, not a gate.
  fade_in = flylo_primary_drums? ? (harm_fade_dur * 1.35).round(2) : harm_fade_dur
  fade_curve = flylo_primary_drums? ? ":curve=qsin" : ""
  build_cut = flylo_primary_drums? ? -0.8 : -2
  "[#{idx}:a]aformat=channel_layouts=stereo,volume=#{harm_vol}," \
    "highpass=f=#{harm_hp},equalizer=f=72:t=o:w=1.2:g=#{sub_shelf}," \
    "equalizer=f=95:t=h:w=120:g=#{sub_cut}," \
    "equalizer=f=420:t=o:w=1.1:g=#{body_boost},equalizer=f=680:t=h:w=900:g=#{mid_boost}," \
    "equalizer=f=1400:t=h:w=1200:g=#{presence}," \
    "#{air}equalizer=f=#{lp}:t=o:w=1.0:g=0.8," \
    "afade=t=in:st=#{harm_fade_start}:d=#{fade_in}#{fade_curve}," \
    "afade=t=out:st=#{(duration - outro_fade).round(2)}:d=#{outro_fade}#{fade_curve}," \
    "equalizer=f=800:t=h:w=600:g=#{build_cut}:enable='between(t,#{build_start},#{duration})'[harm]"
end

def sidechain_amix_weights
  # Camel: pads duck under kicks but stay the main body (not 2.05:0.78 — that
  # erased chord progressions). Kit still leads the transient.
  d = ENV.fetch("SIDECHAIN_DRUM_WEIGHT", flylo_primary_drums? ? "1.48" : "1.0").to_f
  h = ENV.fetch("SIDECHAIN_HARM_WEIGHT", flylo_primary_drums? ? "1.32" : "1.55").to_f
  [d.round(3), h.round(3)]
end

def flylo_sidechain_filters(drum_label: "[drums]", harm_label: "[harm]")
  dw, hw = sidechain_amix_weights
  # Musical duck: soft attack + longer release so pads bloom back between kicks
  # (was attack=1/release=28 — choppy, made progressions feel gated).
  atk = flylo_primary_drums? ? 8 : 1
  rel = flylo_primary_drums? ? 140 : 28
  ratio = flylo_primary_drums? ? 3.2 : 5
  thr = flylo_primary_drums? ? -22 : -20
  [
    "#{drum_label}asplit=2[dr_dry][dr_sc]",
    "#{harm_label}[dr_sc]sidechaincompress=threshold=#{thr}dB:ratio=#{ratio}:attack=#{atk}:release=#{rel}:level_sc=0.9[harm_sc]",
    "[dr_dry][harm_sc]amix=inputs=2:weights=#{dw} #{hw}:duration=first:normalize=0[sc_mix]"
  ]
end

# Tight kick-triggered duck — short attack/release for MPC pocket, not wash.
def dilla_sidechain_filters(drum_label: "[drums]", harm_label: "[harm]")
  dw, hw = sidechain_amix_weights
  [
    "#{drum_label}asplit=2[dr_dry][dr_sc]",
    "#{harm_label}[dr_sc]sidechaincompress=threshold=-24dB:ratio=5:attack=0.3:release=90:level_sc=0.88[harm_sc]",
    "[dr_dry][harm_sc]amix=inputs=2:weights=#{dw} #{hw}:duration=first:normalize=0[sc_mix]"
  ]
end

def sidechain_filter_chain(cfg)
  return flylo_sidechain_filters unless cfg[:style_family] == :dilla
  ENV.fetch("SIDECHAIN_STYLE", "dilla").to_s == "flylo" ? flylo_sidechain_filters : dilla_sidechain_filters
end

DILLA_ROLE_VELOCITY_BASE = {
  kick_anchor: 0.56, kick_sync: 0.44, snare_back: 0.66, snare_off: 0.48,
  ghost: 0.30, hat_down: 0.50, hat_up: 0.40, open: 0.32, clap: 0.42
}.freeze

def dilla_role_velocity(role, bar, step, sec_gain: 1.0, backbeat: false)
  base = case role
         when :kick_anchor then DILLA_ROLE_VELOCITY_BASE[:kick_anchor]
         when :kick_sync then DILLA_ROLE_VELOCITY_BASE[:kick_sync]
         when :snare then backbeat ? DILLA_ROLE_VELOCITY_BASE[:snare_back] : DILLA_ROLE_VELOCITY_BASE[:snare_off]
         when :ghost then DILLA_ROLE_VELOCITY_BASE[:ghost]
         when :hat_down then DILLA_ROLE_VELOCITY_BASE[:hat_down]
         when :hat_up then DILLA_ROLE_VELOCITY_BASE[:hat_up]
         when :open then DILLA_ROLE_VELOCITY_BASE[:open]
         when :clap then DILLA_ROLE_VELOCITY_BASE[:clap]
         else 0.4
         end
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    perf = @composition_session.performer_profile
    if role == :ghost
      nudge = (ENV["GHOST_BOOST_NUDGE"] || "0").to_f
      base *= (perf[:ghost_boost] + nudge).clamp(0.75, 1.65)
    end
  end
  spread = role == :ghost ? 0.06 : 0.08
  vel = dilla_velocity(base, bar, step, spread: spread) * sec_gain
  # FlyLo primary: kick-forward; snares/hats sit under kick (tops were piercing).
  if flylo_primary_drums?
    mul = case role
          when :kick_anchor, :kick_sync then 1.4
          when :snare, :clap then 1.05
          when :hat_down, :hat_up, :open then 0.88
          when :rim, :ghost then 0.75
          else 1.0
          end
    vel = (vel * mul).clamp(0.05, 0.95)
  end
  vel
end

def spectral_arp_chop_bar?(bar, chord_bars, drums_only, section)
  ENV["SPECTRAL_ARP"] == "1" && !drums_only && (bar % [chord_bars, 4].max).zero? &&
    !%i[breakdown intro].include?(section)
end

def build_drum_bus_filter(cfg, sonic, duration: nil)
  crush_mix = sonic&.dig("synth", "crush_mix")&.to_f
  base = if crush_mix&.positive?
           { bits: 12, samples: 1.69, mix: crush_mix.clamp(0.08, 0.55) }
         elsif cfg[:style_family] == :dilla
           { bits: 11, samples: 1.5, mix: 0.22 }
         else
           { bits: 8, samples: 1.2, mix: 0.12 }
         end
  haas = cfg[:style_family] == :flylo ? ",adelay=0|12" : ""
  # Grit as a per-track compositional choice, not a fixed mix-bus setting
  # — cleaner through the exposition, dirtiest through the development
  # section, pulled back as the build lands. A producer varying the dirt
  # on purpose, not one static crush knob for the whole record.
  crush =
    if duration && duration > 20
      third = (duration / 3.0).round(2)
      [
        "acrusher=bits=#{base[:bits] + 2}:samples=#{base[:samples]}:mix=#{(base[:mix] * 0.5).round(2)}:enable='lt(t,#{third})'",
        "acrusher=bits=#{base[:bits]}:samples=#{base[:samples]}:mix=#{(base[:mix] * 1.4).clamp(0.0, 0.6).round(2)}:enable='between(t,#{third},#{(third * 2).round(2)})'",
        "acrusher=bits=#{base[:bits] + 1}:samples=#{base[:samples]}:mix=#{base[:mix]}:enable='gte(t,#{(third * 2).round(2)})'"
      ].join(",") + ","
    else
      "acrusher=bits=#{base[:bits]}:samples=#{base[:samples]}:mix=#{base[:mix]},"
    end
  kick_boost = if flylo_primary_drums?
                 6.5
               elsif cfg[:style_family] == :dilla
                 0.22
               else
                 0.58
               end
  # After peak-normalize, keep bus fader hot (no quiet 0.24*KICK_GAIN path).
  base_vol = if flylo_primary_drums?
               ENV.fetch("DRUM_BUS_VOL", "1.35").to_f.round(2)
             else
               (0.24 * kick_velocity_scale + 0.1).round(2)
             end
  bus_gain = ENV.fetch("DRUM_BUS_GAIN", flylo_primary_drums? ? "1.4" : "1.0").to_f
  drum_vol = (ENV["DEBUG_DRUM_WEIGHT"] || (base_vol * bus_gain).round(2)).to_s
  drum_air = ENV.fetch("DRUM_AIR_DB", "2.5").to_f
  drum_pres = ENV.fetch("DRUM_PRESENCE_DB", "2.5").to_f
  flylo_eq = if flylo_drum_overlay_enabled?
               "equalizer=f=70:t=o:w=0.9:g=5.0,equalizer=f=200:t=o:w=1:g=2.5," \
                 "equalizer=f=4200:t=o:w=1.2:g=#{(4.0 + drum_pres * 0.35).round(1)}," \
                 "equalizer=f=6500:t=o:w=1.5:g=#{(2.5 + drum_air * 0.4).round(1)},"
             elsif drum_air.positive? || drum_pres.positive?
               "equalizer=f=3500:t=h:w=1600:g=#{drum_pres.round(1)}," \
                 "equalizer=f=7000:t=h:w=2200:g=#{drum_air.round(1)},"
             else
               ""
             end
  "[0:a]aformat=channel_layouts=stereo,volume=#{drum_vol}," \
    "equalizer=f=480:t=h:w=420:g=-1.5,#{flylo_eq}#{crush}" \
    "acompressor=threshold=-14dB:ratio=2.2:attack=3:release=60," \
    "equalizer=f=55:t=o:w=0.7:g=#{kick_boost},highpass=f=25#{haas}[drums]"
end

def build_up_filter_enhanced(input_tag, duration, out_tag: "built")
  start_t = (duration * 0.82).round(2)
  "[#{input_tag}]" \
    "equalizer=f=4500:t=h:w=5000:g=3.5:enable='gte(t,#{start_t})'," \
    "equalizer=f=220:t=o:w=1.8:g=2.5:enable='gte(t,#{start_t})'[#{out_tag}]"
end

def true_peak_guard_for_style(input_tag, cfg, out_tag: "out")
  lufs = cfg[:master_lufs] || MASTER_TARGET_LUFS
  lra = cfg[:master_lra] || MASTER_TARGET_LRA
  if ENV["DEBUG_NO_LOUDNORM"]
    return "[#{input_tag}]alimiter=limit=#{TRUE_PEAK_CEILING_LINEAR}:attack=1:release=40:level=disabled[#{out_tag}]"
  end
  "[#{input_tag}]loudnorm=I=#{lufs}:TP=#{TRUE_PEAK_CEILING_DB}:LRA=#{lra}," \
    "aresample=#{SAMPLE_RATE}," \
    "alimiter=limit=#{TRUE_PEAK_CEILING_LINEAR}:attack=1:release=40:level=disabled[#{out_tag}]"
end

def master_bus_filters_enhanced(input_tag, cfg:, duration: nil, ir_input_idx: nil)
  unless sonitex_enabled?
    filt = ["[#{input_tag}]acompressor=threshold=-20dB:ratio=2:attack=25:release=120:makeup=1.5[premaster0]"]
    filt << mix_bass_chord_balance_filter("premaster0", out_tag: "premaster")
    filt << sub_bass_mono_filter("premaster", out_tag: "monobassed")
    filt << analog_drift_filter("monobassed", out_tag: "drifted")
    darken = cfg.fetch(:mood_darken_strength, 1.0)
    filt << mood_darken_filter("drifted", out_tag: "darkened", strength: darken)
    reverb_out = "darkened"
    if ir_input_idx
      filt << convolution_reverb_filter("darkened", ir_input_idx, mix: cfg[:style_family] == :flylo ? 0.22 : 0.16, out_tag: "reverbed")
      reverb_out = "reverbed"
    end
  if duration && !(camel_mode? && ENV.fetch("CAMEL_NO_BREAK", "1") != "0")
    filt << break_filter(reverb_out, duration, out_tag: "broke")
    filt << build_up_filter_enhanced("broke", duration, out_tag: "built")
    filt << true_peak_guard_for_style("built", cfg)
  else
    filt << true_peak_guard_for_style(reverb_out, cfg)
  end
  return filt
  end
  s = sonitex_config(track: cfg[:track].to_s)
  variant = analog_resolve_variant(track: cfg[:track].to_s)
  filt = []
  filt.concat(sonitex_tape_filters(input_tag, out_tag: "snx_out"))
  filt.concat(analog_emulation_filters("snx_out", variant, out_tag: "ana_out"))
  filt << "[ana_out]alimiter=limit=#{s[:limit]}:level_out=#{s[:level_out]}[premaster0]"
  filt << mix_bass_chord_balance_filter("premaster0", out_tag: "premaster")
  filt << sub_bass_mono_filter("premaster", out_tag: "monobassed")
  # Camel: skip wow drift + heavy darken — they smear the kit and delete HF.
  if camel_mode? && ENV.fetch("CAMEL_CLEAN_MASTER", "1") != "0"
    reverb_out = "monobassed"
  else
    filt << analog_drift_filter("monobassed", out_tag: "drifted")
    darken = cfg.fetch(:mood_darken_strength, 1.0)
    filt << mood_darken_filter("drifted", out_tag: "darkened", strength: darken)
    reverb_out = "darkened"
  end
  if ir_input_idx && !(camel_mode? && ENV.fetch("CAMEL_NO_REVERB", "1") != "0")
    filt << convolution_reverb_filter(reverb_out, ir_input_idx, mix: 0.12, out_tag: "reverbed")
    reverb_out = "reverbed"
  end
  # break_filter bitcrushes + silences mid-track — kills pads/leads. Off on Camel.
  if duration && !(camel_mode? && ENV.fetch("CAMEL_NO_BREAK", "1") != "0")
    filt << break_filter(reverb_out, duration, out_tag: "broke")
    filt << build_up_filter_enhanced("broke", duration, out_tag: "built")
    filt << true_peak_guard_for_style("built", cfg)
  else
    filt << true_peak_guard_for_style(reverb_out, cfg)
  end
  filt
end

def motif_from_chord(chord)
  return [0, 1, 2, 1] unless chord && chord[:hz]&.any?
  tones = chord[:hz].sort
  [0, 1, 2, tones.length > 3 ? 3 : 1]
end

def chord_symbol_key(chord)
  chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "")
end

# Phrase-locked recall — same 4-note figure whenever the same chord symbol returns.
def chord_motif_for(chord)
  sym = chord_symbol_key(chord)
  @chord_motif_cache ||= {}
  return @chord_motif_cache[sym] if motif_recall_enabled? && @chord_motif_cache.key?(sym)
  motif = motif_from_chord(chord)
  @chord_motif_cache[sym] = motif if motif_recall_enabled?
  motif
end

def parse_section_map!(raw)
  raw.split(",").filter_map do |pair|
    name, len = pair.strip.split(":", 2)
    next unless name && len
    kind = SECTION_KIND_ALIASES.fetch(name.downcase, name.downcase.to_sym)
    [kind, len.to_i]
  end
end

def resolve_form_map
  return @resolve_form_map if defined?(@resolve_form_map) && @resolve_form_map
  if ENV["SECTION_MAP"] && !ENV["SECTION_MAP"].empty?
    @resolve_form_map = parse_section_map!(ENV["SECTION_MAP"])
  elsif ENV["FORM"] && !ENV["FORM"].empty?
    preset = FORM_PRESETS[ENV["FORM"].to_sym]
    @resolve_form_map = preset&.fetch(:map, nil)
  end
  @resolve_form_map
end

def form_section_at(bar, n_bars)
  map = resolve_form_map
  return nil unless map&.any?
  cycle_len = map.sum { |_, len| len }
  return nil if cycle_len <= 0
  pos = bar % cycle_len
  cumulative = 0
  map.each do |kind, len|
    return kind if pos < cumulative + len
    cumulative += len
  end
  map.last.first
end

def apply_form_to_cfg!(cfg)
  form = ENV["FORM"]&.to_sym
  preset = FORM_PRESETS[form] if form && FORM_PRESETS.key?(form)
  preset ||= FORM_PRESETS[:camel_32] if %w[camel dilla].include?(ENV["RENDER_MODE"].to_s.downcase)
  preset ||= FORM_PRESETS[:soul_16] if ENV["RENDER_MODE"] == "long_soul" || ENV["RENDER_MODE"] == "golden"
  return cfg unless preset
  cfg.merge(
    intro_bars: preset[:intro_bars] || cfg[:intro_bars],
    phrase_bars: preset[:phrase_bars] || cfg[:phrase_bars],
    form: form || :soul_16
  )
end

def harmony_lead_enabled?
  # Camel default is off (pad-forward); long_soul/golden still default on.
  default = if camel_mode?
              "0"
            elsif %w[long_soul golden].include?(ENV["RENDER_MODE"])
              "1"
            else
              "0"
            end
  ENV.fetch("HARMONY_LEAD", default) != "0"
end

def harmony_lead_mode
  raw = (ENV["HARMONY_LEP_MODE"] || "hybrid").to_sym
  %i[chord scale hybrid].include?(raw) ? raw : :hybrid
end

def harmony_lead_cfg_for(patch = nil)
  style = (ENV["HARMONY_ARP_STYLE"] || "coltrane").to_sym
  {
    style: style,
    subdiv: 8,
    gate: 0.68,
    vel: 0.42,
    arp_styles: patch&.dig(:arp_styles) || %i[coltrane quint_spread call motif updown]
  }
end

def harmony_lead_events(pad_events, cfg, arp_cfg, progression_insight: nil)
  return [] if pad_events.empty? || arp_cfg.nil?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  lead_patch = @render_scale_lead_patch || @render_lead_patch
  octave_mul = 2.0**((lead_patch&.fetch(:octave, 2) || 2) - 1)
  n_bars_est = pad_events.empty? ? 32 : ((pad_events.last[0] / bar_p).ceil + 1)
  events = []
  prev_chord = nil
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    next unless chord && chord[:hz]&.any?
    bar_approx = (time / bar_p).floor.clamp(0, [n_bars_est - 1, 0].max)
    section = dilla_section(bar_approx, n_bars_est)
    next if section == :intro && bar_approx < 2
    progress = i.to_f / [pad_events.length - 1, 1].max
    density = DillaHarmonyLead.section_density(section, progress)
    style_hint = DillaHarmonyLead.arp_style_for_change(prev_chord, chord, insight: progression_insight)
    variation = arp_variation_for_chord(i, chord, cfg, arp_cfg, patch: lead_patch, role: :lead)
    variation[:style] = style_hint if style_hint
    variation[:pattern_mode] = :motif if style_hint == :motif
    variation[:pattern_mode] = :call if style_hint == :call
    subdiv = variation[:subdiv]
    step_p = beat_p / subdiv.to_f
    gate = variation[:gate]
    rng = chord_variation_rng(cfg, i, chord, salt: 12_007)
    swing = cfg[:swing].to_f / 100.0 * step_p * 0.28
    tones = DillaHarmonyLead.harmonic_arp_tones_for_chord(chord, prev_chord: prev_chord, mode: harmony_lead_mode)
    tones = tones.map { |hz| hz * octave_mul }.select { |hz| hz < 2500.0 }
    next if tones.empty?
    pattern = arp_pattern_for_chord(chord, variation, tones.length, rng)
    pattern = chord_motif_for(chord).map { |d| d % tones.length } if variation[:pattern_mode] == :motif
    n_steps = [((sustain / step_p).floor * variation[:n_steps_mul] * density).to_i, 3].max
    step_dur = step_p * gate
    n_steps.times do |step|
      next if arp_rest_step?(step, variation[:rest_prob], i)
      hz = if harmony_lead_mode == :hybrid && step.odd? && (pass = DillaHarmonyLead.passing_tone_hz(chord, step, rng))
             pass
           else
             tones[pattern[step % pattern.length] % tones.length]
           end
      t = arp_step_time(time, step, step_p, swing, variation[:step_jitter], variation)
      break if t >= time + sustain - step_dur * 0.35
      accent = step.zero? || (step % 4).zero?
      vel = (velocity * variation[:vel] * (accent ? 0.92 : 0.78) * density).clamp(0.18, 0.62)
      events << [t, vel, { name: "harmony_lead", hz: [hz] }, step_dur]
    end
    prev_chord = chord
  end
  events.sort_by { |e| e[0] }
end

# Parse root letter from chord name (handles slash chords: D/E → D, not E pedal).
def chord_root_pc(chord)
  raw = chord[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "").sub(/low\z/, "")
  # Upper structure before slash is the harmony root for lead scale.
  head = raw.split("/").first.to_s
  m = head.match(/\A([A-Ga-g])([#b]?)/)
  return nil unless m
  names = %w[C C# D D# E F F# G G# A A# B]
  letter = m[1].upcase
  acc = m[2]
  base = { "C" => 0, "D" => 2, "E" => 4, "F" => 5, "G" => 7, "A" => 9, "B" => 11 }[letter]
  return nil unless base
  pc = base
  pc += 1 if acc == "#"
  pc -= 1 if acc == "b"
  pc % 12
end

# Infer scale mode from chord quality — lead must stay diatonic to this scale.
def chord_scale_mode(chord)
  return :minor unless chord && chord[:hz]&.any?
  name = chord[:name].to_s.downcase
  # Slash chords: quality is on the upper symbol (D/E → major triad on D).
  head = name.split("/").first.to_s
  return :major if head.include?("lyd") || head.include?("maj13") || head.include?("maj9") || head.include?("maj7")
  return :minor if head.include?("dor") || head.include?("m11") || head.include?("m9") || head.include?("m7")
  return :minor if head.match?(/(?:^|[^a-z])m[0-9#b]?/) || head.match?(/[a-g][#b]?m\z/)
  return :major if head.include?("maj") || head.include?("add9") || head.include?("sus")
  # Bare letter or letter+accidental (D, Db, F#) → major triad default.
  return :major if head.match?(/\A[a-g][#b]?\z/)
  # Dominant / mixolydian flavor still uses major scale degrees with b7 via chord tones.
  return :major if head.match?(/7\z/) || head.include?("dom") || head.include?("mix")
  # Interval check from harmonic root (not pedal bass).
  root_pc = chord_root_pc(chord)
  midis = chord[:hz].map { |h| hz_to_midi(h).round }
  if root_pc
    ivs = midis.map { |m| (m - root_pc) % 12 }.uniq
  else
    ivs = chord_intervals_from_hz(chord[:hz])
  end
  return :minor if ivs.include?(3) && !ivs.include?(4)
  return :major if ivs.include?(4) && !ivs.include?(3)
  return :minor if ivs.include?(10) && !ivs.include?(11)
  :major
end

# Semitone degrees for the chord's parent scale (0–11 relative to harmonic root).
def chord_scale_semitones(chord)
  # Prefer richer quality-aware set from harmony-lead heuristics when available.
  if defined?(DillaHarmonyLead) && DillaHarmonyLead.respond_to?(:chord_scale_semitones)
    return DillaHarmonyLead.chord_scale_semitones(chord)
  end
  SCALE_SEMITONES.fetch(chord_scale_mode(chord), SCALE_SEMITONES[:major])
end

def scale_tones_for_chord(chord, lead_low: 58, lead_high: 88)
  return [] unless chord && chord[:hz]&.any?
  root_pc = chord_root_pc(chord)
  root_midi = if root_pc
                # Place root near mid register from chord's center of mass.
                center = chord[:hz].map { |h| hz_to_midi(h) }.sum / chord[:hz].length
                base = center.floor - (center.floor % 12) + root_pc
                base -= 12 while base > center + 6
                base += 12 while base < center - 6
                base
              else
                hz_to_midi(chord[:hz].min).floor
              end
  scale = chord_scale_semitones(chord)
  tones = []
  (-1..3).each do |oct|
    scale.each do |semi|
      midi = root_midi + semi + oct * 12
      tones << midi_to_hz(midi) if midi.between?(lead_low, lead_high)
    end
  end
  tones = tones.uniq.sort
  return tones unless tones.empty?
  chord[:hz].sort.map { |hz| hz * 2.0 }.uniq.sort
end

# Lead tone set: chord tones first (in-register), then scale tones of THIS chord only.
# Guarantees arps/melodies never leave the pad harmony's scale.
def lead_scale_locked_tones_hz(chord, lead_patch: nil, lead_low: 58, lead_high: 84)
  return [] unless chord && chord[:hz]&.any?
  scale_hz = scale_tones_for_chord(chord, lead_low: lead_low, lead_high: lead_high)
  scale_pcs = scale_hz.map { |h| hz_to_midi(h).round % 12 }.uniq
  chord_midis = chord[:hz].map { |h| hz_to_midi(h) }.sort
  # Drop pedal/bass if multi-voice so lead sits above pads.
  chord_midis = chord_midis.drop(1) if chord_midis.length >= 4
  chord_in_scale = chord_midis.filter_map do |m|
    m += 12 while m < lead_low
    m -= 12 while m > lead_high
    next unless scale_pcs.include?(m.round % 12)
    next unless m.between?(lead_low, lead_high)
    midi_to_hz(m)
  end.uniq
  # Prefer chord tones; fill with scale for arpeggio motion.
  ordered = (chord_in_scale + scale_hz).uniq
  return ordered unless ordered.empty?
  # Fallback: force chord tones into lead register (still better than chromatic).
  chord_midis.map do |m|
    m += 12 while m < lead_low
    m -= 12 while m > lead_high
    midi_to_hz(m)
  end.uniq.sort
end

def scale_arp_section_density(section, progress)
  base = case section
         when :intro then 0.38
         when :breakdown then 0.48
         when :build then 0.88
         when :outro then 0.58
         else 0.74
         end
  base * (progress < 0.1 ? 0.7 : 1.0)
end

def pad_arp_section_density(section, progress)
  base = case section
         when :intro then 0.42
         when :breakdown then 0.55
         when :build then 0.92
         when :outro then 0.62
         else 0.78
         end
  base * (progress < 0.12 ? 0.75 : 1.0)
end

# Pad-layer arpeggiator — chord-tone figures on EP/warm layers (separate
# FluidSynth passes; never merged with full held chords on the same layer).
def pad_arp_events(pad_events, cfg, arp_cfg, seed_offset: 0, vel_mul: 1.0)
  return [] if pad_events.empty? || arp_cfg.nil?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars_est = pad_events.empty? ? 32 : ((pad_events.last[0] / bar_p).ceil + 1)
  events = []
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    next unless chord && chord[:hz]&.any?
    bar_approx = (time / bar_p).floor.clamp(0, [n_bars_est - 1, 0].max)
    section = dilla_section(bar_approx, n_bars_est)
    progress = i.to_f / [pad_events.length - 1, 1].max
    density = pad_arp_section_density(section, progress)
    variation = arp_variation_for_chord(i, chord, cfg, arp_cfg, role: :pad)
    subdiv = variation[:subdiv]
    step_p = beat_p / subdiv.to_f
    gate = variation[:gate]
    vel_scale = variation[:vel] * vel_mul
    rng = chord_variation_rng(cfg, i, chord, salt: seed_offset)
    swing = cfg[:swing].to_f / 100.0 * step_p * 0.22
    tones = chord[:hz].sort
    pattern = arp_pattern_for_chord(chord, variation, tones.length, rng)
    n_steps = [((sustain / step_p).floor * variation[:n_steps_mul] * density).to_i, 2].max
    step_dur = step_p * gate
    n_steps.times do |step|
      next if arp_rest_step?(step, variation[:rest_prob], i)
      hz = tones[pattern[step % pattern.length] % tones.length]
      t = arp_step_time(time, step, step_p, swing, variation[:step_jitter], variation)
      break if t >= time + sustain - step_dur * 0.35
      vel = (velocity * vel_scale * (step.zero? ? 1.0 : 0.86 - step * 0.015)).clamp(0.08, 0.48)
      events << [t, vel, { name: "pad_arp", hz: [hz] }, step_dur]
    end
  end
  events.sort_by { |e| e[0] }
end

def pad_midi_events_for_layer(pad_events, cfg, _patch, role:, duration:)
  return pad_events if pad_events.length < 2
  return pad_events unless la_beat_progression_enabled? || ENV["PAD_LEGATO_VAR"] == "1"
  rng = Random.new(patch_cycle_seed(role.hash + pad_events.length))
  beat_p = 60.0 / cfg[:bpm]
  pad_events.map.with_index do |parts, i|
    time, vel, chord, sustain = parts
    legato = rng.rand(0.74..1.14)
    stagger = rng.rand(-0.03..0.06) * beat_p
    [time + stagger, vel * rng.rand(0.9..1.02), chord, sustain * legato]
  end
end

def resolve_midi_fx_for(patch, role:)
  midi_fx_specs_for_role(role, patch)
end

def lead_arp_enabled?
  # Explicit off always wins — was: pad_arp_mode != :held forced leads on even
  # when LEAD_ARP=0, so "pads only" streams still rendered flylo lead soup.
  return false if ENV["LEAD_ARP"] == "0"
  return true if pad_arp_mode != :held
  ENV.fetch("LEAD_ARP", "1") != "0"
end

# When true, lead uses subdiv arps (spiral/skip/…); when false, slow melodic phrases.
def lead_true_arp_mode?
  return false if ENV["MELODIC_LEAD"] == "1" && ENV["LEAD_FORCE_ARP"] != "1"
  return true if ENV["LEAD_FORCE_ARP"] == "1" || ENV["MELODIC_LEAD"] == "0"
  mode = (ENV["LEAD_ARP_MODE"] || lead_arp_mode || "").to_s
  !%w[melodic_soul melodic soul_wash ballad_bloom donuts_shimmer].include?(mode)
end

# Lead arp figure — LEAD_ARP_MODE preset, experimental pool, PAD fallback, or patch midi_arp.
def lead_arp_cfg_for(patch)
  return nil unless lead_arp_enabled?
  key = lead_arp_preset_key
  base = if key && LEAD_ARP_PRESETS[key]
           LEAD_ARP_PRESETS[key].dup
         elsif key && EXPERIMENTAL_LEAD_ARP_PRESETS[key]
           EXPERIMENTAL_LEAD_ARP_PRESETS[key].dup
         elsif key && PAD_ARP_PRESETS[key]
           PAD_ARP_PRESETS[key].dup.tap { |h| h[:vel] = (h[:vel] * 1.85).clamp(0.38, 0.58) }
         end
  if base
    styles = (base[:arp_styles] || []) | Array(patch&.dig(:arp_styles)) | ARP_PATTERN_BUILDERS.keys.first(8)
    base.merge(patch&.dig(:midi_arp) || {})
        .merge(arp_styles: styles.uniq)
  else
    patch&.dig(:midi_arp) || {
      style: @render_arp_style || :spiral,
      subdiv: 8,
      gate: (patch&.fetch(:gate, 0.72) || 0.72) * 0.88,
      vel: 0.55,
      arp_styles: %i[spiral skip_up euclidean flylo_wobble pingpong]
    }
  end
end

def lead_arp_section_density(section, progress)
  base = case section
         when :intro then 0.55
         when :breakdown then 0.65
         when :build then 1.0
         when :outro then 0.72
         else 0.85
         end
  base * (progress < 0.08 ? 0.75 : 1.0)
end

def xlead_arp_section_density(section, progress)
  base = case section
         when :intro then 0.78
         when :breakdown then 0.88
         when :build then 1.0
         when :outro then 0.82
         else 0.94
         end
  base * (progress < 0.05 ? 0.88 : 1.0)
end

def melodic_lead_mode?
  return false if lead_true_arp_mode?
  return false if ENV["MELODIC_LEAD"] == "0"
  return true if ENV.fetch("MELODIC_LEAD", "0") != "0"
  mode = (ENV["LEAD_ARP_MODE"] || lead_arp_mode || "").to_s
  %w[soul_wash melodic_soul melodic donuts_shimmer ballad_bloom].include?(mode)
end

# Upper chord tones only, clamped to a singable register (no doubled bass mud).
# Always filtered to the chord's scale (see lead_scale_locked_tones_hz).
def lead_chord_tones_hz(chord, lead_patch: nil)
  lead_scale_locked_tones_hz(chord, lead_patch: lead_patch)
end

# Melodic phrase: 1 note/beat, motif 0-2-1-3, voice-led from previous phrase.
# Tones are scale-locked to the current pad chord.
def lead_melodic_phrase_for_chord(time, velocity, chord, sustain, chord_i, cfg, lead_patch,
                                  role: :lead, prev_end_hz: nil)
  tones = lead_scale_locked_tones_hz(chord, lead_patch: lead_patch)
  return [] if tones.empty?
  beat_p = 60.0 / cfg[:bpm]
  # Quarter notes (subdiv 1 per beat) — readable top line, not arp soup.
  step_p = beat_p
  gate = 0.9
  step_dur = step_p * gate
  n_steps = [(sustain / step_p).floor, 2].max
  n_steps = [n_steps, 6].min
  # Motif over chord tones; rotate per chord so the line breathes.
  base = [0, 2, 1, 3, 1, 0]
  rot = chord_i % [tones.length, 3].max
  pattern = base.map { |d| (d + rot) % tones.length }
  # Voice-lead start: pick tone nearest previous phrase end.
  if prev_end_hz
    start_i = tones.each_with_index.min_by { |hz, _| (hz - prev_end_hz).abs }&.last || 0
    pattern = [start_i] + pattern.reject.with_index { |_, i| i.zero? }
  end
  vel_base = (velocity * 0.62).clamp(0.38, 0.78)
  events = []
  n_steps.times do |step|
    # Leave air every other chord on the last beat.
    next if step == n_steps - 1 && (chord_i % 2).zero? && n_steps > 2
    idx = pattern[step % pattern.length] % tones.length
    hz = tones[idx]
    t = time + step * step_p
    break if t >= time + sustain - step_dur * 0.25
    accent = step.zero?
    vel = (vel_base * (accent ? 1.05 : 0.88)).clamp(0.34, 0.82)
    tag = role == :xlead ? "xlead" : "lead_arp"
    events << [t, vel, { name: tag, hz: [hz] }, step_dur]
  end
  events
end

def lead_arp_events_for_chord(time, velocity, chord, sustain, chord_i, cfg, arp_cfg, lead_patch,
                              role: :lead, n_bars_est: nil, skip_intro: false, progress: nil,
                              prev_end_hz: nil)
  return [] unless chord && chord[:hz]&.any? && arp_cfg
  if role != :xlead && melodic_lead_mode?
    return lead_melodic_phrase_for_chord(time, velocity, chord, sustain, chord_i, cfg, lead_patch,
                                         role: role, prev_end_hz: prev_end_hz)
  end
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars_est ||= ((time / bar_p).ceil + 4)
  bar_approx = (time / bar_p).floor.clamp(0, [n_bars_est - 1, 0].max)
  section = dilla_section(bar_approx, n_bars_est)
  # Keep lead present from bar 0 so streams always have a top line.
  if skip_intro && section == :intro && bar_approx < 1 && role != :xlead
    return []
  end
  progress ||= chord_i.to_f / [n_bars_est, 1].max
  density = role == :xlead ? xlead_arp_section_density(section, progress) : lead_arp_section_density(section, progress)
  density = [density, 0.75].max if role != :xlead
  variation = arp_variation_for_chord(chord_i, chord, cfg, arp_cfg, patch: lead_patch, role: role)
  # Melodic (slow phrase) only when melodic_lead_mode? — otherwise full subdiv arps.
  if role != :xlead && melodic_lead_mode?
    variation = variation.merge(
      style: arp_cfg[:style] || :updown,
      subdiv: [arp_cfg.fetch(:subdiv, 2), 4].min,
      rest_prob: [variation[:rest_prob].to_f, 0.22].max,
      pattern_mode: :motif,
      n_steps_mul: 0.55,
      step_jitter: [variation[:step_jitter].to_f, 0.008].min
    )
  elsif role != :xlead
    # True arp: denser 8ths/16ths, rotate styles from preset pool.
    styles = Array(arp_cfg[:arp_styles])
    styles = %i[spiral skip_up euclidean flylo_wobble] if styles.empty?
    style = styles[chord_i % styles.length] || arp_cfg[:style] || :spiral
    variation = variation.merge(
      style: style,
      subdiv: [arp_cfg.fetch(:subdiv, 8), 6].max.clamp(4, 12),
      rest_prob: [variation[:rest_prob].to_f, 0.12].min,
      pattern_mode: :arp,
      n_steps_mul: 1.0,
      step_jitter: [variation[:step_jitter].to_f, 0.012].min
    )
  end
  subdiv = variation[:subdiv]
  step_p = beat_p / subdiv.to_f
  gate = variation[:gate]
  vel_scale = (variation[:vel] * 1.25).clamp(0.42, 0.72)
  rng = chord_variation_rng(cfg, chord_i, chord, salt: role == :xlead ? 12_007 : 9907)
  swing = cfg[:swing].to_f / 100.0 * step_p * (role == :xlead ? 0.42 : 0.28)
  # Strict: only pitches from this chord's parent scale (+ chord tones).
  tones = lead_scale_locked_tones_hz(chord, lead_patch: lead_patch)
  tones = scale_tones_for_chord(chord) if tones.empty?
  return [] if tones.empty?
  pattern = arp_pattern_for_chord(chord, variation, tones.length, rng)
  n_steps = [((sustain / step_p).floor * variation[:n_steps_mul]).to_i, role == :xlead ? 3 : 4].max
  n_steps = [n_steps, melodic_lead_mode? ? 8 : 16].min if role != :xlead
  step_dur = step_p * gate
  vel_lo = role == :xlead ? 0.32 : 0.34
  vel_hi = role == :xlead ? 0.9 : 0.85
  events = []
  n_steps.times do |step|
    rest_p = role == :xlead ? [variation[:rest_prob].to_f * 0.35, 0.08].min : [variation[:rest_prob].to_f, 0.18].max
    next if arp_rest_step?(step, rest_p, chord_i)
    hz = tones[pattern[step % pattern.length] % tones.length]
    t = arp_step_time(time, step, step_p, swing, variation[:step_jitter], variation)
    break if t >= time + sustain - step_dur * 0.3
    accent = step.zero? || (step % 4).zero?
    vel = (velocity * vel_scale * (accent ? 1.08 : 0.9) * density).clamp(vel_lo, vel_hi)
    tag = role == :xlead ? "xlead" : "lead_arp"
    events << [t, vel, { name: tag, hz: [hz] }, step_dur]
  end
  events
end

# Continuous lead arpeggiator — chord-tone figures on the lead voice (8th/16th
# subdivisions, patch-specific pattern + MIDI FX). Rendered on its own FluidSynth
# stem (lead_arp.wav); distinct from scale_lead and creative-lead bursts.
def lead_arp_events(pad_events, cfg, arp_cfg)
  return [] if pad_events.empty? || arp_cfg.nil?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  lead_patch = @render_lead_patch
  n_bars_est = pad_events.empty? ? 32 : ((pad_events.last[0] / bar_p).ceil + 1)
  prev_end = nil
  events = []
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    progress = i.to_f / [pad_events.length - 1, 1].max
    chunk = lead_arp_events_for_chord(time, velocity, chord, sustain, i, cfg, arp_cfg, lead_patch,
                                      role: :lead, n_bars_est: n_bars_est, progress: progress,
                                      prev_end_hz: prev_end).to_a
    prev_end = chunk.last&.dig(2, :hz)&.first if chunk.any?
    events.concat(chunk)
  end
  events.sort_by { |e| e[0] }
end

# Continuous scale-locked arp on every pad chord — same root/mode as the pad,
# stepping 16ths through scale degrees for the full chord sustain.
def lead_events_scale_arp(pad_events, cfg, duration: nil, n_bars: nil)
  return [] if pad_events.empty?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars ||= duration ? (duration / bar_p).ceil : 32
  scale_patch = @render_scale_lead_patch
  base_gate = scale_patch&.fetch(:gate, 0.62) || 0.62
  base_cfg = { style: @render_scale_arp_style || :updown, subdiv: 4, gate: base_gate, vel: 0.38 }
  events = []
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    next unless chord && chord[:hz]&.any?
    bar_approx = (time / bar_p).floor.clamp(0, n_bars - 1)
    section = dilla_section(bar_approx, n_bars)
    next if section == :intro && bar_approx < 2
    progress = i.to_f / [pad_events.length - 1, 1].max
    density = scale_arp_section_density(section, progress)
    scale_tones = lead_scale_locked_tones_hz(chord, lead_patch: scale_patch)
    scale_tones = scale_tones_for_chord(chord) if scale_tones.empty?
    next if scale_tones.empty?
    variation = arp_variation_for_chord(i, chord, cfg, base_cfg, patch: scale_patch, role: :scale_lead)
    subdiv = variation[:subdiv]
    step_p = beat_p / subdiv.to_f
    gate = variation[:gate]
    rng = chord_variation_rng(cfg, i, chord, salt: 4423)
    pattern = arp_pattern_for_chord(chord, variation, scale_tones.length, rng)
    n_steps = [((sustain / step_p).floor * variation[:n_steps_mul]).to_i, 4].max
    n_steps = [n_steps, (sustain / step_p).ceil].min
    step_dur = step_p * gate * 0.9
    swing = cfg[:swing].to_f / 100.0 * step_p * 0.35
    n_steps.times do |step|
      next if arp_rest_step?(step, variation[:rest_prob] * 0.65, i)
      hz = scale_tones[pattern[step % pattern.length] % scale_tones.length]
      t = arp_step_time(time, step, step_p, swing, variation[:step_jitter], variation)
      break if t >= time + sustain - step_dur * 0.4
      accent = step.zero? || (step % 4).zero?
      vel = (velocity * (accent ? 0.44 : 0.34) * density * variation[:vel]).clamp(0.14, 0.58)
      events << [t, vel, { name: "scale_arp", hz: [hz] }, step_dur]
    end
  end
  events
end

def arp_degrees_for(style, tone_count, rng)
  builder = ARP_PATTERN_BUILDERS[style] || ARP_PATTERN_BUILDERS[:updown]
  raw = builder.arity >= 2 ? builder.call(tone_count, rng) : builder.call(tone_count)
  raw.map { |d| d % tone_count }
end

# Per-chord RNG — same progression, different figure/timing every change.
def chord_variation_rng(cfg, chord_i, chord, salt: 0)
  seed = (cfg[:track].to_s.hash.abs % 100_000) + (@render_seed || 0) + chord_i * 131 +
         (chord[:name].to_s.hash.abs % 5000) + salt
  Random.new(seed)
end

def arp_styles_for_patch(patch, fallback_style)
  patch&.dig(:arp_styles) || [fallback_style || :updown]
end

# Euclidean/ratchet/random_walk/stutter/burst already exist in
# ARP_PATTERN_BUILDERS but every patch's own arp_styles list sticks to the
# safe up/down/updown/pingpong shapes — this is the IDM/Warp-leaning
# opt-in that reaches for the shapes that are already built but unused.
ARP_IDM_STYLES = %i[euclidean ratchet random_walk stutter burst].freeze

# Each pad/lead chord gets its own arp style, subdiv, gate, swing, and pattern shape.
def arp_variation_for_chord(chord_i, chord, cfg, base_arp_cfg, patch: nil, role: :lead)
  rng = chord_variation_rng(cfg, chord_i, chord, salt: role.hash.abs)
  styles = base_arp_cfg[:arp_styles] || arp_styles_for_patch(patch, base_arp_cfg[:style])
  style = styles[chord_i % styles.length]
  style = ARP_IDM_STYLES.sample(random: rng) if ENV["ARP_IDM_BIAS"] == "1" && rng.rand < 0.65
  if role == :pad
    subdiv_pool = [base_arp_cfg.fetch(:subdiv, 8), 4, 6, 8].uniq
    pattern_modes = %i[style motif sparse stagger call]
    return {
      style: style,
      subdiv: subdiv_pool[chord_i % subdiv_pool.length],
      gate: base_arp_cfg.fetch(:gate, 0.75) * rng.rand(0.92..1.06),
      vel: base_arp_cfg.fetch(:vel, 0.22) * rng.rand(0.88..1.1),
      time_offset: rng.rand(-0.02..0.05),
      step_jitter: rng.rand(0.0..0.012),
      rest_prob: rng.rand(0.0..0.06),
      pattern_mode: pattern_modes[chord_i % pattern_modes.length],
      swing_mul: rng.rand(0.75..1.15),
      n_steps_mul: rng.rand(0.72..1.0)
    }
  end
  if role == :xlead
    style = ARP_PATTERN_BUILDERS.keys.sample(random: rng) if rng.rand < 0.55
    subdiv_pool = [3, 4, 6, 8, 12, 16].uniq
    return {
      style: style,
      subdiv: subdiv_pool[rng.rand(subdiv_pool.length)],
      gate: base_arp_cfg.fetch(:gate, 0.5) * rng.rand(0.7..1.28),
      vel: base_arp_cfg.fetch(:vel, 0.58) * rng.rand(0.82..1.38),
      time_offset: rng.rand(-0.05..0.12),
      step_jitter: rng.rand(0.0..0.035),
      rest_prob: rng.rand(0.0..0.1),
      pattern_mode: %i[style motif retrograde sparse call stagger burst stutter].sample(random: rng),
      swing_mul: rng.rand(0.5..1.55),
      n_steps_mul: rng.rand(0.55..1.15)
    }
  end
  style = ARP_PATTERN_BUILDERS.keys.sample(random: rng) if rng.rand < 0.3
  subdiv_pool = [base_arp_cfg.fetch(:subdiv, 8), 3, 4, 6, 8, 12].uniq
  {
    style: style,
    subdiv: subdiv_pool[rng.rand(subdiv_pool.length)],
    gate: base_arp_cfg.fetch(:gate, 0.62) * rng.rand(0.82..1.14),
    vel: base_arp_cfg.fetch(:vel, 0.5) * rng.rand(0.75..1.2),
    time_offset: rng.rand(-0.035..0.09),
    step_jitter: rng.rand(0.0..0.022),
    rest_prob: rng.rand(0.0..0.14),
    pattern_mode: lead_pattern_mode(chord_i, cfg, rng),
    swing_mul: rng.rand(0.6..1.4),
    n_steps_mul: rng.rand(0.5..1.0)
  }
end

# Every arp pattern was picked fresh per chord with no thread between phrases
# — a melody that never restates or develops an idea, just cycles shapes.
# chord_motif_for already gives a stable, chord-symbol-consistent figure and
# :motif already exists as a pattern_mode; this just deliberately reaches for
# it at phrase openings (not every chord — variation still matters) so a
# phrase can actually be recognized as "the same idea" when it returns.
def phrase_start_chord?(chord_i, cfg)
  chord_bars = cfg[:chord_bars]
  phrase_bars = cfg[:phrase_bars]
  return chord_i.zero? unless chord_bars && phrase_bars && chord_bars.positive?
  chords_per_phrase = (phrase_bars / chord_bars.to_f).round
  return chord_i.zero? if chords_per_phrase <= 0
  (chord_i % chords_per_phrase).zero?
end

def lead_pattern_mode(chord_i, cfg, rng)
  modes = %i[style motif retrograde sparse call stagger]
  return modes.sample(random: rng) unless motif_recall_enabled?
  return :motif if phrase_start_chord?(chord_i, cfg) && rng.rand < 0.7
  modes.sample(random: rng)
end

def arp_pattern_for_chord(chord, variation, tone_count, rng)
  case variation[:pattern_mode]
  when :motif
    chord_motif_for(chord).map { |d| d % tone_count }
  when :retrograde
    arp_degrees_for(variation[:style], tone_count, rng).reverse
  when :sparse
    arp_degrees_for(variation[:style], tone_count, rng).each_with_index.filter_map { |d, i| (i.even? || rng.rand < 0.42) ? d : nil }
  when :call
    chord_motif_for(chord).map { |d| d % tone_count } +
      arp_degrees_for(variation[:style], tone_count, rng).first(4)
  when :stagger
    base = arp_degrees_for(variation[:style], tone_count, rng)
    base.flat_map.with_index { |d, i| i.even? ? [d, d] : [d] }
  else
    arp_degrees_for(variation[:style], tone_count, rng)
  end
end

def arp_rest_step?(step, rest_prob, chord_i)
  return false if rest_prob < 0.02
  Random.new(chord_i * 97 + step * 13).rand < rest_prob
end

def arp_step_time(time, step, step_p, swing, jitter, variation)
  t = time + variation[:time_offset] + step * step_p
  t += (step.odd? ? swing * variation[:swing_mul] : 0.0)
  t += jitter * ((step % 3) - 1)
  t
end

# Pad chord entry + chop placement — not locked to bar%4 templates.
def dilla_chord_change_variation(chord_i, bar, section, feel, step_p, chord)
  cfg = dilla_resolve_config
  rng = chord_variation_rng(cfg, chord_i, chord, salt: 7711)
  base_pad_offset = DillaHarmony.pad_entry_late(cfg, feel, step_p)
  sustain_mul = DillaHarmony.pad_sustain_mul(cfg, section, rng)
  chop_density = DillaHarmony.chop_density(cfg, section)
  chop_templates = [
    [1, 5, 9, 13], [2, 6, 10, 14], [1, 9, 13], [3, 7, 11, 15],
    [0, 4, 8, 12], [1, 3, 7, 11], [2, 5, 9, 14], [4, 8, 12, 15],
    [1, 7, 13], [2, 8, 10, 14], [5, 9, 13], [0, 6, 10, 14], [3, 9, 15]
  ]
  chop_steps = chop_templates[(chord_i + bar) % chop_templates.length].dup
  chop_steps.delete_at(rng.rand(chop_steps.length)) if rng.rand < 0.38 && chop_steps.length > 2
  chop_steps << [0, 3, 6, 10, 14].sample(random: rng) if rng.rand < 0.28 && chop_density > 0.3
  if chop_density < 0.35
    keep = (chop_steps.length * chop_density * 2.5).ceil.clamp(1, chop_steps.length)
    chop_steps = chop_steps.sort_by { |s| rng.rand }.first(keep).sort
  end
  {
    pad_offset: base_pad_offset + rng.rand(-step_p * 0.4..step_p * 0.9),
    sustain_mul: sustain_mul,
    chop_steps: chop_steps.uniq.sort,
    chop_jitter: rng.rand(-0.028..0.028),
    pad_vel_mul: rng.rand(0.86..1.1),
    double_pad: rng.rand < 0.2 && section == :main,
    double_pad_delay: step_p * rng.rand(0.2..0.85),
    double_pad_vel: rng.rand(0.18..0.32)
  }
end

def lead_section_chance(section, progress)
  case section
  when :intro then 0.06
  when :breakdown then 0.12
  when :build then 0.48
  when :outro then 0.18
  else progress > 0.78 ? 0.42 : 0.26
  end
end

# Occasional lead bursts — not every chord gets an arp. When they fire, use
# intricate patterns (euclidean, fibonacci, flylo wobble, etc.) with
# call-and-response and patch-specific gate lengths.
def lead_events_creative(pad_events, cfg, duration: nil, n_bars: nil)
  return [] if pad_events.empty?
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars ||= duration ? (duration / bar_p).ceil : 32
  seed = (cfg[:track].to_s.hash.abs % 100_000) + (@render_seed || 0) + 8801
  rng = Random.new(seed)
  leitmotif = leitmotif_for(pad_events)
  arp_style = @render_arp_style || :updown
  lead_patch = @render_lead_patch
  gate_mul = (lead_patch&.fetch(:gate, 0.82) || 0.82)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    gate_mul *= @composition_session.performer_profile[:gate_mul]
  end
  octave_mul = 2.0 ** ((lead_patch&.fetch(:octave, 2) || 2) - 2)
  events = []
  burst_remaining = 0
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    next unless chord && chord[:hz]&.any?
    bar_approx = (time / bar_p).floor.clamp(0, n_bars - 1)
    section = dilla_section(bar_approx, n_bars)
    progress = i.to_f / [pad_events.length - 1, 1].max
    motif_cell = if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
                   @composition_session.motif_for_bar(bar_approx)
                 end
    leitmotif = motif_cell.degrees_for_playback if motif_cell
    if burst_remaining.positive?
      burst_remaining -= 1
    else
      chance = if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
                 prof = @composition_session.profile_at(bar_approx)
                 (prof[:lead] * prof[:melodic_density]).clamp(0.05, 0.92)
               else
                 lead_section_chance(section, progress)
               end
      chance += 0.15 if i % 11 == 5
      next unless rng.rand < chance
      burst_remaining = rng.rand(1..3)
    end
    # Scale-locked only — no chromatic approach tones off the pad harmony.
    tones = lead_scale_locked_tones_hz(chord, lead_patch: lead_patch)
    tones = scale_tones_for_chord(chord) if tones.empty?
    next if tones.empty?
    if octave_mul != 1.0
      tones = tones.map { |hz| hz * octave_mul }.select { |hz|
        m = hz_to_midi(hz)
        m.between?(55, 90)
      }
      tones = lead_scale_locked_tones_hz(chord, lead_patch: lead_patch) if tones.empty?
    end
    burst_cfg = { style: arp_style, subdiv: 2, gate: gate_mul, vel: 0.72 }
    variation = arp_variation_for_chord(i, chord, cfg, burst_cfg, patch: lead_patch, role: :creative_lead)
    pattern = case variation[:pattern_mode]
              when :motif then motif_from_chord(chord).map { |d| d % tones.length }
              when :retrograde then invert_motif(leitmotif)
              when :call then leitmotif + invert_motif(leitmotif)
              when :sparse then leitmotif.each_with_index.filter_map { |d, si| (si.even? || rng.rand < 0.5) ? d : nil }
              else [leitmotif, invert_motif(leitmotif), leitmotif.reverse,
                    arp_degrees_for(variation[:style], tones.length, rng),
                    leitmotif + invert_motif(leitmotif)][i % 5]
              end
    pattern = arp_pattern_for_chord(chord, variation, tones.length, rng) if rng.rand < 0.38
    subdiv = variation[:subdiv]
    step_dur = [(sustain || 1.0) / (pattern.length * subdiv.to_f), 0.045].max
    step_dur *= 1.35 if section == :build
    step_dur *= variation[:n_steps_mul].clamp(0.55, 1.0)
    swing_push = (cfg[:quintuplet] ? step_dur * 0.04 : 0.0) * variation[:swing_mul]
    pattern.each_with_index do |degree, step|
      next if arp_rest_step?(step, variation[:rest_prob], i + 500)
      hz = tones[degree % tones.length]
      # Diatonic approach: previous scale degree, never chromatic half-step.
      if step.zero? && i.positive? && tones.length > 1
        idx = tones.index(hz) || 0
        approach = tones[(idx - 1) % tones.length]
      else
        approach = hz
      end
      t = time + variation[:time_offset] + 0.04 + step * step_dur + (step.odd? ? swing_push : 0.0) +
          variation[:step_jitter] * ((step % 3) - 1) +
          DillaGroove.melody_time_offset(bar_approx, step, beat_p)
      vel = (velocity * (0.88 - step * 0.04)).clamp(0.18, 0.95)
      vel *= 1.12 if section == :build
      pan = cfg[:stereo_pan] ? (step.even? ? -0.45 : 0.45) : (step.even? ? -0.12 : 0.12)
      events << [t, vel, { name: "lead", hz: [approach] }, step_dur * gate_mul, pan]
    end
    next unless rng.rand < 0.55 && i.positive?
    answer_style = ARP_PATTERN_BUILDERS.keys.sample(random: rng)
    answer_pat = arp_degrees_for(answer_style, tones.length, rng)
    conv_offset = if composition_enabled?
                    DillaComposition::Conversation.answer_offset(:lead, beat_p)
                  else
                    0.0
                  end
    answer_offset = conv_offset + pattern.length * step_dur * 0.45
    answer_oct = 1.0
    answer_pat.each_with_index do |degree, step|
      hz = tones[degree % tones.length] * answer_oct
      t = time + 0.04 + answer_offset + step * step_dur * 1.1
      vel = (velocity * 0.42 * (1.0 - step * 0.03)).clamp(0.1, 0.55)
      pan = cfg[:stereo_pan] ? (step.even? ? 0.55 : -0.55) : (step.even? ? 0.18 : -0.18)
      events << [t, vel, { name: "lead_answer", hz: [hz] }, step_dur * gate_mul * 0.75, pan]
    end
  end
  events
end

def lead_events_enhanced(pad_events, cfg)
  lead_events_creative(pad_events, cfg)
end

def warm_dilla_pad_post_enhanced(path, sonic, cfg)
  return path unless tool_available?("ffmpeg")
  lp = sonic_pad_lowpass(sonic)
  tmp = "#{path}.pad_tmp.wav"
  fluidsynth = defined?(@render_used_fluidsynth_pad) && @render_used_fluidsynth_pad
  filt = if fluidsynth
           [
             "aformat=channel_layouts=stereo",
             "lowpass=f=#{lp}:width_type=q:width=0.82",
             "equalizer=f=260:t=o:w=1.0:g=1.2",
             "equalizer=f=900:t=h:w=800:g=0.8",
             "equalizer=f=3200:t=h:w=1400:g=0.6",
             "aecho=0.34:0.44:90|180:0.2|0.1",
             "chorus=0.34:0.54:30|40:0.14|0.1:0.18|0.14:0.92|1.15",
             "acompressor=threshold=-22dB:ratio=1.5:attack=65:release=280:makeup=1.5",
             "volume=1.1",
             "alimiter=limit=0.96:level_out=0.98"
           ]
         else
           patch_fx = @render_warm_patch&.dig(:fx) || @render_ep_patch&.dig(:fx)
           [
             "aformat=channel_layouts=stereo",
             "lowpass=f=#{lp}:width_type=q:width=0.88",
             "equalizer=f=260:t=o:w=1.0:g=2.0",
             "equalizer=f=520:t=h:w=700:g=1.8",
             "equalizer=f=1100:t=o:w=0.9:g=-0.6",
             "equalizer=f=3200:t=h:w=1600:g=1.0",
             ("tremolo=f=3.2:d=0.06" if cfg[:style_family] == :dilla),
             "aecho=0.32:0.42:100|180:0.2|0.1",
             "chorus=0.36:0.56:30|40:0.16|0.12:0.2|0.18:0.95|1.2",
             patch_fx,
             "acompressor=threshold=-24dB:ratio=1.6:attack=60:release=260:makeup=1.6",
             "volume=1.12",
             "alimiter=limit=0.96:level_out=0.98"
           ]
         end
  sh! "ffmpeg", "-y", "-i", path, "-af", filt.compact.join(","), "-c:a", "pcm_s16le", tmp
  FileUtils.mv(tmp, path)
  path
end

GENERATED_STYLE_ROUTES = {
  coltrane: :generate_coltrane_changes,
  backdoor: :generate_backdoor_progression,
  slash: :generate_slash_progression,
  modal_interchange: :generate_modal_interchange
}.freeze

def route_generated_style(style, root_hz:, mode:, length:, seed:)
  meth = GENERATED_STYLE_ROUTES[style]
  return send(meth, root_hz:, mode:, length:, seed:) if meth
  nil
end

DEFAULT_BPM = 86.0
DEFAULT_BARS = 88
SAMPLE_RATE = 44_100
BASS_SUSTAIN_SEC = (ENV["BASS_SUSTAIN"] || 1.45).to_f
BASS_DECAY_RATE = (ENV["BASS_DECAY"] || 1.15).to_f
# Voicemails mix pipeline (make.rb heritage)
VOICEMAILS_BEAT = ENV.fetch("BEAT", File.join(OUTPUT_DIR, "Voicemails.mp3"))
MIX_DUR = 146
MIX_BPM = 118.6
LIVESET_MIN = (ENV["LIVESET_MIN"] || 60).to_i
LIVESET_PERIODS = [97, 113, 127, 149, 163, 179, 193, 211, 227, 251].freeze
VOCALS = {
  processed: File.join(ROOT, "vocals_processed.wav"),
  precise:   File.join(ROOT, "vocals_precise.wav"),
  original:  File.join(ROOT, "vocals_original_pitch.wav"),
}.freeze
# Analog renderer tuning
ANALOG_ROOTS = [43.65, 49.00, 51.91, 38.89, 46.25].freeze
ANALOG_PRIMES = [97, 109, 127, 149, 167, 191, 223, 251].freeze
ANALOG_CFG = {
  lowpass_hz: 2600,
  sp_bits: 12,
  sp_ratio: 44_100.0 / 26_040.0,
  tape_dc: 0.05,
  chorus_delay_l_ms: 9,
  chorus_delay_r_ms: 13,
  vinyl_level: 0.06,
  bad_tune_spike_cents: 16.0,
}.freeze
HIP_HOP_BPM = 86
HIP_HOP_BARS = 8
TECHNO_BPM = 142
TECHNO_BARS = 8
HEDD = "val(0)+0.28*val(0)*val(0)*(gt(val(0),0)-lt(val(0),0))+0.12*val(0)*val(0)*val(0)|" \
       "val(1)+0.28*val(1)*val(1)*(gt(val(1),0)-lt(val(1),0))+0.12*val(1)*val(1)*val(1)"
PITCH_CLASSES = %w[C Db D Eb E F Gb G Ab A Bb B].freeze
PAD_CHORDS = [
  { name: "Fm9", hz: [174.61, 207.65, 261.63, 311.13, 392.00] },
  { name: "Dbmaj9", hz: [138.59, 174.61, 207.65, 261.63, 311.13] },
  { name: "Cm9", hz: [130.81, 155.56, 196.00, 233.08, 293.66] },
  { name: "Ebmaj9", hz: [155.56, 196.00, 233.08, 293.66, 349.23] },
  { name: "Abmaj9", hz: [207.65, 261.63, 311.13, 392.00, 466.16] },
  { name: "Dm9", hz: [146.83, 174.61, 220.00, 261.63, 329.63] },
  { name: "Gm9", hz: [196.00, 233.08, 293.66, 349.23, 440.00] },
  # "+9" means a natural 9th (C#), not the b9 (C) this had.
  { name: "Bm7b5+9", hz: [123.47, 146.83, 174.61, 220.00, 277.18] },
  { name: "E altered", hz: [164.81, 196.00, 233.08, 293.66, 349.23] },
  { name: "Am9", hz: [110.00, 130.81, 164.81, 196.00, 246.94] },
  { name: "Bbm9", hz: [116.54, 138.59, 174.61, 207.65, 261.63] },
  { name: "Gbmaj9", hz: [92.50, 116.54, 138.59, 174.61, 207.65] },
  { name: "C cluster", hz: [130.81, 138.59, 196.00, 233.08, 311.13] },
  { name: "C7#9 Hendrix", hz: [130.81, 155.56, 196.00, 233.08, 277.18] },
  # Was a byte-for-byte copy of Fmaj9's voicing (b7 instead of maj7, no 13th).
  # Real Fmaj13: root, 3, 5, 13, maj7.
  { name: "Fmaj13", hz: [174.61, 220.00, 261.63, 293.66, 329.63] },
  # Had a b7 (Eb) instead of a major 7th — that's actually F9 (dominant), not
  # Fmaj9. Real Fmaj9: root, 3, 5, maj7 (E), 9.
  { name: "Fmaj9", hz: [174.61, 220.00, 261.63, 329.63, 392.00] },
  { name: "Cmaj9", hz: [130.81, 164.81, 196.00, 246.94, 293.66] },
  { name: "E7b9", hz: [82.41, 103.83, 123.47, 146.83, 174.61] },
  { name: "Bm7b5", hz: [123.47, 146.83, 174.61, 220.00, 261.63] },
  { name: "Em9", hz: [164.81, 196.00, 246.94, 293.66, 369.99] },
  { name: "G7", hz: [196.00, 246.94, 293.66, 349.23, 392.00] }
].freeze
# Get Dis Money / Herbie Sunlight stack — vocoder chords over E pedal (Ethan Hein).
EXTENDED_NINTH_CHORDS = [
  # Was E-G-A-D-G: a 3rd (G) with no 5th and no 9th — not actually a sus4 or
  # a 9 chord despite the name, and the "/D" bass wasn't even in the voicing.
  # Real E9sus4 (root E, 4th A, 5th B, b7 D, 9th F#), keeping the same E
  # pedal bass as every other chord in this table.
  { name: "E9sus4/D", hz: [82.41, 220.00, 246.94, 293.66, 369.99] },
  # Ethan Hein: D/E functions as E9sus4 (Get Dis Money / Come Running To Me).
  { name: "D/E", hz: [82.41, 146.83, 220.00, 246.94, 293.66] },
  { name: "Db/E", hz: [82.41, 277.18, 311.13, 349.23, 415.30] },
  { name: "C/E", hz: [82.41, 261.63, 329.63, 392.00, 493.88] },
  { name: "Bm/E", hz: [82.41, 246.94, 293.66, 369.99, 440.00] },
  { name: "Bbm/E", hz: [82.41, 233.08, 277.18, 349.23, 415.30] },
  { name: "Am/E", hz: [82.41, 220.00, 261.63, 329.63, 392.00] },
  { name: "E9sus4", hz: [82.41, 220.00, 246.94, 293.66, 369.99] }
].freeze
# COMMANDS is derived from the DISPATCH table at the bottom of this file —
# one source of truth for dispatch, help, and the debug introspection dump.
# Analog stock characters — digital signal equivalents of film stock data.
# noise_amp: RMS amplitude of the noise floor (≈tape hiss level)
# sat_drive: tanh waveshaper drive (1.0 = light tube warmth, 3.0 = heavy tape saturation)
# rolloff_hz: high-frequency bandwidth limit (anti-halation backing ↔ tape formulation)
# wow_rate: LFO rate in Hz for pitch modulation (reciprocity failure ↔ capstan speed variance)
# wow_depth: LFO depth [0,1] (tape tension variation)
# warmth_db: low-frequency shelf boost in dB (color temperature ↔ tonal weight)
AUDIO_STOCKS = {
  tape_250:  { noise_amp: 0.0018, sat_drive: 1.4, rolloff_hz: 14_500, wow_rate: 0.40, wow_depth: 0.003, warmth_db: 2.5 },
  tape_500:  { noise_amp: 0.0035, sat_drive: 2.2, rolloff_hz: 12_500, wow_rate: 0.45, wow_depth: 0.004, warmth_db: 4.0 },
  vinyl:     { noise_amp: 0.005, sat_drive: 1.0, rolloff_hz: 18_000, wow_rate: 0.50, wow_depth: 0.015, warmth_db: 2.0 },
  cassette:  { noise_amp: 0.008, sat_drive: 0.8, rolloff_hz: 10_500, wow_rate: 0.50, wow_depth: 0.025, warmth_db: 1.5 },
  acetate:   { noise_amp: 0.011, sat_drive: 1.1, rolloff_hz:  9_500, wow_rate: 0.80, wow_depth: 0.040, warmth_db: 5.0 },
}.freeze

# Analog grade presets — concept map:
# tape_saturation  ↔ H&D film curve (soft-knee waveshaper)
# analog_noise     ↔ Newson-Delon grain (noise floor with midtone envelope)
# harmonic_bloom   ↔ halation (even-harmonic enrichment, energy bleeding adjacent)
# spectral_warmth  ↔ color temperature EQ
# parallel_compress↔ bleach bypass (parallel NY compression)
# multiband_tone   ↔ split toning / split grade
# wow_flutter      ↔ reciprocity failure (pitch/time modulation)
# vinyl_crackle    ↔ faded print (aging artifacts)
# transient_sharpen↔ micro-contrast (presence boost)
# stereo_width     ↔ chromatic aberration (M/S spread)
GRADE_PRESETS = {
  tape_warm:   { fx: %w[spectral_warmth tape_saturation analog_noise transient_sharpen], stock: :tape_250 },
  tape_hot:    { fx: %w[tape_saturation harmonic_bloom analog_noise multiband_tone],      stock: :tape_500 },
  vinyl_press: { fx: %w[spectral_warmth analog_noise wow_flutter vinyl_crackle],          stock: :vinyl    },
  lo_fi:       { fx: %w[spectral_warmth tape_saturation analog_noise wow_flutter],        stock: :cassette },
  broadcast:   { fx: %w[parallel_compress multiband_tone transient_sharpen],              stock: :tape_250 },
  sp1200:      { fx: %w[tape_saturation analog_noise transient_sharpen],                  stock: :tape_500 },
  sonitex:     { fx: %w[spectral_warmth tape_saturation harmonic_bloom analog_noise wow_flutter vinyl_crackle], stock: :acetate },
  vinyl_lab:   { fx: %w[spectral_warmth tape_saturation harmonic_bloom platter_wow vinyl_crackle stylus_mistrack needle_drop_fade analog_noise], stock: :vinyl },
  dub_chamber: { fx: %w[spectral_warmth tape_saturation dub_delay chamber_reverb analog_noise], stock: :tape_500 },
}.freeze

# Sonitex STX-1260 — Tone Projects lo-fi life-span workstation (VST).
# Signal flow per SOS / Tone Projects: mastering comp → M/S → distortion (tape sat) →
# vinyl bandwidth (resonant head-bump) → wow/flutter → sibilance/phone → noise →
# digital sampler (SP-1200: 12-bit, ~26.04 kHz) → output comp → limiter.
# SP-1200 subset: crush_sr 1.69 → 44100/1.69 ≈ 26095 Hz (KVR / jones-y).
SONITEX_STX1260 = {
  comp_threshold: -22, comp_ratio: 3.4, comp_attack: 18, comp_release: 130, comp_makeup: 2.2,
  stereo_width: 1.16, side_gain: 0.78,
  dist_pre_emph_db: 3.2, dist_pre_lp: 4800, dist_drive: 1.55, dist_mix: 0.68, dist_dc: 0.025,
  hf_rolloff: 13_800, lf_rolloff: 34, head_bump_hz: 64, head_bump_db: 3.0, warmth_db: 2.4,
  groove_wear_lp: 5200,
  wow_rate: 0.26, wow_depth: 0.007, flutter_hz: 4.4, flutter_depth: 0.0045,
  sibilance_db: 1.6, sibilance_hz: 5600, phone_lp: 4400,
  hiss_amp: 0.0028, pop_rate: 0.00035, pop_amp: 0.14, click_rate: 0.0006,
  crush_bits: 12, crush_sr: 1.69, crush_mix: 0.32, crush_post_lp: 3600,
  out_comp_threshold: -19, out_comp_ratio: 2.6, out_comp_makeup: 1.8,
  limit: 0.92, level_out: 0.90
}.freeze
# Legacy extreme chain (prior STX-1269 emulation) — SONITEX=extreme
SONITEX_STX1269 = {
  comp_threshold: -26, comp_ratio: 5.2, comp_attack: 8, comp_release: 95, comp_makeup: 4.0,
  stereo_width: 1.32, side_gain: 0.62,
  dist_pre_emph_db: 5.5, dist_pre_lp: 3600, dist_drive: 3.1, dist_mix: 0.82, dist_dc: 0.07,
  hf_rolloff: 10_800, lf_rolloff: 45, head_bump_hz: 58, head_bump_db: 5.2, warmth_db: 6.0,
  groove_wear_lp: 3600,
  wow_rate: 0.32, wow_depth: 0.014, flutter_hz: 5.6, flutter_depth: 0.018,
  sibilance_db: 2.8, sibilance_hz: 5200, phone_lp: 3600,
  hiss_amp: 0.0055, pop_rate: 0.0008, pop_amp: 0.22, click_rate: 0.0012,
  crush_bits: 10, crush_sr: 1.69, crush_mix: 0.48, crush_post_lp: 2800,
  out_comp_threshold: -17, out_comp_ratio: 3.2, out_comp_makeup: 2.5,
  limit: 0.86, level_out: 0.88
}.freeze
SONITEX_PRESETS = {
  classic:  SONITEX_STX1260,
  subtle:   SONITEX_STX1260.merge(
    crush_mix: 0.18, crush_bits: 14, hiss_amp: 0.003, pop_rate: 0.00025, pop_amp: 0.12,
    dist_drive: 1.25, dist_mix: 0.52, wow_depth: 0.004, stereo_width: 1.08
  ),
  scuzz:    SONITEX_STX1260.merge(
    crush_mix: 0.48, crush_bits: 10, hiss_amp: 0.009, pop_rate: 0.0012, pop_amp: 0.32,
    wow_depth: 0.012, dist_drive: 2.1, hf_rolloff: 11_200, warmth_db: 4.2
  ),
  sp1200:   SONITEX_STX1260.merge(
    crush_bits: 12, crush_sr: 1.69, crush_mix: 0.52, crush_post_lp: 3000,
    dist_drive: 1.45, hf_rolloff: 12_600, head_bump_hz: 58, head_bump_db: 3.8
  ),
  cassette: SONITEX_STX1260.merge(
    head_bump_hz: 88, head_bump_db: 4.2, hf_rolloff: 10_800, wow_depth: 0.011,
    flutter_depth: 0.009, hiss_amp: 0.008, warmth_db: 3.6, crush_mix: 0.22
  ),
  extreme:  SONITEX_STX1269,
  donuts_warm: SONITEX_STX1260.merge(
    crush_bits: 12, crush_sr: 1.85, crush_mix: 0.42, crush_post_lp: 2100,
    dist_drive: 1.48, dist_mix: 0.62, hf_rolloff: 2200, groove_wear_lp: 2600,
    head_bump_hz: 58, head_bump_db: 5.2, warmth_db: 5.5, lf_rolloff: 38,
    wow_depth: 0.009, flutter_depth: 0.005, stereo_width: 1.12, hiss_amp: 0.0022,
    out_comp_threshold: -17, out_comp_ratio: 3.2, out_comp_makeup: 2.4,
    limit: 0.86, level_out: 0.88
  ),
  # Stream/soul: warm pad glue + enough air for chords/hats (not a 2 kHz blanket).
  donuts_soul: SONITEX_STX1260.merge(
    crush_bits: 13, crush_sr: 1.4, crush_mix: 0.14, crush_post_lp: 8_500,
    dist_drive: 1.12, dist_mix: 0.32, hf_rolloff: 14_200, groove_wear_lp: 12_000,
    head_bump_hz: 58, head_bump_db: 2.2, warmth_db: 3.0, lf_rolloff: 30,
    wow_depth: 0.0035, flutter_depth: 0.0015, stereo_width: 1.12, hiss_amp: 0.0005,
    phone_lp: 13_500, sibilance_db: 0.8,
    out_comp_threshold: -21, out_comp_ratio: 2.0, out_comp_makeup: 1.2,
    limit: 0.95, level_out: 0.97
  ),
  heavy:    SONITEX_STX1269.merge(
    crush_bits: 8, crush_sr: 2.05, crush_mix: 0.58, crush_post_lp: 2400,
    dist_drive: 3.6, dist_mix: 0.88, dist_pre_emph_db: 6.2, dist_dc: 0.09,
    hiss_amp: 0.006, pop_rate: 0.0009, pop_amp: 0.24, click_rate: 0.0012,
    wow_depth: 0.016, flutter_depth: 0.012, stereo_width: 1.36,
    hf_rolloff: 9600, warmth_db: 7.0, head_bump_db: 6.0, groove_wear_lp: 3200,
    phone_lp: 3100, sibilance_db: 3.4,
    out_comp_threshold: -15, out_comp_ratio: 4.0, out_comp_makeup: 3.0,
    limit: 0.84, level_out: 0.86
  )
}.freeze
# Creative analog grade stacks — post-Sonitex film-stock emulation.
ANALOG_CHAIN_VARIANTS = {
  acetate:    { stock: :acetate,   fx: %w[spectral_warmth tape_saturation harmonic_bloom wow_flutter vinyl_crackle analog_noise] },
  sp1200:     { stock: :tape_500,  fx: %w[tape_saturation multiband_tone transient_sharpen analog_noise stereo_width] },
  cassette:   { stock: :cassette,  fx: %w[spectral_warmth wow_flutter analog_noise vinyl_crackle harmonic_bloom] },
  broadcast:  { stock: :tape_250,  fx: %w[parallel_compress multiband_tone transient_sharpen stereo_width spectral_warmth] },
  lo_fi:      { stock: :cassette,  fx: %w[spectral_warmth tape_saturation wow_flutter harmonic_bloom analog_noise] },
  vinyl_hot:  { stock: :vinyl,     fx: %w[spectral_warmth harmonic_bloom vinyl_crackle platter_wow stylus_mistrack analog_noise stereo_width] },
  sonitex:    { stock: :acetate,   fx: %w[tape_saturation harmonic_bloom wow_flutter vinyl_crackle multiband_tone print_through_echo reel_splice_clicks analog_noise] },
  vinyl_lab:  { stock: :vinyl,     fx: %w[spectral_warmth tape_saturation harmonic_bloom platter_wow vinyl_crackle stylus_mistrack needle_drop_fade analog_noise] },
  dub_chamber: { stock: :tape_500, fx: %w[spectral_warmth tape_saturation dub_delay chamber_reverb haas_jitter analog_noise] },
  # NastyVCS-style "Summing Phasy" (75ips) — console glue + phase width after Sonitex texture.
  # No analog_noise / crackle here: Camel stream already has a light vinyl bed; extra
  # grain stacks into "lots of noise" and buries pads.
  summing_phasy: {
    stock: :tape_250,
    fx: %w[parallel_compress harmonic_bloom stereo_width haas_jitter multiband_tone spectral_warmth tape_saturation]
  }
}.freeze
ANALOG_CHAIN_ROTATE = %i[acetate sp1200 cassette broadcast lo_fi vinyl_hot sonitex vinyl_lab dub_chamber summing_phasy].freeze
# Wild mashups — stream auto-iterate picks from these for authentic analog chaos.
ANALOG_CHAIN_WILD = {
  mpc_donut:     { stock: :tape_500,  fx: %w[tape_saturation harmonic_bloom wow_flutter vinyl_crackle print_through_echo analog_noise] },
  ghost_tape:    { stock: :cassette,  fx: %w[spectral_warmth platter_wow stylus_mistrack needle_drop_fade reel_splice_clicks analog_noise] },
  dub_plate:     { stock: :vinyl,     fx: %w[platter_wow vinyl_crackle dub_delay chamber_reverb haas_jitter harmonic_bloom] },
  spring_haze:   { stock: :acetate,   fx: %w[spring_reverb spectral_warmth tape_saturation wow_flutter stereo_width] },
  sp1200_crush:  { stock: :tape_500,  fx: %w[tape_saturation multiband_tone transient_sharpen analog_noise parallel_compress] },
  broadcast_lab: { stock: :tape_250,  fx: %w[parallel_compress multiband_tone plate_reverb haas_jitter spectral_warmth] },
  chamber_dust:  { stock: :cassette,  fx: %w[chamber_reverb vinyl_crackle wow_flutter harmonic_bloom analog_noise stereo_width] }
}.freeze
ANALOG_CHAIN_WILD_ROTATE = ANALOG_CHAIN_WILD.keys.freeze
SONITEX_ROTATE_STREAM = %i[donuts_warm cassette sp1200 subtle scuzz classic heavy].freeze
CONV_REVERB_ROTATE = %w[chamber plate spring 0].freeze
ANALOG_WILD_STOCKS = %i[tape_500 cassette vinyl acetate tape_250].freeze
GRADE_FX_POOL = %w[
  spectral_warmth tape_saturation harmonic_bloom analog_noise wow_flutter vinyl_crackle
  transient_sharpen stereo_width parallel_compress multiband_tone platter_wow stylus_mistrack
  print_through_echo reel_splice_clicks haas_jitter spring_reverb plate_reverb chamber_reverb dub_delay
].freeze
SOUL_TRACK_FAMILY = %i[
  maj7_minor_cycle quartal_west_coast slow_ballad_wash minor_iv_loop neo_soul neo_soul_pocket
  electronium_loop electronium_classic players_measured warm_minor_arc slash_neo_soul erykah_minor
  aydin_modal_quartal aydin_jazz_turn bach_circle_descent bach_descending_bass
  timeless_authentic jazz_ballad_waltz ii_v_i_major ii_v_i_minor glasper_quartal
  fourth_third_sixth_second_turn long_soul golden
].freeze
# Arrangement forms — section lengths in bars (repeats to fill n_bars).
FORM_PRESETS = {
  soul_16: {
    map: [[:intro, 4], [:main, 8], [:build, 4]],
    intro_bars: 4, phrase_bars: 16
  },
  soul_32: {
    map: [[:intro, 4], [:main, 8], [:build, 8], [:turn, 8], [:outro, 4]],
    intro_bars: 4, phrase_bars: 32
  },
  donuts_time: {
    map: [[:intro, 4], [:main, 8], [:turn, 8], [:outro, 4]],
    intro_bars: 4, phrase_bars: 16
  },
  camel_32: {
    map: [[:intro, 8], [:main, 12], [:build, 6], [:turn, 4], [:outro, 2]],
    intro_bars: 8, phrase_bars: 32
  }
}.freeze
SECTION_KIND_ALIASES = {
  "a" => :main, "a2" => :build, "b" => :turn, "turnaround" => :turn
}.freeze
# Chains with real vinyl playback (not tape) get a turntable-motor sub-bass rumble bed.
TURNTABLE_RUMBLE_VARIANTS = %i[vinyl_hot vinyl_lab acetate sonitex].freeze
# Internal presets — output filenames use neutral TAPE_RENDER_CATALOG codes only.
NINTH_VOICING_TRACKS = %i[
  syncopated_slash_ninth chromatic_planing ascending_minor_stack minor_soul_loop suspended_minor_turn major_relative_minor_cycle dominant_minor_resolve
  syncopated_slash_alt minor_cycle_descent minor_stepwise_cycle major7_relative_minor_turn minor_major_ninth_pair minor_stepwise_ascent suspended_minor_close
].freeze
NINTH_VOICING_BARS = { syncopated_slash_ninth: 63, syncopated_slash_alt: 63, minor_soul_loop: 64 }.freeze
TAPE_RENDER_CATALOG = [
  { preset: :syncopated_slash_ninth,      out: "session_01", bars: 63 },
  { preset: :chromatic_planing,         out: "session_02", bars: 64 },
  { preset: :ascending_minor_stack,        out: "session_03", bars: 64 },
  { preset: :minor_soul_loop,            out: "session_04", bars: 64 },
  { preset: :suspended_minor_turn,         out: "session_05", bars: 64 },
  { preset: :major_relative_minor_cycle,            out: "session_06", bars: 64 },
  { preset: :dominant_minor_resolve,       out: "session_07", bars: 64 },
  { preset: :syncopated_slash_alt,     out: "session_08", bars: 63 },
  { preset: :minor_cycle_descent,     out: "session_09", bars: 64 },
  { preset: :minor_stepwise_cycle,         out: "session_10", bars: 64 },
  { preset: :major7_relative_minor_turn,             out: "session_11", bars: 64 },
  { preset: :minor_major_ninth_pair,          out: "session_12", bars: 64 },
  { preset: :minor_stepwise_ascent,            out: "session_13", bars: 64 },
  { preset: :suspended_minor_close, out: "session_14", bars: 64 }
].freeze
INDUSTRIAL_TECHNO_BPM = 135.0
INDUSTRIAL_TECHNO_BARS = 128

# J Dilla / Jay Dee (James Yancey, 1974–2006, Detroit).
# MPC3000 finger-drummed grooves: NOT random "drunk" slop — cyclic, repeating
# microtiming (Charnas: Dilla Time; d-buckner/dilla-time on GitHub).
# Snares/claps land early → hats/kicks/bass feel late (Ethan Hein, Get Dis Money).
# Producer timbre + stereo width dominate hip-hop feel (ar5iv 2410.21297).
#
# Slum Village chord maps sourced from:
#   Ethan Hein — Get Dis Money, Thelonius transcriptions
#   jdillabasslines.wordpress.com — Fantastic Vol. 2 BPM + bass phrasing
#   Hooktheory — Donuts "Time" Ab major IV–iii–vi–ii–V
# Independent micro-timing layers (ms): snare early, kick late, hats later.
# Ranges are cyclic (repeating pocket), not random drunk-slop.
MICROTIMING_MS = {
  kick_anchor: 1..6,
  kick_sync: 6..18,
  snare: -28..-10,
  ghost: -10..6,
  hat_down: -2..8,
  hat_up: 12..32,
  open: 8..20,
  clap: -22..-8,
  bass: 18..34,
  pad: 4..16
}.freeze
# Curated 16-step drum phrases per feel — rotated bar-to-bar instead of
# probabilistic organic generation. Kicks/snares/ghosts/hats are authored
# separately so each voice has its own pocket.
DRUM_PATTERN_SETS = {
  timeless: {
    kicks: [
      [0, 8, 10, 15], [0, 3, 9, 11, 14], [0, 6, 10, 13], [0, 2, 7, 10, 14],
      [0, 5, 9, 12, 15], [0, 1, 8, 11, 14], [0, 4, 7, 10, 13], [0, 3, 6, 10, 14],
      [0, 7, 11, 14], [0, 2, 5, 9, 13], [0, 8, 12, 15], [0, 4, 10, 14]
    ],
    snares: [[4, 12], [4, 12], [4, 11, 12], [4, 10, 12], [4, 12, 14], [3, 12]],
    ghosts: [
      [2, 5, 9, 13], [1, 6, 10, 14], [3, 7, 11, 15], [2, 6, 10, 13],
      [1, 4, 8, 12], [3, 5, 9, 14], [2, 7, 11], [1, 5, 10, 13]
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 1, 3, 5, 7, 9, 11, 13, 15],
      [0, 2, 4, 6, 8, 10, 12, 14, 1, 9], [0, 2, 4, 6, 8, 10, 12, 14, 5, 13],
      [0, 3, 6, 9, 12, 15, 2, 8, 14], [0, 2, 4, 6, 8, 10, 12, 14, 7, 11]
    ],
    opens: [6, 14]
  },
  loose_pocket: {
    kicks: [
      [0, 5, 9, 13], [0, 2, 7, 11, 14], [0, 6, 10, 15], [0, 3, 8, 12, 14],
      [0, 1, 6, 10, 13], [0, 4, 7, 11, 15], [0, 2, 9, 12, 14], [0, 5, 8, 10, 14],
      [0, 3, 7, 10, 13], [0, 6, 11, 14]
    ],
    snares: [[4, 12], [3, 11, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12], [4, 12]],
    ghosts: [
      [1, 3, 5, 7, 9, 11, 13, 15], [2, 4, 6, 8, 10, 12, 14], [1, 4, 7, 10, 13],
      [3, 6, 9, 12, 15], [2, 5, 8, 11, 14], [1, 5, 9, 13], [3, 7, 11, 15], [2, 6, 10]
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 1, 5, 9, 13], [0, 2, 4, 6, 8, 10, 12, 14, 3, 7, 11, 15],
      [0, 1, 3, 4, 6, 8, 10, 12, 14], [0, 2, 4, 6, 8, 10, 12, 14, 5, 13],
      [0, 2, 4, 6, 8, 10, 12, 14, 1, 9], [0, 2, 4, 6, 8, 10, 12, 14, 7, 15]
    ],
    opens: [6, 10, 14]
  },
  syncopated_slash_ninth: {
    kicks: [
      [0, 7, 11, 14], [0, 3, 8, 10, 14], [0, 5, 9, 13], [0, 2, 6, 10, 15],
      [0, 4, 7, 11, 14], [0, 1, 7, 10, 13], [0, 6, 9, 12, 14], [0, 3, 7, 11, 15]
    ],
    snares: [[4, 12], [4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12], [4, 9, 12]],
    ghosts: [
      [2, 5, 8, 12], [3, 6, 10, 14], [1, 4, 9, 13], [2, 7, 11, 15],
      [3, 5, 10, 13], [1, 6, 11, 14]
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 2, 4, 6, 8, 10, 12, 14, 3, 7, 11, 15],
      [0, 4, 8, 12, 3, 11], [0, 2, 4, 6, 8, 10, 12, 14, 1, 3, 9, 11]
    ],
    opens: [6, 14]
  },
  chromatic_planing: {
    kicks: [
      [0, 4, 8, 12], [0, 3, 6, 9, 12, 15], [0, 2, 5, 8, 11, 14], [0, 1, 4, 7, 10, 13],
      [0, 5, 9, 13], [0, 2, 6, 10, 14], [0, 4, 7, 11, 14], [0, 3, 8, 12, 15]
    ],
    snares: [[4, 12], [4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12]],
    ghosts: [
      [2, 6, 10, 14], [1, 5, 9, 13], [3, 7, 11, 15], [2, 5, 9, 12, 14]
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14], [1, 3, 5, 7, 9, 11, 13, 15],
      [0, 2, 4, 6, 8, 10, 12, 14], [1, 3, 5, 7, 9, 11, 13, 15]
    ],
    opens: [6, 14]
  },
  organic: {
    kicks: [
      [0, 8, 11, 14], [0, 4, 7, 10, 14], [0, 3, 6, 10, 13], [0, 5, 9, 12, 15],
      [0, 2, 7, 10, 14], [0, 1, 6, 9, 13], [0, 4, 8, 11, 14], [0, 3, 7, 10, 14]
    ],
    snares: [[4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12], [4, 9, 12]],
    ghosts: [
      [3, 6, 10, 13], [2, 5, 9, 14], [1, 7, 11, 15], [4, 8, 12],
      [3, 5, 8, 11], [2, 6, 10, 14]
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 1, 3, 4, 6, 8, 10, 12, 14],
      [0, 2, 4, 6, 8, 10, 12, 14, 1, 9, 13], [0, 2, 4, 6, 8, 10, 12, 14, 5, 7]
    ],
    opens: [6, 14]
  },
  techno_house: {
    kicks: [[0, 4, 8, 12]],
    snares: [[4, 12], [4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12]],
    ghosts: [[10], [6, 10], [10, 14], []],
    hats: [
      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
      [0, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15],
      [0, 1, 3, 4, 6, 7, 9, 10, 12, 13, 15],
      [0, 2, 4, 5, 7, 8, 10, 11, 13, 14]
    ],
    opens: [6, 14]
  },
  default: {
    kicks: [
      [0, 7, 10, 14], [0, 3, 8, 11, 14], [0, 5, 9, 13], [0, 2, 6, 10, 14],
      [0, 4, 7, 11, 15], [0, 1, 7, 10, 13], [0, 6, 10, 14], [0, 3, 7, 10, 12, 14]
    ],
    snares: [[4, 12], [4, 12], [4, 10, 12], [4, 12, 14], [4, 11, 12]],
    ghosts: [
      [2, 5, 9, 13], [3, 6, 11, 14], [1, 4, 8, 12], [2, 7, 10, 15],
      [3, 5, 9, 12], [1, 6, 10, 13]
    ],
    hats: [
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11], [0, 1, 3, 4, 6, 8, 10, 11, 13, 14],
      [0, 2, 4, 6, 8, 10, 12, 14], [0, 2, 4, 6, 8, 10, 12, 14, 1, 9]
    ],
    opens: [6, 14]
  }
}.merge(
  DillaLofiMachine::DRUM_PRESETS.transform_values do |p|
    {
      kicks: [p[:kicks]],
      snares: [p[:snares]],
      hats: [p[:hats]],
      ghosts: [p[:ghosts]],
      opens: [6, 14],
      claps: [p[:claps]],
      perc: [p[:perc]]
    }
  end
).freeze

LOFI_DRUM_FEELS = DillaLofiMachine::DRUM_PRESETS.keys.freeze

# Authored fill phrases — snare runs, kick clusters, ghost chatter into phrase ends.
DRUM_FILL_SETS = {
  snare: [
    [10, 11, 12, 13, 14, 15], [8, 9, 10, 11, 12, 14], [6, 8, 10, 12, 13, 14, 15],
    [9, 10, 11, 12, 14, 15], [11, 12, 13, 14, 15], [8, 10, 12, 13, 14, 15]
  ],
  kicks: [
    [12, 13, 14, 15], [10, 12, 14, 15], [8, 10, 12, 14, 15], [13, 14, 15], [11, 13, 15]
  ],
  ghosts: [
    [13, 14, 15], [11, 13, 15], [12, 14, 15], [10, 12, 14, 15]
  ]
}.freeze

# FlyLo abstract overlay — second drum schedule on top of Dilla pocket (wonky 16ths).
FLYLO_OVERLAY_SECTION_DENSITY = {
  intro: 0.42, main: 1.0, build: 0.88, turn: 0.92, breakdown: 0.35, outro: 0.48
}.freeze
FLYLO_OVERLAY_FORM_MUL = {
  intro: 0.55, main: 1.0, build: 0.92, turn: 0.95, breakdown: 0.38, outro: 0.5
}.freeze
FLYLO_OVERLAY_SECTION_SHIFT = {
  intro: 0, main: 2, build: 4, turn: 6, breakdown: 1, outro: 3
}.freeze
FLYLO_OVERLAY_GRID_COUNT = 8

MELODY_CHOP_HZ = [392.00, 349.23, 311.13, 277.18, 261.63, 233.08].freeze
LOOSE_POCKET_TIMING_MS = {
  snare: -28..-12, ghost: -10..18, hat_down: 8..18, hat_up: 22..40,
  kick_anchor: 0..6, kick_sync: 10..22
}.freeze
# Linda Perhacs "Delicious" layer calibration — beat at 0.72x ≈ 65 BPM native (minor_soul_loop 90 * 0.72).
DELICIOUS_POCKET_RATIO = 0.72
DELICIOUS_REFERENCE_BPM = 90.0
DELICIOUS_NATIVE_BPM = (DELICIOUS_REFERENCE_BPM * DELICIOUS_POCKET_RATIO).round(1)
# VLC Tools > Effects and Filters — all tabs enabled (EQ, compressor, spatializer, widener, normalize).
VLC_EQ_BANDS = [
  [60, 4.5], [170, 3.5], [310, 2.0], [600, 0.5], [1000, -1.0],
  [3000, 2.5], [6000, 1.5], [9000, -1.0], [12_000, -2.5], [15_000, -3.5]
].freeze
VLC_COMPRESSOR = { threshold: -20, ratio: 4.0, attack: 8, release: 120, makeup: 3.2, mix: 0.78 }.freeze
LOOSE_POCKET_BEAT_CATALOG = TAPE_RENDER_CATALOG.map do |entry|
  { track: entry[:preset], out: entry[:out].sub("session", "beat"), bars: 32 }
end.freeze
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
  { name: "Gm9",       hz: [196.00, 233.08, 293.66, 349.23, 440.00] }
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
  { name: "DMaj7overG", hz: [98.00,  146.83, 185.00, 220.00, 277.18] }
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
  # J Dilla — Donuts: "Time (The Donut of the Heart)" — Ab major IV–iii–vi–ii.
  time_donut: {
    artist: "J Dilla", title: "Time (The Donut of the Heart)", album: "Donuts",
    chords: %w[Dbmaj7 Cm7 Fm7 Bbm7],
    sources: [
      "Hooktheory / Ab IV–iii–vi–ii (Dbmaj7–Cm7–Fm7–Bbm7)",
      "RG-69 researched Donuts symbols"
    ]
  },
  # Same harmonic cycle with 9ths (pad color variant of Time, not a different song).
  maj7_minor_cycle: {
    artist: "J Dilla", title: "Time (The Donut of the Heart)", album: "Donuts",
    chords: %w[Dbmaj9 Cm9 Fm9 Bbm9],
    sources: ["Same Time cycle with maj9/m9 extensions"]
  },
  # Slum Village — Fall in Love (prod. Dilla) samples Gap Mangione.
  # r/jdilla (bzaiif): "Gap Mangione - Diana in the Autumn Wind".
  # ChordU / engine: two-chord Ebm7–Bbm7 vamp (not the old fabricated Bbm–Ab–Fm).
  fall_in_love: {
    artist: "Slum Village", title: "Fall in Love", producer: "J Dilla",
    sample: "Gap Mangione — Diana in the Autumn Wind",
    chords: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
    sources: [
      "r/jdilla: chords for Fall in love? — sample ID Diana in the Autumn Wind",
      "ChordU Ebm7/Bbm7 loop transcription"
    ]
  },
  # Slum Village — Get Dis Money. Ethan Hein full transcription of Herbie sample.
  get_dis_money: {
    artist: "Slum Village", title: "Get Dis Money", producer: "J Dilla",
    sample: "Herbie Hancock — Come Running To Me (Sunlight, 2:08)",
    chords: %w[D/E Db/E C/E Bm/E Bbm/E Am/E],
    sources: [
      "Ethan Hein 2022 transcription https://ethanhein.com/wp/2022/get-dis-money/",
      "D/E = E9sus4; then Db/E C/E Bm/E Bbm/E Am/E over E pedal"
    ]
  },
  # Alias used historically in engine for the same GDM slash cycle.
  syncopated_slash_ninth: {
    artist: "Slum Village", title: "Get Dis Money", producer: "J Dilla",
    sample: "Herbie Hancock — Come Running To Me",
    chords: %w[E9sus4/D Db/E C/E Bm/E Bbm/E Am/E E9sus4],
    sources: ["Ethan Hein Get Dis Money (E9sus4/D naming of D/E)"]
  },
  # Slum Village — Climax (ChordU; was previously wrong-key Fm loop).
  climax: {
    artist: "Slum Village", title: "Climax", producer: "J Dilla",
    chords: %w[Emaj7 G#m7 C#m7 E7climax],
    sources: ["ChordU Climax transcription"]
  },
  major7_relative_minor_turn: {
    artist: "Slum Village", title: "Climax", producer: "J Dilla",
    chords: %w[Emaj7 G#m7 C#m7 E7climax],
    sources: ["ChordU Climax (alias)"]
  },
  # D'Angelo — Untitled (How Does It Feel), Voodoo (Soulquarians / Dilla era).
  untitled_how_does_it_feel: {
    artist: "D'Angelo", title: "Untitled (How Does It Feel)", album: "Voodoo",
    chords: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
    sources: ["ChordU / Voodoo published chord analysis"]
  },
  sus_add9_ballad: {
    artist: "D'Angelo", title: "Untitled (How Does It Feel)", album: "Voodoo",
    chords: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
    sources: ["ChordU Untitled (alias)"]
  },
  # Alternating minor-7 pair = Fall in Love / Diana vamp (explicit name).
  alternating_minor7_pair: {
    artist: "Slum Village", title: "Fall in Love", producer: "J Dilla",
    sample: "Gap Mangione — Diana in the Autumn Wind",
    chords: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
    sources: ["Same as fall_in_love"]
  }
}.freeze

ARTIST_VERIFIED_TRACKS = ARTIST_VERIFIED_PROGRESSIONS.keys.freeze

def artist_verified_only?
  ENV.fetch("ARTIST_VERIFIED_ONLY", "1") != "0"
end

def artist_verified_chords(key)
  entry = ARTIST_VERIFIED_PROGRESSIONS[key&.to_sym]
  entry && entry[:chords]
end

def artist_verified_meta(key)
  ARTIST_VERIFIED_PROGRESSIONS[key&.to_sym]
end

# Album / track progressions — verified first; rest are experimental / theory pack.
CHORD_PROGRESSIONS = {
  # --- Artist-verified (see ARTIST_VERIFIED_PROGRESSIONS) ---
  time_donut: %w[Dbmaj7 Cm7 Fm7 Bbm7],
  maj7_minor_cycle: %w[Dbmaj9 Cm9 Fm9 Bbm9],
  fall_in_love: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
  get_dis_money: %w[D/E Db/E C/E Bm/E Bbm/E Am/E],
  syncopated_slash_ninth: %w[E9sus4/D Db/E C/E Bm/E Bbm/E Am/E E9sus4],
  climax: %w[Emaj7 G#m7 C#m7 E7climax],
  major7_relative_minor_turn: %w[Emaj7 G#m7 C#m7 E7climax],
  untitled_how_does_it_feel: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
  sus_add9_ballad: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
  alternating_minor7_pair: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
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
  tritone: %w[Cm9 Gbmaj9 Bbm9 Fm9],
  # (syncopated_slash_ninth / climax / untitled / fall_in_love: artist-verified block above)
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
  aydin_modal_quartal: %w[Cm9 Fmaj9 Bbmaj9 Ebmaj9 Abmaj7 Dm9 Bb7sus Cm9],
  aydin_jazz_turn: %w[Dm9 Gm9 C7b9 Fmaj9 Bbm9 Eb9 Abmaj9 Dm9],
  bach_circle_descent: %w[Am9 Dm9 G7 Cmaj9 Fmaj9 Bm7b5 E7b9 Am9],
  bach_descending_bass: %w[Dm9 Dm/C Bbmaj9 A7 Dm9 Gm9 Cmaj9 Fmaj9],
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
  coltrane_lite_triad: %w[Fm9 Abmaj9 Bmaj9 Fm9 Dbmaj9 Emaj9 Abmaj9 Fm9],
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
  dominant_chain_home: %w[C7 F7 Bb7 Eb7 Abmaj9 Dbmaj9 Cm9 F7]
}.freeze
# Per-track production presets (BPM from jdillabasslines Vol. 2).
TRACK_PRESETS = {
  baroque: {
    bpm: 104, progression: :baroque, chord_bars: 1, phrase_bars: 8, swing: 53,
    feel: :chromatic_planing,
    timing: { snare: -14..-5, hat_up: 8..18, bass: 10..24, kick_anchor: 0..3, pad: -6..4 }
  },
  chromatic_mediant: {
    bpm: 84, progression: :chromatic_mediant, chord_bars: 2, phrase_bars: 16, swing: 61,
    feel: :loose_pocket, stereo_pan: true, sidechain: true, voicing: :quartal, intro_bars: 8,
    timing: { snare: -30..-13, hat_up: 18..38, bass: 26..48, kick_anchor: 0..7, pad: 8..24 }
  },
  neo_soul: {
    bpm: 84, progression: :neo_soul, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :timeless, stereo_pan: true,
    timing: { snare: -20..-8, hat_up: 14..30, bass: 18..38, kick_anchor: 0..5, pad: 2..16 }
  },
  syncopated_slash_ninth: {
    bpm: 90, progression: :syncopated_slash_ninth, chord_bars: 1, phrase_bars: 7,
    swing: 54, feel: :syncopated_slash_ninth, stereo_pan: true, quintuplet: true,
    timing: { snare: -24..-10, hat_up: 20..36, bass: 28..48, kick_anchor: 0..3 }
  },
  chromatic_planing: {
    bpm: 96, progression: :chromatic_planing, chord_bars: 2, phrase_bars: 2,
    swing: 56, feel: :chromatic_planing,
    timing: { bass: 10..22, pad: -8..4, kick_sync: 6..16 }
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
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 }
  },
  time_donut: {
    bpm: 94, progression: :time_donut, chord_bars: 2, phrase_bars: 8, swing: 54,
    feel: :timeless, quintuplet: true, voicing: :rootless,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 }
  },
  get_dis_money: {
    bpm: 92, progression: :get_dis_money, chord_bars: 1, phrase_bars: 6, swing: 54,
    feel: :syncopated_slash_ninth, stereo_pan: true, quintuplet: true, voicing: :rootless,
    timing: { snare: -24..-10, hat_up: 20..36, bass: 28..48, kick_anchor: 0..3 }
  },
  fall_in_love: {
    bpm: 91, progression: :fall_in_love, chord_bars: 2, phrase_bars: 8, swing: 57,
    feel: :dilla_slight, voicing: :rootless, quintuplet: true,
    timing: { snare: -22..-10, hat_up: 14..28, bass: 22..38, kick_anchor: 0..4 }
  },
  climax: {
    bpm: 88, progression: :climax, chord_bars: 2, phrase_bars: 8, swing: 57,
    feel: :timeless, quintuplet: true, voicing: :rootless
  },
  untitled_how_does_it_feel: {
    bpm: 92, progression: :untitled_how_does_it_feel, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, stereo_pan: true, voicing: :rootless
  },
  timeless_authentic: {
    bpm: 86, progression: :timeless_authentic, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 }
  },
  chromatic_minor_descent: {
    bpm: 86, progression: :chromatic_minor_descent, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -22..-10, hat_up: 14..28, bass: 22..38, kick_anchor: 0..4 }
  },
  jazz: { bpm: 88, progression: :jazz, chord_bars: 4, swing: 60 },
  # Not a lookup — dilla_progression detects :generated and calls
  # generate_progression (functional-harmony random walk) instead.
  # GEN_ROOT/GEN_MODE/GEN_LENGTH/GEN_SEED env vars configure it.
  generated: {
    bpm: 90, progression: :generated, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :organic, stereo_pan: true
  },
  # progression: matches a GENERATED_STYLES entry directly — dilla_progression
  # detects this and routes to the matching generate_*_progression call.
  generated_planing: {
    bpm: 86, progression: :planing, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :organic, stereo_pan: true
  },
  generated_mediant: {
    bpm: 78, progression: :chromatic_mediant, chord_bars: 2, phrase_bars: 16, swing: 60,
    feel: :organic, stereo_pan: true
  },
  generated_polytonal: {
    bpm: 92, progression: :polytonal, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :organic, stereo_pan: true
  },
  generated_negative: {
    bpm: 84, progression: :negative_harmony, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :organic, stereo_pan: true
  },
  generated_neapolitan: {
    bpm: 80, progression: :neapolitan, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :organic, stereo_pan: true
  },
  generated_techno: {
    bpm: 80, progression: :chromatic_mediant, chord_bars: 2, phrase_bars: 16, swing: 0,
    feel: :techno_house, stereo_pan: true
  },
  fourth_third_sixth_second_turn: {
    bpm: 86, progression: :fourth_third_sixth_second_turn, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 }
  },
  voice_led_minor_arc: {
    bpm: 86, progression: :voice_led_minor_arc, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14 }
  },
  borrowed_dominant_turn: {
    bpm: 90, progression: :borrowed_dominant_turn, chord_bars: 2, phrase_bars: 8, swing: 54,
    feel: :timeless, voicing: :spread,
    timing: { snare: -22..-10, hat_up: 14..28, bass: 22..38, kick_anchor: 0..4 }
  },
  soul: {
    bpm: 84, progression: :soul, chord_bars: 4, phrase_bars: 16, swing: 58,
    feel: :timeless, voicing: :spread,
    timing: { snare: -20..-8, hat_up: 14..28, bass: 20..36, kick_anchor: 0..5 }
  },
  players: {
    bpm: 93, progression: :players_measured, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :timeless, voicing: :spread,
    timing: { snare: -20..-8, hat_up: 12..26, bass: 18..34, kick_anchor: 0..5 }
  }
}.freeze
INDUSTRIAL_BPM_DEFAULT = 132.0

CHORD_TEMPLATES = {
  "maj" => [0, 4, 7],
  "min" => [0, 3, 7],
  "7" => [0, 4, 7, 10],
  "maj7" => [0, 4, 7, 11],
  "m7" => [0, 3, 7, 10],
  "m9" => [0, 3, 7, 10, 2],
  "maj9" => [0, 4, 7, 11, 2],
  "sus" => [0, 5, 7],
  "dim" => [0, 3, 6],
  "7alt" => [0, 4, 7, 10, 1],
  "7#11" => [0, 4, 7, 10, 6],
  "m11" => [0, 3, 7, 10, 5],
  "sus4" => [0, 5, 7, 10],
  "aug" => [0, 4, 8],
  "6" => [0, 4, 7, 9]
}.freeze

# Real progression generator (not a lookup table) — a weighted-random walk
# over scale-degree functional harmony, the same tonic/predominant/dominant
# circulation Bach's chorales and jazz standards both run on: I tends
# toward IV/V/vi, ii/IV lean toward V, V resolves to I, vi wanders through
# ii/IV before finding its way back. Extended qualities (m9/maj9/dominant7)
# keep it in the same lush-pad harmonic language as the researched
# progressions rather than plain triads.
SCALE_DEGREE_QUALITY = {
  major: { 1 => "maj9", 2 => "m9", 3 => "m7", 4 => "maj9", 5 => "7", 6 => "m9", 7 => "dim" },
  minor: { 1 => "m9", 2 => "dim", 3 => "maj9", 4 => "m9", 5 => "7", 6 => "maj9", 7 => "7" }
}.freeze
SCALE_SEMITONES = {
  major: [0, 2, 4, 5, 7, 9, 11],
  minor: [0, 2, 3, 5, 7, 8, 10]
}.freeze
# Degree -> {next_degree => relative weight}. Standard functional motion:
# tonic radiates outward, predominants (ii/IV) gravitate to the dominant,
# the dominant resolves home, vi is the deceptive detour.
DEGREE_TRANSITIONS = {
  1 => { 4 => 3, 5 => 3, 6 => 2, 2 => 1 },
  2 => { 5 => 4, 7 => 1, 4 => 1 },
  3 => { 6 => 2, 4 => 1, 2 => 1 },
  4 => { 5 => 3, 1 => 2, 2 => 1 },
  5 => { 1 => 4, 6 => 1, 4 => 1 },
  6 => { 2 => 2, 4 => 2, 5 => 1 },
  7 => { 1 => 3, 3 => 1 }
}.freeze

def weighted_pick(rng, weights)
  total = weights.values.sum
  roll = rng.rand(total)
  acc = 0
  weights.each do |value, weight|
    acc += weight
    return value if roll < acc
  end
  weights.keys.first
end

# Generates a fresh progression by scale-degree random walk rather than
# picking from CHORD_PROGRESSIONS. root_hz sets the key center, mode is
# :major or :minor, length is chord count. Same seed -> same progression,
# so a track can be reproduced; no seed -> genuinely new each render.
def chord_from_root(root_hz, quality, voices: 5)
  intervals = CHORD_TEMPLATES.fetch(quality)
  hz = intervals.map { |iv| (root_hz * (2**(iv / 12.0))).round(2) }
  extra = intervals.max + 2
  hz << (root_hz * (2**(extra / 12.0))).round(2) while hz.length < voices
  hz.sort.first(voices)
end

def generate_progression(root_hz: 130.81, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  quality_for = SCALE_DEGREE_QUALITY.fetch(mode)
  semitones = SCALE_SEMITONES.fetch(mode)
  degree = 1
  Array.new(length) do
    quality = quality_for.fetch(degree)
    chord_root_hz = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
    chord = { name: "deg#{degree}#{quality}", hz: chord_from_root(chord_root_hz, quality) }
    degree = weighted_pick(rng, DEGREE_TRANSITIONS.fetch(degree))
    chord
  end
end

# Dilla's chromatic-minor-descent language (Donuts/Fantastic Vol. 2) isn't
# functional resolution — it's the *same* extended chord quality (m9/maj9)
# walked scalar/chromatic steps, occasionally toggling major/minor color.
# "Parallel planing" in classical-theory terms.
PLANING_STEP_WEIGHTS = { -2 => 3, -1 => 2, 2 => 2, -3 => 1, 3 => 1, -5 => 1 }.freeze
PLANING_QUALITIES = %w[m9 maj9].freeze

def generate_planing_progression(root_hz: 130.81, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  scale = SCALE_SEMITONES.fetch(mode)
  degree = 0
  quality = mode == :minor ? "m9" : "maj9"
  Array.new(length) do
    octave_shift = (degree.to_f / scale.length).floor
    chord_root_hz = root_hz * (2**((scale[degree % scale.length] + octave_shift * 12) / 12.0))
    chord = { name: "planing#{degree}#{quality}", hz: chord_from_root(chord_root_hz, quality) }
    quality = PLANING_QUALITIES.sample(random: rng) if rng.rand < 0.25
    degree += weighted_pick(rng, PLANING_STEP_WEIGHTS)
    chord
  end
end

# Chromatic-mediant language (chord analysis): root
# motion by thirds (chromatic mediants) rather than fifths, with an
# occasional tritone substitution standing in for a dominant resolution.
MEDIANT_STEP_WEIGHTS = { 3 => 3, -3 => 3, 4 => 2, -4 => 2, 6 => 1 }.freeze
MEDIANT_QUALITIES = %w[m9 maj9 7].freeze

def generate_chromatic_mediant_progression(root_hz: 130.81, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  semitone_offset = 0
  Array.new(length) do
    chord_root_hz = root_hz * (2**(semitone_offset / 12.0))
    quality = MEDIANT_QUALITIES.sample(random: rng)
    chord = { name: "mediant#{semitone_offset}#{quality}", hz: chord_from_root(chord_root_hz, quality) }
    semitone_offset += weighted_pick(rng, MEDIANT_STEP_WEIGHTS)
    chord
  end
end

# Aydin Esen's bitonal color: layer a second triad a tritone or major
# 2nd above the primary chord's root (a real polychord stack) rather than
# just extending the primary chord further up the tertian stack.
POLYTONAL_OFFSETS = [6, 2, 10].freeze

def generate_polytonal_progression(root_hz: 130.81, mode: :minor, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  quality_for = SCALE_DEGREE_QUALITY.fetch(mode)
  semitones = SCALE_SEMITONES.fetch(mode)
  degree = 1
  Array.new(length) do
    quality = quality_for.fetch(degree)
    chord_root_hz = root_hz * (2**(semitones[(degree - 1) % 7] / 12.0))
    hz = chord_from_root(chord_root_hz, quality, voices: 4)
    if rng.rand < 0.45
      poly_root = chord_root_hz * (2**(POLYTONAL_OFFSETS.sample(random: rng) / 12.0))
      hz += chord_from_root(poly_root, "maj", voices: 2)
    end
    chord = { name: "poly#{degree}#{quality}", hz: hz.sort.first(6) }
    degree = weighted_pick(rng, DEGREE_TRANSITIONS.fetch(degree))
    chord
  end
end

# Real pedal-point technique (Bach organ works, film-scoring tension
# device): freeze the bass note while the chords above it keep changing.
# Implemented by literally replacing each chord's lowest voice with a
# fixed anchor pitch for a stretch — the upper structure still moves, only
# the foundation holds still, which is the actual effect.
def apply_pedal_point(pads, probability: 0.35, seed: nil)
  return pads if pads.length < 3
  rng = seed ? Random.new(seed) : Random.new
  pedal_root = pads.first[:hz].min
  pads.map.with_index do |chord, i|
    next chord if i.zero? || rng.rand >= probability
    hz = chord[:hz].dup
    hz[hz.index(hz.min)] = pedal_root
    { name: "#{chord[:name]}_pedal", hz: hz.sort }
  end
end

# Negative harmony (Ernst Levy / popularized by Jacob Collier): reflect
# every pitch around a fixed axis between the tonic and dominant. A major
# chord's mirror is its relative-minor-adjacent inversion — genuinely
# different color from any of the other generators, not just a mode swap.
def generate_negative_harmony_progression(root_hz: 130.81, mode: :minor, length: 8, seed: nil)
  source = generate_progression(root_hz:, mode:, length:, seed:)
  # Axis sits between the tonic and dominant (7 semitones up) — reflecting
  # around midi_axis = tonic_midi + 3.5 semitones is the standard convention.
  axis_midi = hz_to_midi(root_hz) + 3.5
  source.map do |chord|
    mirrored = chord[:hz].map { |hz| midi_to_hz((2 * axis_midi) - hz_to_midi(hz)) }
    { name: "neg_#{chord[:name]}", hz: mirrored.sort }
  end
end

# Neapolitan/tritone-first: root motion dominated by a half-step (bII, the
# Neapolitan) or a tritone, resolving to the tonic only rarely — deliberately
# avoids the fifth-based motion every other generator here leans on.
NEAPOLITAN_STEP_WEIGHTS = { 1 => 4, 6 => 3, 11 => 2, 4 => 1 }.freeze
NEAPOLITAN_QUALITIES = %w[maj7 m9 7].freeze

def generate_neapolitan_progression(root_hz: 130.81, length: 8, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  semitone_offset = 0
  Array.new(length) do
    chord_root_hz = root_hz * (2**(semitone_offset / 12.0))
    quality = NEAPOLITAN_QUALITIES.sample(random: rng)
    chord = { name: "napl#{semitone_offset}#{quality}", hz: chord_from_root(chord_root_hz, quality) }
    step = weighted_pick(rng, NEAPOLITAN_STEP_WEIGHTS)
    semitone_offset += rng.rand < 0.5 ? step : -step
    chord
  end
end

def sh!(*command)
  argv = command.flatten.map(&:to_s)
  display = argv.join(" ")
  display = "#{display.byteslice(0, 420)}… (#{display.bytesize} bytes)" if display.bytesize > 460
  bin = File.basename(argv.first.to_s)
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ok = if DillaDmesg.interactive_bin?(argv)
         DillaDmesg.play!(bin, argv.last.to_s) if argv.length > 1
         system(*argv)
       elsif DillaDmesg.verbose?
         # Full tool chatter (ffmpeg banners, fluidsynth) when debugging.
         system(*argv)
       else
         # Quiet tools: OpenBSD dmesg only — no ffmpeg version spam.
         system(*argv, out: File::NULL, err: File::NULL)
       end
  sec = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
  DillaDmesg.run!(display, exitstatus: ok ? 0 : ($?.exitstatus || 1), seconds: sec)
  return if ok
  msg = "failed: #{bin}"
  dmesg_error(msg)
  raise RuntimeError, msg if ENV["DILLA_STREAMING"] == "1"
  abort msg
end

def capture(*command)
  Open3.capture3(*command.flatten.map(&:to_s))
end

def tool_available?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |directory| File.executable?(File.join(directory, name)) }
end

DEMUX_VENV_PYTHON = File.join(ROOT, ".venv-demucs", "bin", "python").freeze

def demucs_cmd
  return %w[demucs] if tool_available?("demucs")
  return [DEMUX_VENV_PYTHON, "-m", "demucs"] if File.executable?(DEMUX_VENV_PYTHON) &&
                                                  system(DEMUX_VENV_PYTHON, "-m", "demucs", "--help",
                                                         out: File::NULL, err: File::NULL)
  return %w[python3 -m demucs] if system("python3", "-m", "demucs", "--help", out: File::NULL, err: File::NULL)
  nil
end

def demucs_available?
  !demucs_cmd.nil?
end

# One dependency gate for every external binary — reports all missing tools
# at once instead of failing on the first and hiding the rest.
def require_tools!(*names)
  missing = names.reject { |name| tool_available?(name) }
  return if missing.empty?
  abort "#{missing.join(', ')} required"
end

def darwin?
  RUBY_PLATFORM.include?("darwin")
end

# ffplay from agent/nohup shells often has no CoreAudio route on macOS;
# afplay uses the logged-in user's default output device.
def playback_tool
  return "afplay" if darwin? && tool_available?("afplay")
  return "ffplay" if tool_available?("ffplay")
  nil
end

def require_playback_tool!
  abort "afplay or ffplay required" unless playback_tool
end

def ensure_mac_output_audible!
  return unless darwin?
  return if ENV["SKIP_VOLUME_NUDGE"] == "1"
  # Unmute + raise output if the session is silent (common “I can’t hear” cause).
  system("osascript", "-e",
         'set volume output volume 70 without output muted',
         out: File::NULL, err: File::NULL)
rescue StandardError
  nil
end

def play_audio(path, loop: false)
  tool = playback_tool
  unless tool
    msg = "afplay or ffplay required"
    raise RuntimeError, msg if ENV["DILLA_STREAMING"] == "1"
    abort msg
  end
  abort "missing audio #{path}" unless path && File.file?(path)
  ensure_mac_output_audible!
  vol = (ENV["PLAY_VOL"] || "1").to_f.clamp(0.0, 1.0)
  dmesg("play #{File.basename(path)} vol=#{vol} tool=#{tool} size=#{File.size(path)}",
        unit: "play0", parent: "dilla0")
  case tool
  when "afplay"
    if loop
      dmesg("loop #{File.basename(path)} via afplay (ctrl-c stop)", unit: "play0", parent: "dilla0")
      trap("INT") { exit 0 }
      loop { sh! "afplay", "-v", format("%.3f", vol), path }
    else
      sh! "afplay", "-v", format("%.3f", vol), path
    end
  else
    args = ["ffplay", "-nodisp", "-volume", (vol * 100).round.to_s]
    args << (loop ? "-loop" : "-autoexit")
    args << "0" if loop
    sh!(*args, path)
  end
end

def prompt(label)
  print "#{label}: "
  value = STDIN.gets&.strip
  abort "missing #{label}" if value.nil? || value.empty?
  value
end

# --- FFmpeg expression helpers ---

def lavfi(src)
  ["-f", "lavfi", "-i", src]
end

# Sum ffmpeg aeval expressions; never return empty (ffmpeg rejects blank expr).
def expr_sum(parts)
  flat = parts.flatten.compact.reject { |p| p.to_s.strip.empty? }
  flat.empty? ? "0" : flat.join("+")
end

# Wrap volume envelope for noise-channel gating (snare/hat/open).
def safe_volume_env(parts)
  "(#{expr_sum(parts)})"
end

def chop_hz(chord, t = 0.0)
  raw = case chord
        when Hash  then chord[:hz] || chord["hz"] || []
        when Array then chord
        else []
        end
  return raw if raw.empty? || !defined?(DillaSpectral) || !DillaSpectral.enabled?
  DillaSpectral.chop_hz(chord.is_a?(Hash) ? chord : { hz: raw }, t)
end

# Sample-chop wave: chord may be a PAD_CHORDS Hash or raw Hz array.
def chop_wave(chord, t, v, sustain = 0.55)
  hz = chop_hz(chord)
  return "0" if hz.empty?
  f = hz[(t * 10).to_i % hz.length]
  "between(t,#{t},#{t + sustain})*#{v}*0.11*exp(-(t-#{t})*1.7)*" \
    "(sin(2*PI*#{f}*(t-#{t}))+0.35*sin(2*PI*#{f * 1.5}*(t-#{t})))"
end

def bpm
  (ENV["BPM"] || DEFAULT_BPM).to_f
end

def bars
  (ENV["BARS"] || DEFAULT_BARS).to_i
end

def beat_seconds
  60.0 / bpm
end

def render_seconds
  (beat_seconds * 4.0 * bars).round(3)
end

def chord_expression
  cycle = (PAD_CHORDS.length * 8.0 * beat_seconds).round(4)
  PAD_CHORDS.each_with_index.map do |chord, chord_index|
    start_seconds = chord_index * 8.0 * beat_seconds
    stop_seconds = start_seconds + 8.0 * beat_seconds
    voices = chord[:hz].each_with_index.map do |frequency, voice_index|
      detune = 1.0 + ((voice_index - 2) * 0.0015)
      gain = 0.018 + (voice_index * 0.002)
      "#{gain.round(4)}*sin(2*PI*#{(frequency * detune).round(4)}*t)"
    end.join("+")
    "between(mod(t,#{cycle}),#{start_seconds.round(4)},#{stop_seconds.round(4)})*(#{voices})"
  end.join("+")
end

def start_groove_preview
  return nil unless tool_available?("ffplay")

  tmp = File.join(ROOT, ".groove_tmp.wav")
  render_dilla(tmp, [8, bars].max)
  pid = spawn("ffplay", "-nodisp", "-loop", "0", tmp, out: "/dev/null", err: "/dev/null")
  [pid, tmp]
rescue SystemCallError
  nil
end

def scan(groove: false)
  groove_pid, groove_tmp = groove ? start_groove_preview : [nil, nil]
  puts JSON.pretty_generate(
    root: ROOT,
    bpm: bpm,
    bars: bars,
    seconds: render_seconds,
    files: {
      ruby: File.exist?(__FILE__),
      html: File.exist?(File.join(ROOT, "dilla.html")),
      clean_harmonic: File.exist?(SAMPLE_CLEAN)
    },
    tools: {
      ffmpeg: tool_available?("ffmpeg"),
      ffprobe: tool_available?("ffprobe"),
      yt_dlp: tool_available?("yt-dlp"),
      demucs: tool_available?("demucs")
    },
    commands: COMMANDS
  )
ensure
  if groove_pid
    Process.kill("TERM", groove_pid) rescue nil
    Process.wait(groove_pid) rescue nil
  end
  FileUtils.rm_f(groove_tmp) if groove_tmp
end

def council
  puts "MASTER council"
  puts "preserve existing command surface"
  puts "separate source capture, demucs, rhythm study, melody study"
  puts "add harmony and semantic texture evidence"
  puts "feed ears metrics into MASTER before aesthetic judgment"
  puts "keep render, clean, stems, chords intact"
end

def source(input = nil, output = nil)
  input ||= prompt("audio path or URL")
  output ||= File.join(SAMPLE_DIR, "source.wav")
  FileUtils.mkdir_p(File.dirname(output))
  return convert_audio(input, output) if File.exist?(input)
  download_track(input, output)
end

def livestream(input = nil, output = nil)
  input ||= prompt("livestream URL")
  output ||= File.join(SAMPLE_DIR, "livestream.wav")
  seconds_to_capture = (ENV["LIVE_SECONDS"] || 600).to_i
  require_tools! "yt-dlp", "ffmpeg"
  media_url = direct_media_url(input)
  FileUtils.mkdir_p(File.dirname(output))
  sh! "ffmpeg", "-y", "-t", seconds_to_capture.to_s, "-i", media_url, "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
  output
end

def sample
  path = source(nil, File.join(SAMPLE_DIR, "source.wav"))
  separated = separate(path)
  harmonic = separated.fetch("other")
  clean(harmonic, SAMPLE_CLEAN)
end

def separate(input = nil)
  input ||= prompt("audio path or URL")
  wav = File.exist?(input) ? input : source(input, File.join(SAMPLE_DIR, "source.wav"))
  require_tools! "demucs"
  FileUtils.mkdir_p(STEM_DIR)
  sh! "demucs", "-n", "htdemucs_ft", "-o", STEM_DIR, wav
  map = latest_stems
  puts JSON.pretty_generate(map)
  map
end

def latest_stems
  files = Dir[File.join(STEM_DIR, "**", "*.wav")]
  abort "no stems found" if files.empty?
  newest_directory = files.group_by { |path| File.dirname(path) }.max_by { |_directory, paths| paths.map { |path| File.mtime(path) }.max }.first
  stem_paths(Dir[File.join(newest_directory, "*.wav")])
end

def download_track(url, output)
  require_tools! "yt-dlp", "ffmpeg"
  temporary = File.join(SAMPLE_DIR, "download.%(ext)s")
  sh! "yt-dlp", "-f", "bestaudio", "--extract-audio", "--audio-format", "wav", url, "-o", temporary
  downloaded = Dir[File.join(SAMPLE_DIR, "download.wav")].max_by { |path| File.mtime(path) }
  abort "download produced no wav" unless downloaded
  FileUtils.mv(downloaded, output)
  puts "wrote #{output}"
  output
end

def direct_media_url(url)
  output, error, status = capture("yt-dlp", "-g", "-f", "bestaudio", url)
  abort error unless status.success?
  media_url = output.lines.first&.strip
  abort "yt-dlp returned no media URL" if media_url.nil? || media_url.empty?
  media_url
end

def convert_audio(input, output)
  require_tools! "ffmpeg"
  sh! "ffmpeg", "-y", "-i", input, "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
  output
end

def render(destination = File.join(OUTPUT_DIR, "full_track.mp3"))
  require_tools! "ffmpeg"
  FileUtils.mkdir_p(File.dirname(destination))
  duration = render_seconds
  kick_period = (beat_seconds * 2.0).round(6)
  command = ["ffmpeg", "-y"]
  command += ["-f", "lavfi", "-i", "aevalsrc='#{chord_expression}':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.16*sin(2*PI*49*t)*exp(-mod(t,#{beat_seconds.round(6)})*3.1)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.58*sin(2*PI*(45+90*exp(-mod(t,#{kick_period})*18))*t)*exp(-mod(t,#{kick_period})*9)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.13*(random(0)-0.5)*lt(mod(t+#{beat_seconds.round(6)},#{kick_period}),0.08)*exp(-mod(t+#{beat_seconds.round(6)},#{kick_period})*28)':d=#{duration}:s=#{SAMPLE_RATE}"]
  command += ["-f", "lavfi", "-i", "aevalsrc='0.035*(random(0)-0.5)*lt(mod(t,#{(beat_seconds / 2.0).round(6)}),0.035)*exp(-mod(t,#{(beat_seconds / 2.0).round(6)})*80)':d=#{duration}:s=#{SAMPLE_RATE}"]
  sample_input = nil
  if File.exist?(SAMPLE_CLEAN)
    sample_input = 5
    command += ["-stream_loop", "-1", "-i", SAMPLE_CLEAN]
  end
  command += ["-filter_complex", render_filter(duration, sample_input), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  puts "wrote #{destination}"
end

def render_filter(duration, sample_input)
  filter = []
  filter << "[0:a]aformat=channel_layouts=stereo,lowpass=f=3300,adelay=7|13[ep]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=160[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,lowpass=f=140[kick]"
  filter << "[3:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=5000[snare]"
  filter << "[4:a]aformat=channel_layouts=stereo,highpass=f=6500[hats]"
  labels = %w[[ep] [bass] [kick] [snare] [hats]]
  weights = %w[1.00 0.80 0.72 0.55 0.24]
  if sample_input
    filter << "[#{sample_input}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS,highpass=f=70,lowpass=f=12000[sample]"
    labels << "[sample]"
    weights << "0.85"
  end
  filter << "#{labels.join}amix=inputs=#{labels.length}:weights=#{weights.join(' ')}:duration=first,acompressor=threshold=-18dB:ratio=2.4:attack=24:release=130,acrusher=bits=13:samples=2:mix=0.12,alimiter=limit=0.94:level_out=0.96[out]"
  filter.join(";")
end

def codec_for(destination)
  return ["-codec:a", "libmp3lame", "-b:a", "320k"] if File.extname(destination).downcase == ".mp3"
  ["-c:a", "pcm_s16le"]
end

def verify(path = File.join(OUTPUT_DIR, "full_track.mp3"))
  abort "missing #{path}" unless File.exist?(path)
  output, error, status = capture("ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-")
  text = output + error
  puts text.lines.grep(/Duration|bitrate|mean_volume|max_volume/).join
  abort "verify failed" unless status.success? && text.include?("mean_volume:")
end

def dilla_quality(path, baseline_path = nil)
  abort "missing #{path}" unless File.file?(path)
  loud_out, loud_err, loud_status = capture(
    "ffmpeg", "-hide_banner", "-i", path, "-af", "loudnorm=I=-14:TP=-1:LRA=11:print_format=json", "-f", "null", "-"
  )
  abort loud_err unless loud_status.success?
  json_text = (loud_out + loud_err)[/\{\s*"input_i".*?\}/m]
  loudness = json_text ? JSON.parse(json_text) : {}
  spectrum = {
    low: band_rms(path, highpass: 28, lowpass: 180),
    mid: band_rms(path, highpass: 180, lowpass: 3_500),
    high: band_rms(path, highpass: 3_500, lowpass: 16_000)
  }
  mono = band_rms(path, highpass: 28, lowpass: 16_000)
  chords = DillaHarmony.last_progression_chords
  harmony_score = DillaHarmony.score_beauty(chords)
  harmony_breakdown = chords&.any? ? DillaHarmony.score_breakdown(chords) : {}
  harshness = DillaMaster.analyze_harshness(spectrum)
  sub_kick = DillaMaster.sub_kick_balance(spectrum, harmony_score)
  report = media_metadata(path).merge(
    schema: "dilla.master.v1", path: File.expand_path(path), delivery: File.extname(path).delete_prefix(".").downcase,
    integrated_lufs: loudness["input_i"]&.to_f, true_peak_dbtp: loudness["input_tp"]&.to_f,
    harmony_score: harmony_score, harmony_breakdown: harmony_breakdown,
    progression_chord_names: chords&.map { |c| c[:name] },
    harshness: harshness, sub_kick_balance: sub_kick,
    ml_notes: (ENV["DILLA_ML"] == "1" ? [DillaMl.ddsp_stub_note] : nil),
    loudness_range_lu: loudness["input_lra"]&.to_f, mono_rms_db: mono, spectral_rms_db: spectrum,
    target: { integrated_lufs: -14.0..-11.0, true_peak_max_dbtp: -1.0 }, warnings: [],
    capabilities: Master::Io::AnalogCapabilities.for(:dilla).last(5).map { |entry| entry[:id] }
  )
  report[:warnings] << "true peak exceeds -1 dBTP" if report[:true_peak_dbtp] && report[:true_peak_dbtp] > -1.0
  report[:warnings] << "master is outside radio-ready -14..-11 LUFS range" if report[:integrated_lufs] && !(-14.0..-11.0).cover?(report[:integrated_lufs])
  if baseline_path && File.file?(baseline_path)
    baseline = JSON.parse(File.read(baseline_path), symbolize_names: true)
    old = baseline[:spectral_rms_db] || {}
    report[:spectral_delta_db] = spectrum.to_h { |band, value| [band, (value - old.fetch(band, value).to_f).round(3)] }
    report[:warnings] << "spectral balance moved more than 4 dB" if report[:spectral_delta_db].values.any? { |delta| delta.abs > 4.0 }
  end
  sidecar = "#{path}.quality.json"
  File.write(sidecar, JSON.pretty_generate(report) + "\n")
  puts JSON.pretty_generate(report.merge(sidecar: sidecar))
  report
end

def clean(input, output)
  abort "missing input" unless input && File.exist?(input)
  FileUtils.mkdir_p(File.dirname(output))
  sh! "ffmpeg", "-y", "-i", input, "-af", "highpass=f=28,lowpass=f=15500,afftdn=nf=-25,adeclick,loudnorm=I=-18:TP=-1.5:LRA=10", "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
end

# --- Stems rack (manifest in stems/) ---

def stems_load_manifest
  return { "active" => "default", "sets" => {} } unless File.exist?(STEM_MANIFEST)
  JSON.parse(File.read(STEM_MANIFEST, encoding: "utf-8"))
end

def stems_write_manifest(manifest)
  FileUtils.mkdir_p(File.dirname(STEM_MANIFEST))
  File.write(STEM_MANIFEST, JSON.pretty_generate(manifest) + "\n")
  puts "manifest -> #{STEM_MANIFEST}"
end

def stems_scan_set(dir)
  Dir.children(dir).select { |f| STEM_EXTS.include?(File.extname(f).downcase) }.sort
end

def stems_register(name, dir, bpm: nil, source: nil)
  rel = dir.sub(%r{\A#{Regexp.escape(STEM_DIR)}/?}, "")
  rel = "." if rel.empty?
  files = stems_scan_set(dir)
  abort "no stems in #{dir}" if files.empty?
  m = stems_load_manifest
  m["sets"][name] = { "dir" => rel, "bpm" => bpm, "source" => source, "files" => files }.compact
  m["active"] ||= name
  stems_write_manifest(m)
end

def stems_scan(root = File.join(SAMPLE_DIR, "demucs"), manifest = File.join(SAMPLE_DIR, "manifest.json"))
  grouped = Dir.glob(File.join(root, "**", "*.{wav,mp3,flac,ogg,m4a}"), File::FNM_EXTGLOB)
               .group_by { |path| File.dirname(path) }
  sets = grouped.map.with_index do |(directory, files), index|
    {
      "name" => File.basename(directory),
      "bpm" => bpm,
      "stems" => stem_paths(files),
      "prime_swell" => ANALOG_PRIMES[index % ANALOG_PRIMES.length]
    }
  end
  FileUtils.mkdir_p(File.dirname(manifest))
  File.write(manifest, JSON.pretty_generate({ "version" => 4, "sets" => sets }) + "\n")
  puts "manifest -> #{manifest}"
end

def stems(*args)
  case args[0]
  when "scan"
    stems_scan(args[1] || File.join(SAMPLE_DIR, "demucs"), args[2] || File.join(SAMPLE_DIR, "manifest.json"))
  when "add"
    name = args[1] or abort "usage: ruby dilla.rb stems add <name> <dir> [bpm]"
    dir  = args[2] or abort "usage: ruby dilla.rb stems add <name> <dir> [bpm]"
    stems_register(name, File.expand_path(dir), bpm: (args[3] && args[3].to_f))
  when nil
    stems_register("default", STEM_DIR, bpm: 90, source: "Sirkel Sag · Voicemails")
  else
    stems_scan(args[0], args[1] || STEM_MANIFEST)
  end
end

def stem_paths(files)
  files.each_with_object({}) { |path, map| map[stem_key(path)] = path.sub(ROOT + "/", "") }
end

def stem_key(path)
  basename = File.basename(path).downcase
  return "drums" if basename.include?("drums")
  return "bass" if basename.include?("bass")
  return "vocals" if basename.include?("vocals")
  return "other" if basename.include?("other")
  File.basename(path, ".*")
end

def chords
  PAD_CHORDS.each_with_index { |chord, number| puts "%02d %s %s" % [number + 1, chord[:name], chord[:hz].map { |frequency| frequency.round(2) }.join(" ")] }
end

def study(kind, input = nil)
  input ||= prompt("audio path")
  abort "missing #{input}" unless File.exist?(input)
  return rhythm(input) if kind == "rhythm"
  return melody(input) if kind == "melody"
  return harmony(input) if kind == "harmony"
  return semantics(input) if kind == "semantics"
  abort "study kind must be rhythm, melody, harmony, or semantics"
end

def rhythm(input = nil)
  input ||= prompt("drum or full audio path")
  data = frame_energy(input, highpass: 90, lowpass: 8_000)
  peaks = peak_frames(data.fetch(:frames), data.fetch(:hop_seconds))
  puts JSON.pretty_generate(type: "rhythm", path: input, duration_seconds: data.fetch(:duration_seconds), peaks: peaks.first(128))
end

def melody(input = nil)
  input ||= prompt("melodic stem path")
  data = spectral_windows(input)
  puts JSON.pretty_generate(type: "melody", path: input, duration_seconds: data.fetch(:duration_seconds), windows: data.fetch(:windows).first(128))
end

def harmony(input = nil)
  input ||= prompt("harmonic stem path")
  profile = pitch_profile(input)
  pcs = profile.fetch(:pitch_classes)
  ranking = chord_candidates(pcs).first(16)
  coltrane_hits = DillaMusicGems.chord_candidates_from_pitch_classes(pcs, limit: 12) if defined?(DillaMusicGems)
  puts JSON.pretty_generate(
    type: "harmony", path: input, duration_seconds: profile.fetch(:duration_seconds),
    pitch_classes: pcs, chords: ranking,
    coltrane_candidates: coltrane_hits,
    pitch_class_set: DillaMusicGems.pitch_class_set(pcs)&.to_a
  )
end

def beauty_report(path = nil)
  chords = DillaHarmony.last_progression_chords
  if path && File.file?(path)
    sidecar = "#{path}.quality.json"
    if File.file?(sidecar)
      rep = JSON.parse(File.read(sidecar), symbolize_names: true)
      chords = rep[:progression_chords] if rep[:progression_chords]&.any?
    end
    dilla_quality(path) unless File.file?(sidecar)
  end
  if chords.nil? || chords.empty?
    cfg = dilla_resolve_config
    pads = dilla_progression(cfg[:progression])
    if pads.any?
      pads, = if curated_progression?(cfg)
                DillaHarmony.beautify_curated_pipeline(pads, cfg)
              else
                DillaHarmony.beautify_pipeline(pads, cfg)
              end
      chords = pads
      DillaHarmony.remember_progression(pads)
    end
  end
  abort "no progression — render first: TRACK=maj7_minor_cycle ruby dilla.rb dilla out.wav 8" if chords.nil? || chords.empty?
  breakdown = DillaHarmony.score_breakdown(chords)
  recs = DillaHarmony.recommendations(breakdown)
  symbols = chords.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }
  analysis = DillaMusicGems.progression_analysis(symbols) if defined?(DillaMusicGems)
  puts "── Harmony beauty ──"
  breakdown.each { |k, v| puts format("%-12s %s", "#{k}:", v) }
  if analysis
    puts "── Coltrane progression (github.com/pedrozath/coltrane) ──"
    puts "  #{analysis[:notation]} in #{analysis[:scale]} (#{analysis[:notes_out]} notes outside scale)"
  end
  puts "Recommendations:"
  recs.each { |r| puts "  • #{r}" }
  { breakdown: breakdown, recommendations: recs, progression_analysis: analysis }
end

def phone_preview(path = nil)
  path ||= File.join(OUTPUT_DIR, "beat.mp3")
  abort "missing #{path}" unless File.file?(path)
  out = DillaMaster.apply_phone_preview!(path)
  puts "phone preview → #{out}"
  play(out) if tool_available?("ffplay")
  out
end

def semantics(input = nil)
  input ||= prompt("audio path")
  rhythm_data = frame_energy(input, highpass: 60, lowpass: 12_000)
  loudness = rhythm_data.fetch(:frames).map(&:last)
  brightness = frame_energy(input, highpass: 2_400, lowpass: 12_000).fetch(:frames).map(&:last)
  density = peak_frames(rhythm_data.fetch(:frames), rhythm_data.fetch(:hop_seconds)).length.to_f / [rhythm_data.fetch(:duration_seconds), 1.0].max
  puts JSON.pretty_generate(type: "semantics", path: input, duration_seconds: rhythm_data.fetch(:duration_seconds), tags: semantic_tags(loudness, brightness, density))
end

def ears(path = File.join(OUTPUT_DIR, "full_track.mp3"))
  abort "missing #{path}" unless File.exist?(path)
  report = media_metadata(path).merge(volume_metadata(path)).merge(path: path)
  report[:verdict] = ears_verdict(report)
  puts JSON.pretty_generate(report)
end

def frame_energy(path, highpass:, lowpass:)
  require_tools! "ffmpeg"
  raw = pipe_floats(path, "highpass=f=#{highpass},lowpass=f=#{lowpass},aformat=sample_fmts=flt:channel_layouts=mono")
  hop = 2_048
  frames = raw.each_slice(hop).with_index.map do |slice, index|
    next if slice.empty?
    [index * hop.to_f / SAMPLE_RATE, Math.sqrt(slice.sum { |value| value * value } / slice.length)]
  end.compact
  { frames: frames, hop_seconds: hop.to_f / SAMPLE_RATE, duration_seconds: raw.length.to_f / SAMPLE_RATE }
end

def band_rms(path, highpass:, lowpass:)
  raw = pipe_floats(path, "highpass=f=#{highpass},lowpass=f=#{lowpass},aformat=sample_fmts=flt:channel_layouts=mono")
  return -Float::INFINITY if raw.empty?

  rms = Math.sqrt(raw.sum { |value| value * value } / raw.length)
  (20.0 * Math.log10([rms, 1.0e-12].max)).round(3)
end

def spectral_windows(path)
  raw = pipe_floats(path, "highpass=f=90,lowpass=f=5000,aformat=sample_fmts=flt:channel_layouts=mono")
  window = 4_096
  windows = raw.each_slice(window).with_index.map do |slice, index|
    next if slice.length < window
    zero_crossings = slice.each_cons(2).count { |left, right| (left.negative? && right.positive?) || (left.positive? && right.negative?) }
    estimated_hz = zero_crossings.to_f * SAMPLE_RATE / (2.0 * slice.length)
    [index * window.to_f / SAMPLE_RATE, estimated_hz.round(2), nearest_note(estimated_hz)]
  end.compact
  { duration_seconds: raw.length.to_f / SAMPLE_RATE, windows: windows }
end

def pitch_profile(path)
  raw = pipe_floats(path, "highpass=f=65,lowpass=f=5000,aformat=sample_fmts=flt:channel_layouts=mono")
  window = 2_048
  bins = Array.new(12, 0.0)
  raw.each_slice(window) do |slice|
    next if slice.length < window
    estimate = zero_crossing_hz(slice)
    next if estimate < 40.0 || estimate > 5_000.0
    bins[pitch_class_for(estimate)] += slice.sum { |value| value.abs } / slice.length
  end
  total = bins.sum
  normalized = total.positive? ? bins.map { |value| (value / total).round(5) } : bins
  { duration_seconds: raw.length.to_f / SAMPLE_RATE, pitch_classes: PITCH_CLASSES.zip(normalized).to_h }
end

def chord_candidates(pitch_classes)
  values = PITCH_CLASSES.map { |name| pitch_classes.fetch(name, 0.0) }
  candidates = []
  PITCH_CLASSES.each_with_index do |root_name, root_index|
    CHORD_TEMPLATES.each do |suffix, intervals|
      score = intervals.sum { |interval| values[(root_index + interval) % 12] }
      candidates << { chord: "#{root_name}#{suffix}", score: score.round(5) }
    end
  end
  candidates.sort_by { |candidate| -candidate.fetch(:score) }
end

def zero_crossing_hz(slice)
  crossings = slice.each_cons(2).count { |left, right| (left.negative? && right.positive?) || (left.positive? && right.negative?) }
  crossings.to_f * SAMPLE_RATE / (2.0 * slice.length)
end

def pitch_class_for(frequency)
  (69 + (12 * Math.log2(frequency / 440.0))).round % 12
end

def semantic_tags(loudness, brightness, density)
  mean_loudness = average(loudness)
  mean_brightness = average(brightness)
  tags = []
  tags << (density > 2.5 ? "dense" : "spacious")
  tags << (mean_brightness > mean_loudness * 0.45 ? "bright" : "warm")
  tags << (standard_deviation(loudness) > mean_loudness * 0.8 ? "unstable" : "steady")
  tags << (mean_loudness < 0.03 ? "intimate" : "forward")
  tags
end

def pipe_floats(path, filter)
  output, error, status = capture("ffmpeg", "-v", "error", "-i", path, "-af", filter, "-f", "f32le", "-")
  abort error unless status.success?
  output.unpack("e*")
end

def peak_frames(frames, hop_seconds)
  return [] if frames.empty?
  values = frames.map(&:last)
  threshold = average(values) + standard_deviation(values)
  frames.each_cons(3).each_with_object([]) do |(left, middle, right), out|
    next unless middle.last > threshold && middle.last > left.last && middle.last > right.last
    out << { time: middle.first.round(3), strength: middle.last.round(5), grid: (middle.first / hop_seconds).round }
  end
end

def average(values)
  return 0.0 if values.empty?
  values.sum / values.length
end

def standard_deviation(values)
  mean = average(values)
  Math.sqrt(values.sum { |value| (value - mean) * (value - mean) } / [values.length, 1].max)
end

def nearest_note(frequency)
  return nil if frequency <= 0
  midi = (69 + (12 * Math.log2(frequency / 440.0))).round
  "#{PITCH_CLASSES[midi % 12]}#{(midi / 12) - 1}"
end

def media_metadata(path)
  output, error, status = capture("ffprobe", "-v", "error", "-show_entries", "format=duration,bit_rate", "-of", "json", path)
  abort error unless status.success?
  format = JSON.parse(output).fetch("format", {})
  { duration_seconds: format.fetch("duration", "0").to_f.round(3), bit_rate: format.fetch("bit_rate", "0").to_i }
rescue JSON::ParserError => error
  abort "ffprobe json parse failed: #{error.message}"
end

def volume_metadata(path)
  output, error, status = capture("ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "-")
  abort error unless status.success?
  text = output + error
  { mean_volume_db: number_after(text, "mean_volume:"), max_volume_db: number_after(text, "max_volume:") }
end

def number_after(text, label)
  line = text.lines.find { |entry| entry.include?(label) }
  line ? line.split(label, 2).last.to_f : nil
end

def ears_verdict(report)
  return "too_short" if report[:duration_seconds] < 20.0
  return "too_quiet" if report[:mean_volume_db] && report[:mean_volume_db] < -28.0
  return "clips" if report[:max_volume_db] && report[:max_volume_db] > -0.2
  "usable"
end

def debug
  scan
  puts "music gems: #{DillaMusicGems.status.inspect}" if defined?(DillaMusicGems)
  _output, error, status = capture("ruby", "-c", __FILE__)
  puts(status.success? ? "ruby syntax: ok" : error)
end

def sweep
  output = File.join(OUTPUT_DIR, "sweep_check.mp3")
  previous = ENV["BARS"]
  ENV["BARS"] = "8"
  render(output)
  verify(output)
  ears(output) if tool_available?("ffprobe")
ensure
  previous ? ENV["BARS"] = previous : ENV.delete("BARS")
end

# --- Analog grade engine ---

# Build an ffmpeg filter fragment for one grade effect using stock params.
# Each filter maps to a postpro analog concept (see GRADE_PRESETS comment).
def grade_filter(fx, stock)
  case fx
  when "tape_saturation"
    # H&D characteristic curve analog: tanh waveshaper, gain-neutral.
    d = stock[:sat_drive]
    n = Math.tanh(d).round(6)
    "aeval=exprs='tanh(#{d}*val(0))/#{n}|tanh(#{d}*val(1))/#{n}'"
  when "analog_noise"
    # Newson-Delon grain analog: flat Gaussian noise floor at stock amplitude.
    a = stock[:noise_amp]
    "aeval=exprs='val(0)+#{a}*(random(0)-0.5)|val(1)+#{a}*(random(1)-0.5)'"
  when "harmonic_bloom"
    # Halation analog: even-harmonic enrichment (tube/transformer bloom).
    # x|x| adds 2nd+3rd order harmonics without DC offset.
    "aeval=exprs='val(0)+0.07*val(0)*abs(val(0))|val(1)+0.07*val(1)*abs(val(1))'"
  when "spectral_warmth"
    # Color temperature analog: low-shelf boost + high-shelf cut.
    db  = stock[:warmth_db].round(1)
    cut = (db * 0.65).round(1)
    "equalizer=f=90:width_type=o:width=2:g=#{db},equalizer=f=9500:width_type=o:width=2:g=-#{cut}"
  when "parallel_compress"
    # Bleach bypass analog: New York parallel compression.
    "acompressor=threshold=-22dB:ratio=7:attack=6:release=55:makeup=3:mix=0.45"
  when "multiband_tone"
    # Split grade analog: three-band independent tonal shaping.
    "equalizer=f=110:width_type=o:width=2:g=1.8,equalizer=f=900:width_type=o:width=2:g=0.5,equalizer=f=7000:width_type=o:width=2:g=-1.2"
  when "wow_flutter"
    # Reciprocity failure analog: capstan speed LFO (wow=slow, flutter=fast).
    r = stock[:wow_rate]
    d = stock[:wow_depth]
    "vibrato=f=#{r}:d=#{d}"
  when "vinyl_crackle"
    # Faded print analog: stochastic crackle bursts at ~0.08% of samples.
    "aeval=exprs='val(0)+if(lt(random(0),0.0008),(random(1)-0.5)*0.22,0)|" \
    "val(1)+if(lt(random(2),0.0008),(random(3)-0.5)*0.22,0)'"
  when "transient_sharpen"
    # Micro-contrast analog: presence boost via high-mid shelf.
    "equalizer=f=4000:width_type=o:width=1.5:g=2.0"
  when "stereo_width"
    # Chromatic aberration analog: M/S stereo widening.
    "extrastereo=m=1.35"
  when "print_through_echo"
    # Print-through analog: adjacent tape-layer bleed. True print-through is a
    # pre-echo; ffmpeg's aecho is forward-only, so this renders it as a faint
    # post-echo shadow of the same magnitude and timing (~40ms, -25dB).
    "aecho=1.0:0.056:38:0.11"
  when "reel_splice_clicks"
    # Reel splice analog: a physical tape join clicks once per reel length.
    "aeval=exprs='val(0)+if(lt(mod(t,42.5),0.0015),0.4*(random(0)-0.5),0)|" \
    "val(1)+if(lt(mod(t,42.5),0.0015),0.4*(random(1)-0.5),0)'"
  when "stylus_mistrack"
    # Groove mistracking analog: extra clipping kicks in only above a peak threshold.
    "aeval=exprs='val(0)+0.5*(tanh(4*val(0))-val(0))*gt(abs(val(0)),0.55)|" \
    "val(1)+0.5*(tanh(4*val(1))-val(1))*gt(abs(val(1)),0.55)'"
  when "platter_wow"
    # Off-centre pressing analog: wow locked to platter speed (33 1/3rpm ≈ 0.556Hz),
    # not tape capstan speed — slower and more periodic than wow_flutter.
    "vibrato=f=0.556:d=0.012"
  when "needle_drop_fade"
    # Needle-drop analog: stylus settling into a spinning groove.
    "afade=t=in:st=0:d=0.12:curve=qsin"
  when "haas_jitter"
    # Console crosstalk / Haas analog: asymmetric micro-delay per channel for width.
    "adelay=9|13,aecho=0.15:0.2:130:0.18"
  when "spring_reverb"
    # Spring tank analog: sparse, dispersive taps with a metallic mid resonance.
    "aecho=0.8:0.65:29|61|101|149:0.5|0.4|0.3|0.22,equalizer=f=2200:t=o:w=1.4:g=3.0,highpass=f=350"
  when "plate_reverb"
    # Plate analog: dense, closely spaced early reflections, smooth decay.
    "aecho=0.85:0.7:15|33|52|74|97|123:0.42|0.36|0.3|0.24|0.18|0.12"
  when "chamber_reverb"
    # Chamber analog: a few distinct early reflections before a short room tail.
    "aecho=0.9:0.6:41|83|127|179:0.38|0.30|0.22|0.15"
  when "dub_delay"
    # Dub delay analog: regenerating tape-echo feedback with saturation in the loop.
    "aecho=0.8:0.75:340|680:0.45|0.28,aeval=exprs='tanh(1.6*val(0))/#{Math.tanh(1.6).round(6)}|" \
    "tanh(1.6*val(1))/#{Math.tanh(1.6).round(6)}'"
  end
end

def sonitex_resolve_preset(track: nil)
  track ||= (ENV["TRACK"] || ENV["PROGRESSION"] || "chromatic_minor_descent").to_s.downcase.tr("-", "_")
  raw = (ENV["SONITEX_PRESET"] || ENV["SONITEX"]).to_s.strip.downcase
  if raw.empty?
    # Was :donuts_warm — that preset's hf_rolloff/groove_wear_lp sit at
    # 2200/2600Hz (see its "not a 2 kHz blanket" sibling comment above
    # donuts_soul) and its out_comp_ratio is a full point hotter, burying
    # presence/air and sitting crest factor right at the reject-gate floor.
    # DILLA_STYLE_DEFAULTS/DILLA_BEST_DEFAULTS both already target
    # donuts_soul; this fallback had drifted out of sync with them.
    return :donuts_soul
  end
  return nil if raw =~ /\A(?:0|false|off)\z/
  return :heavy if %w[1 true on heavy].include?(raw)
  return :classic if %w[classic st1260 1260].include?(raw)
  return :extreme if %w[extreme st1269 1269].include?(raw)
  key = raw.to_sym
  SONITEX_PRESETS.key?(key) ? key : :heavy
end

def analog_chain_lookup(variant)
  key = variant.to_sym
  return ANALOG_CHAIN_VARIANTS[key] if ANALOG_CHAIN_VARIANTS.key?(key)
  return ANALOG_CHAIN_WILD[key] if ANALOG_CHAIN_WILD.key?(key)
  if @stream_wild_analog_chain && @stream_wild_analog_chain[:name] == key
    return { stock: @stream_wild_analog_chain[:stock], fx: @stream_wild_analog_chain[:fx] }
  end
  nil
end

def build_random_wild_analog_chain!(rng)
  stock = ANALOG_WILD_STOCKS.sample(random: rng)
  fx = GRADE_FX_POOL.shuffle(random: rng).first(rng.rand(5..8)).uniq
  unless fx.any? { |f| f.include?("warmth") || f.include?("saturation") }
    fx.unshift("spectral_warmth")
  end
  unless fx.any? { |f| f.include?("noise") || f.include?("crackle") }
    fx << "analog_noise"
  end
  name = :"wild_#{(@stream_iterate_count || 0)}_#{rng.rand(1000..9999)}"
  @stream_wild_analog_chain = { name: name, stock: stock, fx: fx.uniq }
  name
end

def analog_resolve_variant(track: nil, rotate_index: nil)
  explicit = ENV["ANALOG_CHAIN"]&.strip
  if explicit && !explicit.empty? && explicit != "auto"
    key = explicit.to_sym
    return key if analog_chain_lookup(key)
    return build_random_wild_analog_chain!(Random.new(Time.now.to_i + Process.pid)) if %w[wild wild_random random].include?(explicit)
  end
  idx = rotate_index
  unless idx
    t = track || ENV["TRACK"]
    idx = TAPE_RENDER_CATALOG.index { |e| e[:preset].to_s == t.to_s } if t
    idx ||= 0
  end
  pool = ANALOG_CHAIN_ROTATE + ANALOG_CHAIN_WILD_ROTATE
  pool[idx % pool.length]
end

def analog_emulation_filters(input_tag, variant, out_tag: "ana_out")
  cfg = analog_chain_lookup(variant) || ANALOG_CHAIN_VARIANTS.fetch(variant)
  stock = AUDIO_STOCKS[cfg[:stock]]
  parts = cfg[:fx].map { |fx| grade_filter(fx, stock) }.compact
  return ["[#{input_tag}]anull[#{out_tag}]"] if parts.empty?
  segs = []
  tag = input_tag
  parts.each_with_index do |filt, i|
    nxt = "ana#{i}"
    segs << "[#{tag}]#{filt}[#{nxt}]"
    tag = nxt
  end
  segs << "[#{tag}]lowpass=f=#{stock[:rolloff_hz]}[#{out_tag}]"
  segs
end

def analog_list
  puts "Analog chain variants (ANALOG_CHAIN= or auto-rotate per session):"
  ANALOG_CHAIN_VARIANTS.each do |name, cfg|
    puts "  #{name}: #{cfg[:fx].join(' → ')} [#{cfg[:stock]}]"
  end
  puts "Wild mashups (stream auto-iterate + ANALOG_CHAIN=wild):"
  ANALOG_CHAIN_WILD.each do |name, cfg|
    puts "  #{name}: #{cfg[:fx].join(' → ')} [#{cfg[:stock]}]"
  end
end

def sonitex_enabled?
  !sonitex_resolve_preset.nil?
end

def sonitex_config(track: nil)
  SONITEX_PRESETS.fetch(sonitex_resolve_preset(track:) || :classic)
end

def sonitex_label
  preset = sonitex_resolve_preset
  return "dry" unless preset
  variant = analog_resolve_variant
  "Sonitex STX-1260 (#{preset}) + analog:#{variant}"
end

def sonitex_list
  puts "Sonitex STX-1260 presets (SONITEX_PRESET= or SONITEX=):"
  SONITEX_PRESETS.each_key do |name|
    mark = name == (sonitex_resolve_preset || :classic) ? " *" : ""
    puts "  #{name}#{mark}"
  end
end

# ST-1260 life-span chain — ends at snx_out; limiter applied in master_bus_filters.
def sonitex_tape_filters(input_tag = "mix", out_tag: "snx_out")
  unless sonitex_enabled?
    return ["[#{input_tag}]alimiter=limit=0.90:level_out=0.92[out]"]
  end
  s = sonitex_config
  d = s[:dist_drive]
  n = Math.tanh(d).round(6)
  dry_w = (1.0 - s[:dist_mix]).round(3)
  wet_w = s[:dist_mix].round(3)
  pop_dyn = s[:pop_amp].round(3)
  [
    "[#{input_tag}]acompressor=threshold=#{s[:comp_threshold]}dB:ratio=#{s[:comp_ratio]}:attack=#{s[:comp_attack]}:release=#{s[:comp_release]}:makeup=#{s[:comp_makeup]}[snx1]",
    "[snx1]extrastereo=m=#{s[:stereo_width]}[snx2]",
    "[snx2]asplit=2[snx_dry][snx_wet]",
    "[snx_wet]equalizer=f=2800:t=o:w=1.2:g=#{s[:dist_pre_emph_db]},lowpass=f=#{s[:dist_pre_lp]}[snx_pre]",
    "[snx_pre]aeval=exprs='tanh(#{d}*(val(0)+#{s[:dist_dc]}))/#{n}|tanh(#{d}*(val(1)+#{s[:dist_dc]}))/#{n}'[snx_sat]",
    "[snx_sat]equalizer=f=2800:t=o:w=1.2:g=#{-s[:dist_pre_emph_db]}[snx_de]",
    "[snx_dry][snx_de]amix=inputs=2:weights=#{dry_w} #{wet_w}:duration=longest[snx3]",
    "[snx3]highpass=f=#{s[:lf_rolloff]}:width_type=q:width=0.9," \
    "equalizer=f=#{s[:head_bump_hz]}:t=o:w=0.82:g=#{s[:head_bump_db]}," \
    "equalizer=f=82:t=o:w=2:g=#{s[:warmth_db]}," \
    "lowpass=f=#{s[:hf_rolloff]}:width_type=q:width=0.85," \
    "lowpass=f=#{s[:groove_wear_lp]}[snx4]",
    "[snx4]vibrato=f=#{s[:wow_rate]}:d=#{s[:wow_depth]}[snx5]",
    "[snx5]vibrato=f=#{s[:flutter_hz]}:d=#{s[:flutter_depth]}[snx6]",
    "[snx6]lowpass=f=#{s[:phone_lp]},equalizer=f=#{s[:sibilance_hz]}:t=o:w=1.1:g=#{s[:sibilance_db]}[snx7]",
    "[snx7]aeval=exprs='(val(0)+#{s[:hiss_amp]}*(random(0)-0.5))|" \
    "(val(1)+#{s[:hiss_amp]}*(random(1)-0.5))'[snx8]",
    "[snx8]aeval=exprs='val(0)+if(lt(random(2),#{s[:pop_rate]}),(random(3)-0.5)*#{pop_dyn}*max(0.15,1-1.8*abs(val(0))),0)|" \
    "val(1)+if(lt(random(4),#{s[:click_rate]}),(random(5)-0.5)*#{(pop_dyn * 0.55).round(3)}*max(0.15,1-1.8*abs(val(1))),0)'[snx9]",
    "[snx9]acrusher=bits=#{s[:crush_bits]}:samples=#{s[:crush_sr]}:mix=#{s[:crush_mix]}[snx10]",
    "[snx10]lowpass=f=#{s[:crush_post_lp]}[snx11]",
    "[snx11]aeval=exprs='#{HEDD}'[snx12]",
    "[snx12]acompressor=threshold=#{s[:out_comp_threshold]}dB:ratio=#{s[:out_comp_ratio]}:attack=22:release=120:makeup=#{s[:out_comp_makeup]}[#{out_tag}]"
  ]
end

# Dilla drum bus — NY parallel compression, sub bump, mix low-pass from measured centroid (~1061 Hz).
def dilla_mix_preprocess_filters(input_tag = "mix", out_tag: "dpre")
  [
    "[#{input_tag}]asplit=2[dm_dry][dm_par]",
    "[dm_par]acompressor=threshold=-30dB:ratio=4.5:attack=2:release=48:makeup=3.0[dm_pc]",
    "[dm_dry][dm_pc]amix=inputs=2:weights=0.80 0.20:duration=first[dm_ny]",
    "[dm_ny]extrastereo=m=1.14[dm_wide]",
    "[dm_wide]equalizer=f=58:t=o:w=0.7:g=5.2,equalizer=f=92:t=o:w=1.2:g=3.6," \
    "equalizer=f=2200:t=o:w=1.4:g=-3.2,lowpass=f=2400[#{out_tag}]"
  ]
end

# Sonitex + creative analog grade stack + streaming loudness delivery.
# loudnorm supplies EBU R128 integrated loudness and true-peak analysis (including
# its oversampled peak path); the final limiter remains a deterministic last guard.
MASTER_TARGET_LUFS = -17.0
MASTER_TARGET_LRA = 11.0
TRUE_PEAK_CEILING_DB = -1.0
TRUE_PEAK_CEILING_LINEAR = (10**(TRUE_PEAK_CEILING_DB / 20.0)).round(4)

def true_peak_guard_filter(input_tag, out_tag: "out")
  if ENV["DEBUG_NO_LOUDNORM"]
    return "[#{input_tag}]alimiter=limit=#{TRUE_PEAK_CEILING_LINEAR}:attack=1:release=40:level=disabled[#{out_tag}]"
  end
  "[#{input_tag}]loudnorm=I=#{MASTER_TARGET_LUFS}:TP=#{TRUE_PEAK_CEILING_DB}:LRA=#{MASTER_TARGET_LRA}," \
    "aresample=#{SAMPLE_RATE}," \
    "alimiter=limit=#{TRUE_PEAK_CEILING_LINEAR}:attack=1:release=40:level=disabled[#{out_tag}]"
end

# dilla_mix_preprocess_filters' NY drum bump (+5.2dB@58Hz/+3.6dB@92Hz) and
# every Sonitex preset's own warmth/head-bump EQ both re-boost the same
# sub-100Hz band the sample bass and synth bass already occupy, at various
# points earlier in the chain — repeatedly undoing any balance correction
# placed before them. This is the one point both the dry and Sonitex paths
# funnel through right before the final safety limiter, so it's the only
# place a correction here actually sticks.
def mix_bass_chord_balance_filter(input_tag, out_tag: "balanced")
  # Sonitex warmth re-boosts sub; this stage tames sustained bass so chords
  # stay clear. On Camel/FlyLo the same -11dB@95Hz was also deleting kick
  # fundamentals — protect the 45–70Hz pocket when the kit is primary.
  if flylo_primary_drums?
    cut = sonitex_enabled? ? -5.5 : -3.5
    boost = sonitex_enabled? ? 5.5 : 4.5
    kick_restore = 4.2
  else
    cut = sonitex_enabled? ? -11.0 : -7.0
    boost = sonitex_enabled? ? 8.0 : 6.0
    kick_restore = deep_render? ? 2.4 : 1.6
    cut -= 1.5 if deep_render?
    boost += 1.2 if deep_render?
  end
  "[#{input_tag}]bass=g=#{cut}:f=95:width_type=h:w=170,equalizer=f=300:t=h:w=360:g=#{boost}," \
    "equalizer=f=55:t=o:w=0.75:g=#{kick_restore}[#{out_tag}]"
end

# Real mix-engineering technique: sum everything below ~120Hz to mono.
# Stereo-widened sub content cancels on real speakers/systems (especially
# mono or near-mono playback) and phase-cancellation down there is where
# translation problems actually come from — the highs can stay wide.
def sub_bass_mono_filter(input_tag, out_tag: "monobassed")
  "[#{input_tag}]asplit=2[sblo_src][sbhi_src];" \
  "[sblo_src]lowpass=f=120,pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1[sblo];" \
  "[sbhi_src]highpass=f=120[sbhi];" \
  "[sblo][sbhi]amix=inputs=2:weights=1.0 1.0:duration=first:normalize=0[#{out_tag}]"
end

# Very slow, very subtle continuous pitch/tempo drift — real tape/vinyl
# never holds perfectly still. Two independent slow LFOs (not locked to
# the same rate) so it doesn't read as a single obvious wobble.
def analog_drift_filter(input_tag, out_tag: "drifted")
  "[#{input_tag}]vibrato=f=0.13:d=0.0035,vibrato=f=0.19:d=0.002[#{out_tag}]"
end

CONVOLUTION_IR_CACHE = File.join(SCRATCH_DIR, "ir_%s.wav")

# Real convolution reverb via ffmpeg's afir filter — genuinely convolving
# against an impulse response, just a synthesized one (exponentially
# decaying filtered noise per "room") rather than a recorded one, since no
# real IR files exist in this repo. That's a legitimate, standard way to
# build a reverb IR algorithmically, not a fake stand-in for the effect.
CONVOLUTION_ROOMS = {
  plate: { decay: 2.6, color: "highpass=f=400,lowpass=f=6000" },
  room: { decay: 1.1, color: "highpass=f=120,lowpass=f=4500" },
  chamber: { decay: 3.4, color: "highpass=f=200,lowpass=f=3200" }
}.freeze

def synth_impulse_response!(room)
  path = format(CONVOLUTION_IR_CACHE, room)
  return path if File.exist?(path)
  FileUtils.mkdir_p(SCRATCH_DIR)
  cfg = CONVOLUTION_ROOMS.fetch(room)
  decay_rate = (3.0 / cfg[:decay]).round(3)
  sh! "ffmpeg", "-y", "-f", "lavfi", "-i", "anoisesrc=color=white:d=#{cfg[:decay] + 0.3}:r=#{SAMPLE_RATE}",
      "-af", "aeval=exprs='val(0)*exp(-#{decay_rate}*t)|val(1)*exp(-#{decay_rate}*t)',#{cfg[:color]}",
      "-ac", "2", "-ar", SAMPLE_RATE.to_s, path
  path
end

# Real convolution against the synthesized IR (via ffmpeg's afir filter),
# ir_input_idx being the ffmpeg -i index the caller has already added —
# same pattern as the self-sample bus: this function only builds the
# filter-graph string, the caller owns adding the actual -i input.
def convolution_reverb_filter(input_tag, ir_input_idx, mix: 0.16, out_tag: "convolved")
  "[#{input_tag}]asplit=2[#{out_tag}dry][#{out_tag}wetsrc];" \
    "[#{out_tag}wetsrc][#{ir_input_idx}:a]afir=dry=0:wet=10[#{out_tag}wet];" \
    "[#{out_tag}dry][#{out_tag}wet]amix=inputs=2:weights=#{(1.0 - mix).round(2)} #{mix}:duration=first:normalize=0[#{out_tag}]"
end

# Darker/deeper tonal color: gentle high rolloff (less brightness/major
# "shimmer") plus a bit more low-mid weight — moodier without changing any
# chord quality, on top of the STREAM_TRACKS rotation now leaning minor.
def mood_darken_filter(input_tag, out_tag: "darkened", strength: 1.0)
  hi_cut = (-3.5 * strength).round(1)
  low_boost = (2.0 * strength).round(1)
  ceiling = strength < 0.7 ? 12_500 : 11_000
  "[#{input_tag}]equalizer=f=5500:t=h:w=4000:g=#{hi_cut},equalizer=f=220:t=h:w=180:g=#{low_boost},lowpass=f=#{ceiling}[#{out_tag}]"
end

# A real destabilizing moment, not another polite EQ nudge: heavy
# lowpass+bitcrush gate right before the build lands, then a short hard
# silence gap — the mix actually breaks for a beat instead of just getting
# brighter. Fires at 79% through, build_up_filter picks up right after.
def break_filter(input_tag, duration, out_tag: "broke")
  break_t = (duration * 0.79).round(2)
  gate_dur = 0.6
  silence_dur = 0.18
  "[#{input_tag}]" \
    "lowpass=f=600:enable='between(t,#{break_t},#{break_t + gate_dur})'," \
    "acrusher=bits=6:samples=8:mix=0.8:enable='between(t,#{break_t},#{break_t + gate_dur})'," \
    "volume=0:enable='between(t,#{break_t + gate_dur},#{break_t + gate_dur + silence_dur})'" \
    "[#{out_tag}]"
end

# A real build-up: rising loudness + rising brightness across the final
# stretch of the track (last ~18%), landing right as the hook returns
# (fugue recapitulation) — structural energy, not just a static mix.
def build_up_filter(input_tag, duration, out_tag: "built")
  build_up_filter_enhanced(input_tag, duration, out_tag:)
end

def master_bus_filters(input_tag = "mix", track: nil, duration: nil, ir_input_idx: nil, cfg: nil)
  cfg ||= dilla_resolve_config
  filt = master_bus_filters_enhanced(input_tag, cfg:, duration:, ir_input_idx:)
  return filt unless DillaMaster.enabled?

  guard = filt.pop
  pre = guard[/\A\[(\w+)\]/, 1] || "built"
  mh = DillaMaster.extra_filters(pre, cfg:, duration:)
  filt.concat(mh) if mh.any?
  inlet = mh.any? ? "#{pre}_mh" : pre
  filt << guard.sub("[#{pre}]", "[#{inlet}]")
  filt
end

def grade(input = nil, output = nil, preset_name = nil)
  input       ||= prompt("audio path")
  preset_name ||= prompt("preset (#{GRADE_PRESETS.keys.join(', ')})")
  output      ||= input.sub(/(\.\w+)\z/, "_#{preset_name}\\1")
  abort "missing #{input}" unless File.exist?(input)
  p = GRADE_PRESETS[preset_name.to_sym] or abort "unknown preset: #{preset_name}. valid: #{GRADE_PRESETS.keys.join(', ')}"
  stock   = AUDIO_STOCKS[p[:stock]]
  filters = p[:fx].map { |fx| grade_filter(fx, stock) }.compact
  abort "no filters for preset #{preset_name}" if filters.empty?
  chain = [filters, "lowpass=f=#{stock[:rolloff_hz]}"].flatten.join(",")
  sh! "ffmpeg", "-y", "-i", input, "-af", chain, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
end

def grade_list
  GRADE_PRESETS.each do |name, p|
    stock = p[:stock]
    puts "#{name}: #{p[:fx].join(' → ')} [#{stock}]"
  end
end

# --- Live playback ---

# Render a short preview and play it immediately via ffplay.
TTS_WORKER = File.expand_path("../../bin/tts-worker", ROOT)
# Funny-but-clear Edge voices — avoid heavy pitch/effects that hurt intelligibility.
SPEECH_VOICES = %w[en-US-AndrewNeural en-US-GuyNeural en-US-BrianMultilingualNeural].freeze
SPEECH_VOICE_DEFAULT = "en-US-AndrewNeural"
# MASTER's own TTS (MASTER/bin/tts-worker, Edge TTS one-shot mode) speaking
# over the beat — real speech, not a stub, mixed in quiet. Original pickup
# lines, not lyrics from any real song (those are copyrighted).
SPEECH_LINES = [
  "is your name Google? because you're everything I've been searching for",
  "are you made of copper and tellurium? because you're Cu-Te",
  "do you have a map? I just keep getting lost in your eyes",
  "if you were a vegetable, you'd be a cute-cumber",
  "are you a parking ticket? because you've got fine written all over you",
  "is there an airport nearby, or is that just my heart taking off",
  "do you believe in love at first sight, or should I walk by again",
  "are you a magician? because whenever I look at you, everyone else disappears",
  "I was going to say something really sweet about your smile, but you distracted me",
  "excuse me, I think you dropped something: my jaw",
  "are you French? because Eiffel for you",
  "if I could rearrange the alphabet, I'd put U and I together",
  "do you have a sunburn, or are you always this hot",
  "are you a campfire? because you're hot and I want s'more",
  "is it hot in here, or is it just you",
  "are you a time traveler? because I can totally see you in my future",
  "I'm not a photographer, but I can picture us together",
  "do you have a Band-Aid? because I just scraped my knee falling for you"
].freeze

# Comedic voice archetypes — text-level character, not a different TTS
# voice (Edge TTS gives no per-phrase SSML control, confirmed: only a
# single whole-utterance rate/pitch pair per call, no <break>/<emphasis>).
ARCHETYPE_LINES = [
  "aaand she reaches for the volume knob — CLASSIC move, folks",
  "you love to see it, absolute peak performance right there",
  "duuude, this whole track is, like, a whole vibe, for real",
  "it was a Tuesday. the coffee was cold. so was the mix",
  "if I may be so bold, your energy this evening is... quite something",
  "but wait — there's MORE. so much more",
  "ladies and gentlemen, what a play, what an absolute masterclass",
  "the pocket was tight that night. tighter than my budget",
  "one does not simply walk into a groove this deep"
].freeze

FILLER_SUBJECTS = %w[
  your smile your laugh that outfit this playlist your energy the room
  this beat your timing that look you your vibe this moment
].freeze
FILLER_VERBS = %w[
  is throwing off is stealing is rewriting is upgrading is complicating
  is improving is derailing is soundtracking is elevating is haunting
].freeze
FILLER_TOPICS = %w[
  my whole schedule my train of thought my entire plan my focus
  my Friday night my next three decisions my playlist my composure
].freeze

def filler_sentence(rng)
  "#{FILLER_SUBJECTS.sample(random: rng)} #{FILLER_VERBS.sample(random: rng)}, #{FILLER_TOPICS.sample(random: rng)}, yeah."
end

# Real text-level "impediment" character that stays intelligible: light
# stutter-repeat on ~1 in 6 words (never every word — that's where
# intelligibility actually breaks) and elongated vowels on emphasis words.
# Edge TTS renders repeated letters as real duration, so this reads as
# comic timing rather than garbage — confirmed, not assumed.
def quirkify(text, rng)
  words = text.split(" ")
  words.map do |w|
    clean = w.gsub(/[^a-zA-Z']/, "")
    next w if clean.length < 3
    if rng.rand < 0.16
      "#{clean[0]}-#{clean[0]}-#{w}"
    elsif rng.rand < 0.10
      w.sub(/([aeiouAEIOU])(?!.*[aeiouAEIOU])/) { $1 * 3 }
    else
      w
    end
  end.join(" ")
end

# Speech quirk lines — no faker gem; harmony/MIDI/WAV outsourced to :dilla gems when bundled —
# local word-bank generator instead, mixed with the curated lines, gives
# enough varied text to talk continuously rather than one clip per track.
def continuous_speech_text(duration, seed: nil)
  rng = seed ? Random.new(seed) : Random.new
  words_needed = (duration * 2.1).to_i
  sentences = []
  word_count = 0
  while word_count < words_needed
    s = case rng.rand
        when 0...0.28 then SPEECH_LINES.sample(random: rng)
        when 0.28...0.40 then ARCHETYPE_LINES.sample(random: rng)
        else filler_sentence(rng)
        end
    s = quirkify(s, rng) if rng.rand < speech_quirk_probability
    sentences << s
    word_count += s.split.length
  end
  sentences.join(" ")
end

# Real structure, not a smooth gate: ~20-30s of talking, then ~20-30s of
# real silence, repeating — actual separately-synthesized segments placed
# at their own start times, not a tremolo faking it (tremolo's 0.1Hz floor
# can't reach a cycle this slow anyway).
SPEECH_TALK_SEC = 22.0
SPEECH_CYCLE_SEC = 62.0

def speech_quirk_probability
  ENV.fetch("SPEAK_QUIRK", "0.12").to_f.clamp(0.0, 1.0)
end

def speech_tts_voice
  v = ENV["SPEAK_VOICE"].to_s.strip
  return v if !v.empty? && SPEECH_VOICES.include?(v)
  SPEECH_VOICE_DEFAULT
end

def speech_tts_rate
  ENV.fetch("SPEAK_RATE", "-48%")
end

def speech_tts_pitch
  ENV.fetch("SPEAK_PITCH", "+8Hz")
end

def speech_talk_length
  base = if ENV["DILLA_STREAMING"] == "1"
           (ENV["SPEECH_TALK_STREAM"] || "14").to_f
         else
           SPEECH_TALK_SEC
         end
  base + (ENV["DILLA_STREAMING"] == "1" ? 0.0 : (rand - 0.5) * 6.0)
end

def speech_max_segments
  return nil unless ENV["DILLA_STREAMING"] == "1"
  [(ENV["SPEECH_MAX_SEGMENTS"] || "1").to_i, 1].max
end

def stream_track_banner(extra = nil)
  tag = ENV["TRACK"] || "?"
  lead_on = lead_arp_enabled? || harmony_lead_enabled?
  lead_tag = if lead_on
               ENV["LEAD_VOICE"] || @render_lead_patch&.dig(:id) || "on"
             else
               "0"
             end
  arp_tag = lead_on ? (ENV["LEAD_ARP_MODE"] || lead_arp_mode || pad_arp_mode) : "off"
  rap_tag = rap_vocal_stream_slug || "0"
  drum_tag = flylo_primary_drums? ? "flylo" : ENV.fetch("KICKS", "1")
  meta = "pad=#{ENV['PAD_VOICE']}/#{pad_arp_mode} lead=#{lead_tag}/#{arp_tag} " \
         "drums=#{drum_tag} rap=#{rap_tag} speak=#{ENV.fetch('SPEAK', '0')}"
  meta = "#{meta} #{extra}" if extra
  DillaDmesg.track!(tag, meta)
end

def speech_over_track_enabled?
  return false if ENV["SPEAK"] == "0"
  # Was auto-on whenever DILLA_STREAMING=1; now requires explicit SPEAK=1.
  ENV["SPEAK"] == "1"
end

def speak_over_track!(mp3_path, duration, _bpm = 90.0)
  return mp3_path unless File.executable?(TTS_WORKER) && tool_available?("ffmpeg")
  voice = speech_tts_voice
  rate = speech_tts_rate
  pitch = speech_tts_pitch
  segments = []
  # Never talk right at t=0 — that reads as a scripted "intro" every time a
  # track starts/loops. Let the track establish itself first.
  t = 10.0 + rand * 14.0
  idx = 0
  max_seg = speech_max_segments
  while t < duration
    break if max_seg && idx >= max_seg
    talk_len = speech_talk_length
    text = continuous_speech_text(talk_len, seed: idx + rand(100_000))
    seg_path = "#{mp3_path}.voice#{idx}.mp3"
    ok = false
    Open3.popen2(Gem.ruby, TTS_WORKER, voice, rate, pitch, seg_path) { |stdin, _stdout, wait|
      stdin.write(text)
      stdin.close
      ok = wait.value.success?
    }
    unless ok
      warn "speech: TTS segment #{idx} failed (#{voice})"
      break
    end
    segments << { path: seg_path, start: t } if File.exist?(seg_path) && File.size(seg_path) > 500
    t += SPEECH_CYCLE_SEC + (rand - 0.5) * 8.0
    idx += 1
  end
  return mp3_path if segments.empty?

  # Dry, intelligible speech over the beat — no echo/delay/chorus; timing only.
  vol = (ENV["SPEAK_VOL"] || "0.82").to_f
  inputs = []
  filter_parts = []
  labels = []
  segments.each_with_index do |seg, i|
    inputs += ["-i", seg[:path]]
    delay_ms = (seg[:start] * 1000).round
    filter_parts << "[#{i + 1}:a]aformat=channel_layouts=stereo," \
                     "highpass=f=90,lowpass=f=11000," \
                     "adelay=#{delay_ms}|#{delay_ms},volume=#{vol}[voice#{i}]"
    labels << "[voice#{i}]"
  end
  filter_parts << "#{labels.join}amix=inputs=#{labels.length}:duration=first:normalize=0[voicemix]"
  filter_parts << "[0:a][voicemix]amix=inputs=2:duration=first:normalize=0[out]"

  tmp = "#{mp3_path}.spoken.mp3"
  sh! "ffmpeg", "-y", "-i", mp3_path, *inputs,
      "-filter_complex", filter_parts.join(";"),
      "-map", "[out]", "-c:a", "libmp3lame", "-b:a", "320k", tmp
  FileUtils.mv(tmp, mp3_path)
  mp3_path
ensure
  segments&.each { |s| FileUtils.rm_f(s[:path]) }
end

# Stream / demo capture — WAV skips lame encode (faster than demo.mp3).
def stream_demo_path
  name = ENV.fetch("STREAM_DEMO", "demo.wav")
  name = "demo.wav" if name.empty?
  path = File.expand_path(name, OUTPUT_DIR)
  path = "#{path}.wav" unless path.match?(/\.(wav|mp3|flac|ogg|aiff?)\z/i)
  path
end

def stream_save_demo?
  return true if ENV["DILLA_STREAMING"] == "1"
  ENV.fetch("STREAM_SAVE_DEMO", "0") != "0"
end

def play(preset_name = nil, bars_count = 8)
  require_playback_tool!
  preset_name ||= "dilla"
  keep_demo = stream_save_demo?
  # WAV during stream: pcm_s16le only — no libmp3lame pass (faster cycle).
  out = keep_demo ? stream_demo_path : scratch_path("play_tmp.wav")
  prev = ENV["BARS"]
  ENV["BARS"] = bars_count.to_s
  attempts = play_render_attempts
  attempts.times do |try|
    pick_render_seed! if try.positive?
    if preset_name == "dilla"
      render_dilla(out)
    else
      render(out)
    end
    ok = if quality_gate_enabled?
           render_quality_acceptable?(out)
         elsif stream_iterate_enabled?
           stream_iterate_acceptable?(out)
         else
           true
         end
    break if ok
    dmesg_warn("render retry #{try + 1}/#{attempts}") if try + 1 < attempts
  end
  # Never let iterate/promote crashes skip speaker playback.
  begin
    stream_iterate_after_render!(out) if stream_iterate_enabled? && File.file?(out)
  rescue StandardError => e
    warn "stream iterate: #{e.class} — #{e.message} (still playing)"
  end
  begin
    log_render_meta(out) if quality_gate_enabled? || ENV["DILLA_STREAMING"] == "1"
  rescue StandardError => e
    warn "log_render_meta: #{e.message}"
  end
  if speech_over_track_enabled?
    cfg = dilla_resolve_config
    track_duration = (60.0 / cfg[:bpm]) * 4.0 * bars_count.to_i
    dmesg("speech overlay #{speech_tts_voice} rate=#{speech_tts_rate}", unit: "speech0", parent: "dilla0")
    speak_over_track!(out, track_duration, cfg[:bpm])
  end
  DillaDmesg.write!(out) if keep_demo && File.file?(out)
  play_audio(out)
ensure
  if defined?(prev)
    prev ? ENV["BARS"] = prev : ENV.delete("BARS")
  end
  FileUtils.rm_f(out) if defined?(out) && defined?(keep_demo) && !keep_demo
end

# Loop a WAV via ffplay (rb-only playback).
def play_loop(path)
  require_playback_tool!
  abort "missing #{path}" unless File.exist?(path)
  cfg = dilla_resolve_config
  prog = CHORD_PROGRESSIONS[cfg[:progression]]
  prog_names = prog.is_a?(Array) ? prog.join(" → ") : cfg[:progression].to_s
  dmesg("loop #{File.basename(path)} #{File.size(path)}B bpm=#{cfg[:bpm].to_i}", unit: "play0", parent: "dilla0")
  dmesg("progression #{prog_names}", unit: "harm0", parent: "dilla0")
  dmesg("ctrl-c to stop", unit: "play0", parent: "dilla0")
  play_audio(path, loop: true)
end

# Instant playback — cached WAV, no render wait.
def live_now
  harm = File.join(ROOT, ".harmony_loud.wav")
  full = File.join(ROOT, ".live_tmp.wav")
  path = File.exist?(harm) ? harm : full
  abort "no cache — run: ruby dilla.rb regenerate" unless File.exist?(path)
  play_loop(path)
end

# Harmony-forward stem mix from cached drum + harmonic renders.
def build_harmony_loud(
  drums: File.join(ROOT, ".dilla_drums.wav"),
  harmonic: File.join(ROOT, ".dilla_harmonic.wav"),
  out: File.join(ROOT, ".harmony_loud.wav")
)
  abort "missing #{drums}" unless File.exist?(drums)
  abort "missing #{harmonic}" unless File.exist?(harmonic)
  dur = capture("ffprobe", "-v", "error", "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1", harmonic).first.to_f
  dur = [dur, 8.0].max
  drum_vol = (ENV["DRUM_VOL"] || "0.38").to_f
  harm_gain = (ENV["HARM_VOL"] || "2.45").to_f
  harm_chain = "aformat=channel_layouts=stereo,lowpass=f=3200,aecho=0.35:0.4:120:0.32," \
               "volume=#{harm_gain},alimiter=limit=0.96:level_out=0.99"
  if drum_vol <= 0.001
    filt = "[0:a]#{harm_chain}[out]"
    sh! "ffmpeg", "-y", "-i", harmonic, "-filter_complex", filt,
        "-map", "[out]", "-t", dur.round(3).to_s, "-c:a", "pcm_s16le", out
    puts "wrote #{out} (#{dur.round(1)}s harmony-only, drums muted)"
  else
    filt = [
      "[1:a]#{harm_chain}[harm]",
      "[0:a]aformat=channel_layouts=stereo,volume=#{drum_vol}[drm]",
      "[drm][harm]amix=inputs=2:weights=1.0 1.0:duration=first:normalize=0[out]"
    ].join(";")
    sh! "ffmpeg", "-y", "-i", drums, "-i", harmonic, "-filter_complex", filt,
        "-map", "[out]", "-t", dur.round(3).to_s, "-c:a", "pcm_s16le", out
    puts "wrote #{out} (#{dur.round(1)}s harmony-forward, drums=#{drum_vol})"
  end
  out
end

# Fresh render + harmony-forward mix + ffplay loop.
def regenerate(bars_count = 16)
  require_tools! "ffmpeg"
  bars_count = (ENV["BARS"] || bars_count).to_i
  tmp = File.join(ROOT, ".live_tmp.wav")
  harm = File.join(ROOT, ".harmony_loud.wav")
  puts "regenerating #{bars_count} bars (TRACK=#{ENV['TRACK'] || 'timeless'})…"
  render_dilla(tmp, bars_count, keep_stems: true)
  build_harmony_loud
  puts "wrote #{tmp}"
  play_loop(harm)
end

# Chords + melody up front — loops .harmony_loud.wav.
def harmony_now
  harm = File.join(ROOT, ".harmony_loud.wav")
  drums = File.join(ROOT, ".dilla_drums.wav")
  harmonic = File.join(ROOT, ".dilla_harmonic.wav")
  if ENV["REBUILD"] == "1" || !File.exist?(harm)
    if File.exist?(drums) && File.exist?(harmonic)
      build_harmony_loud
    else
      abort "no harmony mix — run: ruby dilla.rb regenerate"
    end
  end
  play_loop(harm)
end

# Loop full master — .live_tmp.wav via ffplay.
def live(bars_count = 32)
  tmp = File.join(ROOT, ".live_tmp.wav")
  unless File.exist?(tmp)
    quick = [4, bars_count].min
    puts "no cache — warming #{quick} bars first (~15s)"
    render_dilla(tmp, quick)
    if bars_count > quick
      puts "rendering full #{bars_count} bars…"
      render_dilla(tmp, bars_count)
    end
  end
  play_loop(tmp)
rescue SystemCallError => e
  abort "playback failed: #{e.message}"
end

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

# Best-track defaults — applied on every invocation unless already set (or
# DILLA_RAW=1). Bare `ruby dilla.rb` uses deep mode on top of these.
DILLA_BEST_DEFAULTS = {
  "DILLA_DEEP" => "1",
  "PAD_VOICE" => "blend",
  "PAD_ARP_MODE" => "wash",
  "LEAD_VOICE" => "soul_prophet",
  "LEAD_ARP_MODE" => "soul_wash",
  "LEAD_ARP" => "1",
  "EXPERIMENTAL_LEADS" => "1",
  "SOUL_ENRICH" => "1",
  "SYNTH_CYCLE" => "0",
  "LUSH_SYNTH" => "1",
  "REHARM_LOOP" => "0",
  "PAD_TEXTURE" => "0",
  "CREEPY_PATCHES" => "0",
  # donuts_warm's hf_rolloff/groove_wear_lp sit at 2200/2600Hz (see the
  # "not a 2 kHz blanket" comment on its donuts_soul sibling) and its
  # out_comp_ratio runs a full point hotter — buries presence/air and
  # sits crest factor right at the reject-gate floor. DILLA_STYLE_DEFAULTS
  # already uses donuts_soul; this table (applied first) was overriding it.
  "SONITEX" => "donuts_soul",
  "SONITEX_PRESET" => "donuts_soul",
  "ANALOG_CHAIN" => "acetate",
  "DRUM_PRESET" => "dilla_slight",
  "EXTERNAL_KIT" => "03-soulful-vintage",
  "PERFORMER" => "yancey",
  "GROOVE_DNA" => "donuts",
  "COMPOSITION" => "1",
  "MARKOV_DRUMS" => "1",
  "FLAM" => "1",
  "GROOVE_LOCK" => "kick",
  "VINYL" => "35",
  "KICK_GAIN" => "0.34",
  "KICKS" => "1",
  "BASS_SLIDE" => "1",
  "SPECTRAL_ARP" => "0",
  "INDUSTRIAL_DARK" => "0",
  "MASTER_HEURISTICS" => "0",
  "GHOST_TIER" => "pocket",
  "MOTIF_RECALL" => "1",
  "SLASH_BASS" => "0",
  "PROMOTION_BEAUTY_MIN" => "78",
  "GROOVE_SCORE_MIN" => "75"
}.freeze

RENDER_MODE_DEFAULTS = {
  sketch: {
    "STEM_EXPORT" => "0", "COMPOSITION" => "0", "LISTEN_PASSES" => "0",
    "DILLA_QUALITY_GATE" => "0", "MARKOV_DRUMS" => "1", "GHOST_TIER" => "pocket",
    "RENDER_BEAUTY_MIN" => "55", "KEEP_STEMS" => "0"
  },
  record: {
    "STEM_EXPORT" => "1", "COMPOSITION" => "1", "LISTEN_PASSES" => "2",
    "DILLA_QUALITY_GATE" => "1", "KEEP_STEMS" => "1", "RENDER_BEAUTY_MIN" => "72",
    "MOTIF_RECALL" => "1"
  },
  perform: {
    "STEM_EXPORT" => "1", "COMPOSITION" => "1", "LISTEN_PASSES" => "3",
    "DILLA_QUALITY_GATE" => "1", "STREAM_EVOLVE_PERFORMER" => "1",
    "RENDER_BEAUTY_MIN" => "75", "MOTIF_RECALL" => "1", "SLASH_BASS" => "1",
    "KEEP_STEMS" => "1", "GHOST_TIER" => "accent"
  },
  long_soul: {
    "FORM" => "soul_32", "COMPOSITION" => "1", "VOICING" => "bill_evans",
    "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "PAD_VOL" => "58",
    "LEAD_ARP" => "1", "HARMONY_LEAD" => "1", "HARMONY_LEP_MODE" => "hybrid",
    "LUSH_SYNTH" => "1", "LONG_STRIPDOWN" => "1", "MOTIF_RECALL" => "1",
    "GROOVE_DNA" => "donuts", "PERFORMER" => "yancey",
    "SONITEX" => "donuts_warm", "SONITEX_PRESET" => "donuts_warm",
    "ANALOG_CHAIN" => "vinyl_hot", "CONV_REVERB" => "chamber",
    "TRACK" => "long_soul", "BARS" => "32"
  },
  golden: {
    "FORM" => "donuts_time", "COMPOSITION" => "1", "VOICING" => "kenny_barron",
    "PAD_ATTACK" => "1500", "PAD_RELEASE" => "4000", "PAD_VOL" => "58",
    "LEAD_ARP" => "1", "HARMONY_LEAD" => "1", "HARMONY_LEP_MODE" => "hybrid",
    "LUSH_SYNTH" => "1", "LONG_STRIPDOWN" => "1", "MOTIF_RECALL" => "1",
    "GROOVE_DNA" => "donuts", "PERFORMER" => "yancey",
    "SONITEX" => "donuts_warm", "SONITEX_PRESET" => "donuts_warm",
    "ANALOG_CHAIN" => "cassette", "CONV_REVERB" => "chamber",
    "TRACK" => "golden", "BARS" => "32"
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
    "BARS" => "32"
  },
  # camel / dilla style: single table DILLA_STYLE_DEFAULTS below.
  camel: {},
  dilla: {}
}.freeze

# Single stream/render style — pad-forward curated progressions + locked 16-step kit.
DILLA_STYLE_DEFAULTS = {
  # Ethan Hein exact Get Dis Money slash cycle (artist-verified).
  "TRACK" => "get_dis_money",
  "PROGRESSION" => "get_dis_money",
  "BPM" => "92",
  "BARS" => "32",
  "FORM" => "camel_32",
  "COMPOSITION" => "1",
  "GROOVE_DNA" => "donuts",
  "PERFORMER" => "yancey",
  "VOICING" => "rootless",
  "VOICE_LEAD_PADS" => "1",
  "LEARNED_PROGRESSION" => "0",
  # Stacked pad: Rhodes + Moog + Prophet + texture (see PAD_LAYER_STACKS).
  "PAD_VOICE" => "stack_soul",
  # Held pads; arps live on the lead stem (stream rotates LEAD_ARP_MODE).
  "PAD_ARP_MODE" => "held",
  "PAD_ATTACK" => "1100",
  "PAD_RELEASE" => "3400",
  "PAD_LEGATO_VAR" => "1",
  "PAD_LAYERS" => "1",
  "LUSH_SYNTH" => "1",
  "LONG_STRIPDOWN" => "0",
  "MOTIF_RECALL" => "1",
  # Hybrid pocket + FlyLo overlay so kick/snare/hat/clap all read on speakers.
  # FLYLO_DRUMS_ONLY=1 + KICKS=0 was "no-kicks" and buried the hat bus under pads.
  "KICKS" => "1",
  "POCKET_KICKS" => "1",
  "FLYLO_DRUMS_ONLY" => "0",
  "FLYLO_DRUM_OVERLAY" => "1",
  "FLYLO_QUINT_HATS" => "1",
  # These three gains stack multiplicatively on the same kick signal —
  # 1.55*1.25*1.15 ~= 2.23x (+7dB) compounded was the likely cause of
  # "drums too loud" direct feedback. ~1.26x (+2dB) keeps the kit-forward
  # intent (kick was previously buried under pads) without the overshoot.
  "FLYLO_KICK_GAIN" => "1.2",
  "KICK_SAMPLE_GAIN" => "1.05",
  "KICK_GAIN" => "1.0",
  "POCKET_DNA" => "1",
  "POCKET_SIMPLE" => "1",
  "POCKET_GHOSTS" => "1",
  "POCKET_OPEN_HAT" => "1",
  "SNARE_EARLY" => "1",
  "HATS_LATE" => "1",
  "KICK_LATE" => "1",
  "KICK_FREEHAND" => "1",
  "HAT_MICRO" => "1",
  "SWING_JITTER" => "1",
  "GROOVE_ENGINE" => "1",
  "DRUM_CHOPS" => "1",
  "NO_QUANTIZE" => "1",
  "BACKBEAT_CLAP" => "1",
  # Jonas V isolated vocals — sit on top of the kit, not under pads.
  "RAP_VOCAL" => "jonas_v",
  "RAP_VOCAL_STYLE" => "rap",
  "RAP_VOCAL_MIX" => "1.85",
  "RAP_VOCAL_WEIGHT" => "1.75",
  "RAP_VOCAL_BED_WEIGHT" => "0.72",
  "RAP_VOCAL_DUCK" => "0.58",
  "RAP_VOCAL_SIDECHAIN" => "1",
  "LA_BEAT_PROGRESSION" => "0",
  "LINEAR_CHORD_INDEX" => "1",
  # Rotate full progression pack (not only the 10 verified names).
  "ARTIST_VERIFIED_ONLY" => "0",
  "HARMONY_LEAD" => "1",
  "SCALE_LEAD" => "1",
  "CREATIVE_LEAD" => "1",
  # Real arps (not just slow melodic phrases) — MELODIC_LEAD=0 forces subdiv arps.
  "MELODIC_LEAD" => "0",
  "LEAD_ARP" => "1",
  "LEAD_ARP_MODE" => "flylo_spiral",
  "LEAD_VOICE" => "soul_prophet",
  "EXPERIMENTAL_LEADS" => "1",
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
  "SIDECHAIN_STYLE" => "flylo",
  "SONITEX" => "donuts_soul",
  "SONITEX_PRESET" => "donuts_soul",
  "ANALOG_CHAIN" => "broadcast",
  "DRUM_PRESET" => "dilla_slight",
  # Kit-forward but not snare/shaker walls — tops (hats/snares/claps) sat ~2×
  # over kicks when TOP_MIX/MERGE and air EQ were maxed for laptop speakers.
  "FLYLO_OVERLAY_GAIN" => "1.35",
  "FLYLO_SUB_MIX" => "1.55",
  "FLYLO_TOP_MIX" => "0.95",
  "FLYLO_MERGE_BOOST" => "1.55",
  "FLYLO_BASE_DRUM_VOL" => "1.0",
  "DRUM_BUS_VOL" => "1.45",
  "DRUM_BUS_GAIN" => "1.35",
  "DRUM_MIX_WEIGHT" => "1.55",
  "DRUM_PEAK_DB" => "-1.5",
  "DRUM_AIR_DB" => "3.5",
  "DRUM_PRESENCE_DB" => "3.0",
  # Pads step back so kick/hat/vocal occupy the mix.
  "HARM_MIX_WEIGHT" => "1.05",
  "HARM_BUS_VOL" => "1.35",
  "HARM_BODY_DB" => "2.2",
  "HARM_MID_DB" => "1.8",
  "HARM_PRESENCE_DB" => "1.6",
  "HARM_AIR_DB" => "0.8",
  "HARM_SUB_CUT_DB" => "-4.0",
  "HARM_SUB_SHELF_DB" => "0.6",
  "SIDECHAIN_DRUM_WEIGHT" => "1.65",
  "SIDECHAIN_HARM_WEIGHT" => "1.05",
  "FLYLO_CHORD_DUCK" => "0.88",
  "HARMONIC_PADS_WEIGHT" => "1.05",
  "HARMONIC_PADS_VOLUME" => "1.15",
  "PAD_VOL" => "58",
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
  "VINYL" => "0",
  "SELF_SAMPLE" => "0",
  "RADIO_BERGEN" => "0",
  "STREAM_CONTINUOUS" => "1",
  "STREAM_GAP" => "0.25",
  "STREAM_CROSSFADE" => "0.08",
  "STREAM_DEMO" => "demo.wav",
  "STREAM_NORMALIZE" => "1",
  "STREAM_LUFS" => "-16.5",
  "STREAM_TRUE_PEAK" => "-1.5",
  "STREAM_LRA" => "11",
  # Dilla's documented MPC sweet spot is 54-58% (Dilla Time + producer
  # consensus); 60+ reads as over-swung rather than the authentic pocket.
  "SWING" => "56",
  "MASTER_HEURISTICS" => "1",
  # Slow tempo-breathe over a phrase (not per-hit noise) + periodic full-layer
  # drop-out for arrangement contrast — see DillaGroove.phrase_drift_sec and
  # DillaRhythm.periodic_layer_drop_gain.
  "PHRASE_DRIFT" => "1",
  "ARRANGEMENT_VARIATION" => "1"
}.freeze

# Back-compat name used by camel_mode paths.
CAMEL_MODE_DEFAULTS = DILLA_STYLE_DEFAULTS

STREAM_SOUL_DEFAULTS = {
  "STREAM_SOUL" => "1",
  "FORM" => "soul_32",
  "BARS" => "32",
  "LA_BEAT_PROGRESSION" => "0",
  "LINEAR_CHORD_INDEX" => "1",
  "PAD_LEGATO_VAR" => "1",
  "LEAD_ARP" => "1",
  "LEAD_ARP_MODE" => "melodic_soul",
  "LEAD_VOICE" => "soul_prophet",
  "MELODIC_LEAD" => "1",
  "SCALE_LEAD" => "0",
  "CREATIVE_LEAD" => "0",
  "HARMONY_LEAD" => "0",
  "PAD_VOICE" => "stack_soul",
  "PAD_ARP_MODE" => "held",
  "PAD_LAYERS" => "1",
  "PAD_VOL" => "74",
  "VOICING" => "rootless",
  "VOICE_LEAD_PADS" => "1",
  "LEARNED_PROGRESSION" => "0",
  "STREAM_LOCK" => "0",
  "TRACK" => "get_dis_money",
  "PROGRESSION" => "get_dis_money",
  "ARTIST_VERIFIED_ONLY" => "1",
  "RADIO_BERGEN" => "0",
  "SPEAK" => "0",
  "MOTIF_RECALL" => "1",
  "LUSH_SYNTH" => "1",
  "PAD_ATTACK" => "1400",
  "PAD_RELEASE" => "3600",
  "LONG_STRIPDOWN" => "0",
  "STREAM_LEARN_BIAS" => "0",
  "PROMOTION_BEAUTY_MIN" => "85",
  "FLYLO_DRUM_OVERLAY" => "1",
  "FLYLO_QUINT_HATS" => "0",
  "FLYLO_OVERLAY_GAIN" => "1.0",
  # Jonas V acapella (rap-vocal ingest) — tempo-fit per track BPM.
  "RAP_VOCAL" => "jonas_v",
  "RAP_VOCAL_STYLE" => "rap",
  "RAP_VOCAL_MIX" => "1.55",
  "RAP_VOCAL_WEIGHT" => "1.35",
  "RAP_VOCAL_BED_WEIGHT" => "0.92",
  "RAP_VOCAL_DUCK" => "0.72",
  "RAP_VOCAL_SIDECHAIN" => "1",
  "SIDECHAIN_STYLE" => "flylo",
  "SYNTH_MORPH" => "0",
  "SYNTH_CYCLE" => "1",
  "LEAD_MORPH" => "0",
  "FM_NATIVE" => "1",
  "EXPERIMENTAL_LEADS" => "0",
  "HARMONIC_PADS_WEIGHT" => "1.85",
  "HARMONIC_PADS_VOLUME" => "1.85",
  "HARMONIC_LEAD_ARP_WEIGHT" => "1.55",
  "HARMONIC_LEAD_ARP_VOLUME" => "1.85",
  "HARMONIC_XLEAD_WEIGHT" => "0.15",
  "HARMONIC_XLEAD_VOLUME" => "0.35"
}.freeze

GHOST_TIERS = {
  whisper: { mul: 0.58, steps_scale: 0.72, fill_mul: 0.35 },
  pocket:  { mul: 1.0,  steps_scale: 1.0,  fill_mul: 1.0 },
  accent:  { mul: 1.28, steps_scale: 1.18, fill_mul: 1.45 }
}.freeze

SLASH_BASS_PROFILES = %i[
  syncopated_slash_ninth syncopated_slash_alt slash_neo_soul slash_ninth_cycle
  minor_dominant_slash_cycle
].freeze

PROMOTED_PROFILES_PATH = File.join(DillaComposition::PROJECT_DIR, "promoted_profiles.json").freeze

# Deep render — quality gate, soul rotation, long pads, pocket jitter, mix refine.
DILLA_DEEP_DEFAULTS = {
  "DILLA_QUALITY_GATE" => "1",
  "PHONE_PREVIEW_GATE" => "1",
  "RENDER_RETRIES" => "2",
  "LISTEN_PASSES" => "1",
  "QUALITY_REPORT" => "1",
  "RENDER_BEAUTY_MIN" => "70",
  "PAD_ATTACK" => "920",
  "PAD_RELEASE" => "2600",
  "PAD_VOL" => "52",
  "QUINTUPLET" => "1",
  "SWING_JITTER" => "1",
  "LONG_STRIPDOWN" => "1",
  "EVOLVE_HARMONY_W" => "0.18",
  "CONV_REVERB" => "chamber"
}.freeze

STREAM_EXTRA_DEFAULTS = {
  "DRUM_VOL" => "0.85",
  "DILLA_STREAMING" => "1",
  "PLAY_VOL" => "1",
  # Speech overlay disabled — beat only until re-enabled (SPEAK=1 or --speak=1).
  "SPEAK" => "0",
  "SPEAK_VOICE" => "en-US-AndrewNeural",
  "SPEAK_RATE" => "-48%",
  "SPEAK_PITCH" => "+8Hz",
  "SPEAK_VOL" => "0.82",
  "SPEAK_QUIRK" => "0.12",
  # Kit balanced for speakers (force after style table) — tops quieter than kicks.
  "KICKS" => "1",
  "POCKET_KICKS" => "1",
  "FLYLO_DRUMS_ONLY" => "0",
  "FLYLO_DRUM_OVERLAY" => "1",
  "FLYLO_QUINT_HATS" => "1",
  "BACKBEAT_CLAP" => "1",
  "KICK_GAIN" => "1.2",
  "FLYLO_KICK_GAIN" => "1.45",
  "FLYLO_OVERLAY_GAIN" => "1.35",
  "FLYLO_SUB_MIX" => "1.55",
  "FLYLO_TOP_MIX" => "0.95",
  "FLYLO_MERGE_BOOST" => "1.55",
  "FLYLO_BASE_DRUM_VOL" => "1.0",
  "DRUM_BUS_VOL" => "1.45",
  "DRUM_BUS_GAIN" => "1.35",
  "DRUM_MIX_WEIGHT" => "1.55",
  "DRUM_AIR_DB" => "3.5",
  "DRUM_PRESENCE_DB" => "3.0",
  "HARM_MIX_WEIGHT" => "1.05",
  "HARM_BUS_VOL" => "1.35",
  "HARMONIC_PADS_WEIGHT" => "1.05",
  "HARMONIC_PADS_VOLUME" => "1.15",
  "PAD_VOL" => "58",
  "RADIO_BERGEN" => "0",
  "STREAM_ITERATE" => "1",
  "SPEECH_MAX_SEGMENTS" => "1",
  "SPEECH_TALK_STREAM" => "14",
  "STREAM_CONTINUOUS" => "1",
  # Shorter tracks = less silence between hearable audio.
  "STREAM_BARS" => "12",
  "STREAM_GAP" => "0.05",
  "STREAM_CROSSFADE" => "0",
  "STREAM_TRACK_TIMEOUT" => "300",
  # Jonas V vocals — loud, tempo-matched.
  "RAP_VOCAL" => "jonas_v",
  "RAP_VOCAL_STYLE" => "rap",
  "RAP_VOCAL_MIX" => "1.85",
  "RAP_VOCAL_WEIGHT" => "1.75",
  "RAP_VOCAL_BED_WEIGHT" => "0.72",
  "RAP_VOCAL_DUCK" => "0.58",
  "RAP_VOCAL_SIDECHAIN" => "1",
  "STREAM_NORMALIZE" => "1",
  "STREAM_LUFS" => "-14.5",
  "STREAM_TRUE_PEAK" => "-1.0",
  "STREAM_LRA" => "9",
  "STREAM_ROTATE_LEAD" => "1",
  "STREAM_ROTATE_SYNTH" => "1",
  "STREAM_LEAD_MIDI_RICH" => "1",
  "LEAD_FORCE_ARP" => "1",
  "MELODIC_LEAD" => "0",
  "LEAD_ARP" => "1",
  "EXPERIMENTAL_LEADS" => "1",
  "LEAD_MORPH" => "1",
  "SYNTH_MORPH" => "1",
  "SYNTH_CYCLE" => "1",
  "ARTIST_VERIFIED_ONLY" => "0",
  # Creativity max (re-applied AFTER apply_dilla_style force — see force_env!).
  "STREAM_CREATIVE_FREEDOM" => "1",
  "STREAM_ANALOG_WILD" => "1",
  "STREAM_ANALOG_EVERY" => "1",
  "EVOLVE_EVERY" => "1",
  "STREAM_HARMONY_EVERY" => "1",
  "STREAM_EVOLVE_PERFORMER" => "1",
  "STREAM_LEARN_BIAS" => "1",
  "LA_BEAT_PROGRESSION" => "1",
  "LUSH_SYNTH" => "1",
  "PAD_TEXTURE" => "1",
  "FM_NATIVE" => "1",
  "VINYL" => "1",
  "SELF_SAMPLE" => "1",
  "CONV_REVERB" => "chamber",
  "CAMEL_CLEAN_MASTER" => "0",
  "CAMEL_NO_REVERB" => "0",
  "CAMEL_NO_BREAK" => "0",
  "PHONE_PREVIEW_GATE" => "0"
}.freeze

# Forced on every stream boot after style locks (force:true was wiping creativity).
STREAM_CREATIVE_MAX = STREAM_EXTRA_DEFAULTS.freeze

def stream_track_timeout_sec
  sec = (ENV["STREAM_TRACK_TIMEOUT"] || "420").to_i
  sec.positive? ? sec : nil
end

# Light auto-iterate during stream — beauty retry, mix/groove nudges, lead freedom.
STREAM_ITERATE_TUNING = {
  "RENDER_RETRIES" => "1",
  "RENDER_BEAUTY_MIN" => "55",
  "EVOLVE_EVERY" => "1",
  "LEAD_ARP" => "1",
  "EXPERIMENTAL_LEADS" => "1",
  "SYNTH_CYCLE" => "1",
  "SYNTH_MORPH" => "1",
  "LEAD_MORPH" => "1",
  "LUSH_SYNTH" => "1",
  "STREAM_EVOLVE_PERFORMER" => "1",
  "STREAM_CREATIVE_FREEDOM" => "1",
  "PHONE_PREVIEW_GATE" => "0",
  "EVOLVE_GROOVE_W" => "0.35",
  "EVOLVE_HARMONY_W" => "0.32",
  "GROOVE_SCORE_MIN" => "70",
  "MOTIF_RECALL" => "1",
  "STREAM_HARMONY_EVERY" => "1",
  "STREAM_ANALOG_EVERY" => "1",
  "STREAM_ANALOG_WILD" => "1",
  "STREAM_LEARN_BIAS" => "1"
}.freeze

# STREAM_FAST_DEFAULTS must not clobber these when iterate is on.
STREAM_ITERATE_OVERRIDE_KEYS = %w[
  RENDER_RETRIES LISTEN_PASSES RENDER_BEAUTY_MIN EVOLVE_EVERY
  LEAD_ARP EXPERIMENTAL_LEADS STREAM_EVOLVE_PERFORMER STREAM_CREATIVE_FREEDOM
  STREAM_HARMONY_EVERY STREAM_ANALOG_EVERY STREAM_ANALOG_WILD STREAM_LEARN_BIAS
].freeze

STREAM_ITERATE_LOG = File.join(ROOT, "stream_iterate.log").freeze

# Fast stream — render+play without quality gate / listen refine (~15–30s/track).
STREAM_FAST_DEFAULTS = {
  "DILLA_DEEP" => "0",
  "DILLA_QUALITY_GATE" => "0",
  "PHONE_PREVIEW_GATE" => "0",
  "RENDER_RETRIES" => "0",
  "LISTEN_PASSES" => "0",
  "QUALITY_REPORT" => "0",
  "CONV_REVERB" => "0",
  "LEAD_ARP" => "0"
}.freeze

def deep_render?
  ENV.fetch("DILLA_DEEP", "0") != "0"
end

def stream_deep?
  ENV["STREAM_DEEP"] == "1"
end

def quality_gate_enabled?
  ENV["DILLA_QUALITY_GATE"] == "1"
end

def stream_iterate_enabled?
  ENV.fetch("STREAM_ITERATE", "1") != "0" && ENV["DILLA_STREAMING"] == "1"
end

def stream_creative_freedom_enabled?
  stream_iterate_enabled? && ENV.fetch("STREAM_CREATIVE_FREEDOM", "1") != "0"
end

def play_render_attempts
  if quality_gate_enabled?
    [STREAM_MAX_RETRIES, (ENV["RENDER_RETRIES"] || "2").to_i].max + 1
  elsif stream_iterate_enabled?
    retries = [(ENV["RENDER_RETRIES"] || "1").to_i, 1].max
    retries + 1
  else
    1
  end
end

def stream_iterate_acceptable?(path)
  return true unless stream_iterate_enabled?
  return true unless File.file?(path)
  beauty = DillaHarmony.score_beauty(DillaHarmony.last_progression_chords)
  spectrum = render_spectrum(path)
  harsh = DillaMaster.analyze_harshness(spectrum)
  min = (ENV["RENDER_BEAUTY_MIN"] || "65").to_f
  ok = beauty >= min && !harsh[:needs_notch]
  if ok && phone_preview_gate_enabled?
    phone_path = DillaMaster.apply_phone_preview!(path)
    phone_spec = render_spectrum(phone_path)
    phone = DillaMaster.phone_preview_acceptable?(phone_spec)
    unless phone[:ok]
      warn "stream iterate phone gate: mid=#{phone[:mid_db]} dB low-mid=#{phone[:low_mid_delta]} dB"
      ok = false
    end
    FileUtils.rm_f(phone_path) if phone_path != path && phone_path.end_with?(".phone.wav")
  end
  ok
end

# Style-lock keys — reassert after track soul / iterate so the mix doesn't drift.
# Exclude lead/synth/progression-rotation keys so stream can cycle voices + arps.
DILLA_STYLE_LOCK_KEYS = (
  DILLA_STYLE_DEFAULTS.keys - %w[
    TRACK PROGRESSION LEAD_VOICE LEAD_ARP_MODE LEAD_ARP PAD_VOICE
    MELODIC_LEAD SCALE_LEAD CREATIVE_LEAD HARMONY_LEAD
    SYNTH_MORPH SYNTH_CYCLE LEAD_MORPH EXPERIMENTAL_LEADS
    ARTIST_VERIFIED_ONLY STREAM_CREATIVE_FREEDOM STREAM_ROTATE_SYNTH STREAM_ROTATE_LEAD
  ]
).freeze

# Pad stack only — do NOT lock lead voice / arp mode (stream rotates those).
DILLA_PAD_LEAD_LOCK_KEYS = %w[
  PAD_LAYERS PAD_VOL PAD_ARP_MODE
  LEARNED_PROGRESSION VOICE_LEAD_PADS VOICING
  HARMONIC_PADS_WEIGHT HARMONIC_PADS_VOLUME
  HARMONIC_LEAD_ARP_WEIGHT HARMONIC_LEAD_ARP_VOLUME
  HARMONIC_SCALE_LEAD_WEIGHT HARMONIC_SCALE_LEAD_VOLUME
  HARMONIC_HARMONY_LEAD_WEIGHT HARMONIC_HARMONY_LEAD_VOLUME
  HARMONIC_LEAD_WEIGHT HARMONIC_LEAD_VOLUME
].freeze

# Lead arp modes cycled each stream track (real figures, not held wash).
STREAM_LEAD_ARP_ROTATION = %i[
  flylo_spiral neo_quartal soul_wash moog_funk prophet_glass
  donuts_shimmer pocket_stab glass_spin vapor_wave acid_run
  crystal_scatter erykah_dust gospel_lift ballad_bloom melodic_soul
].freeze

STREAM_LEAD_VOICE_ROTATION = %w[
  soul_prophet flylo moog prophet neo_pluck glass vapor
  crystal acid soft ballad gospel erykah donuts cs
].freeze

STREAM_PAD_VOICE_ROTATION = %w[blend rhodes moog prophet].freeze

# Which defaults table last touched each ENV key, and how (fill vs force) —
# multiple tables (DILLA_BEST_DEFAULTS, RENDER_MODE_DEFAULTS,
# DILLA_STYLE_DEFAULTS, STREAM_EXTRA_DEFAULTS/STREAM_CREATIVE_MAX) apply in
# sequence, soft-fill only wins races when nothing set the key first, and
# that ordering has caused real, silent bugs (a style table's setting
# permanently losing to an earlier table because apply_render_mode! hadn't
# run yet). See "config-provenance" command.
def config_provenance
  @config_provenance ||= {}
end

def record_config_provenance!(key, label, verb)
  return unless label
  config_provenance[key] = "#{label} (#{verb})"
end

def soft_fill_env!(table, label: nil)
  table.each do |key, value|
    next if value.nil?
    if ENV[key].nil? || ENV[key].empty?
      ENV[key] = value.to_s
      record_config_provenance!(key, label, "fill")
    end
  end
end

# Overwrite ENV keys (stream creative layer after style force-locks).
def force_env!(table, label: nil)
  table.each do |key, value|
    next if value.nil?
    ENV[key.to_s] = value.to_s
    record_config_provenance!(key.to_s, label, "force")
  end
end

def print_config_provenance
  if config_provenance.empty?
    puts "config-provenance: empty — run a render first (soft_fill_env!/force_env! haven't been called with labels yet)"
    return
  end
  width = config_provenance.keys.map(&:length).max
  config_provenance.sort.each { |key, source| puts "#{key.ljust(width)}  #{source}  = #{ENV[key].inspect}" }
end

def soft_fill_iterate!(tuning, locked_keys: [])
  locked = locked_keys.map(&:to_s)
  tuning.each do |key, value|
    next if value.nil?
    next if locked.include?(key.to_s)
    next if ENV[key] && !ENV[key].empty?
    ENV[key] = value.to_s
  end
end

def reassert_pad_lead_locks!
  return unless camel_mode? || ENV["RENDER_MODE"].to_s.downcase == "dilla"
  DILLA_PAD_LEAD_LOCK_KEYS.each do |key|
    next unless DILLA_STYLE_DEFAULTS.key?(key)
    ENV[key] = DILLA_STYLE_DEFAULTS[key].to_s
  end
end

def reassert_dilla_style_locks!
  return unless camel_mode? || ENV["RENDER_MODE"].to_s.downcase == "dilla"
  DILLA_STYLE_LOCK_KEYS.each do |key|
    next unless DILLA_STYLE_DEFAULTS.key?(key)
    ENV[key] = DILLA_STYLE_DEFAULTS[key].to_s
  end
  atk = [ENV["PAD_ATTACK"].to_i, DILLA_STYLE_DEFAULTS["PAD_ATTACK"].to_i].max
  rel = [ENV["PAD_RELEASE"].to_i, DILLA_STYLE_DEFAULTS["PAD_RELEASE"].to_i].max
  ENV["PAD_ATTACK"] = atk.to_s
  ENV["PAD_RELEASE"] = rel.to_s
end

def reassert_camel_beauty_locks!
  reassert_dilla_style_locks!
end

# Loss-gate report for stream promote — RadioBergenStudy#analyze_audio is
# module-private; DeepAudio has the dynamics block gates need.
def stream_analyze_for_gates(path)
  RadioBergenStudy::DeepAudio.analyze(path)
rescue StandardError
  RadioBergenStudy.analyze_audio(path) if RadioBergenStudy.respond_to?(:analyze_audio)
rescue StandardError
  nil
end

def stream_iterate_after_render!(path)
  return unless File.file?(path)
  @stream_iterate_count = (@stream_iterate_count || 0) + 1
  beauty = DillaHarmony.score_beauty(DillaHarmony.last_progression_chords)
  spectrum = render_spectrum(path)
  harsh = DillaMaster.analyze_harshness(spectrum)
  sk = DillaMaster.sub_kick_balance(spectrum, beauty)
  notes = []
  # Dilla-style stream: soft mix nudges only — no morph / grid rewrite / analog roulette.
  if camel_mode?
    if sk[:recommendation] == "boost_sub"
      notes << "sub_ok"
    end
    if harsh[:needs_notch]
      notes << "harsh_soft"
    end
    promote_progression_hook!(ENV["TRACK"].to_s, beauty,
                               report: (stream_analyze_for_gates(path) if DillaMaster.loss_gates.any?),
                               path: path)
    notes.concat(stream_iterate_evolve_harmony!) if (@stream_iterate_count % 4).zero?
    reassert_camel_beauty_locks!
    line = "[#{Time.now.utc.iso8601}] ##{@stream_iterate_count} track=#{ENV['TRACK']} beauty=#{beauty} " \
           "camel_beauty #{notes.join(' ')}"
    File.open(STREAM_ITERATE_LOG, "a") { |f| f.puts(line) }
    puts "stream iterate: beauty=#{beauty} camel_lock #{notes.join(', ')}"
    return
  end
  if refine_deep_mix_env!(path)
    notes << "kick=#{ENV['KICK_GAIN']} harm=#{ENV['DEBUG_HARM_WEIGHT']}"
  end
  if harsh[:needs_notch]
    dv = [(ENV["DRUM_VOL"] || "0.38").to_f - 0.03, 0.22].max
    ENV["DRUM_VOL"] = dv.round(2).to_s
    notes << "drum_vol=#{ENV['DRUM_VOL']}"
  end
  if sk[:recommendation] == "boost_sub" && (ENV["PAD_VOL"] || "52").to_i < 58
    ENV["PAD_VOL"] = ((ENV["PAD_VOL"] || "52").to_i + 2).to_s
    notes << "pad_vol=#{ENV['PAD_VOL']}"
  end
  groove_score = nil
  if instance_variable_defined?(:@last_drum_events) && @last_drum_events
    groove_score = DillaGrooveScore.analyze(@last_drum_events)[:score]
    @last_groove_score = groove_score
    notes << "groove=#{groove_score}"
  end
  promote_progression_hook!(ENV["TRACK"].to_s, beauty,
                             report: (stream_analyze_for_gates(path) if DillaMaster.loss_gates.any?),
                             path: path)
  every = [(ENV["EVOLVE_EVERY"] || "3").to_i, 1].max
  evolve_due = composition_enabled? && (@stream_iterate_count % every).zero?
  groove_low = groove_score && groove_score < (ENV["GROOVE_SCORE_MIN"] || "75").to_f
  if evolve_due
    stream_evolve_composition!
    stream_evolve_pocket!
    notes << "evolved"
  elsif groove_low
    stream_evolve_pocket!
    notes << "pocket_nudge"
  end
  if stream_creative_freedom_enabled?
    notes.concat(stream_iterate_creative_freedom!)
  end
  notes.concat(stream_iterate_evolve_harmony!)
  notes.concat(stream_iterate_evolve_flylo_drums!)
  notes.concat(stream_iterate_analog_emulation!)
  line = "[#{Time.now.utc.iso8601}] ##{@stream_iterate_count} track=#{ENV['TRACK']} beauty=#{beauty} " \
         "sub=#{sk[:recommendation]} harsh=#{harsh[:harshness]} #{notes.join(' ')}"
  File.open(STREAM_ITERATE_LOG, "a") { |f| f.puts(line) }
  puts "stream iterate: beauty=#{beauty} #{notes.join(', ')}"
end

def stream_evolve_composition!
  return unless composition_enabled?
  bars = (ENV["BARS"] || STREAM_BARS_COUNT).to_i
  track = ENV["TRACK"].to_s
  sess = composition_session!(n_bars: bars, track: track)
  keep_performer = ENV["PERFORMER"]
  keep_groove = ENV["GROOVE_DNA"]
  rng = Random.new(Time.now.to_i + Process.pid + (@stream_iterate_count || 0))
  sess.motifs.each { |m| m.evolve! if rng.rand < 0.35 }
  if ENV.fetch("STREAM_EVOLVE_PERFORMER", "0") == "1"
    sess.mutate!
    ENV["PERFORMER"] = sess.performer.to_s
    ENV["GROOVE_DNA"] = sess.groove_dna.to_s
  else
    ENV["PERFORMER"] = keep_performer if keep_performer && !keep_performer.empty?
    ENV["GROOVE_DNA"] = keep_groove if keep_groove && !keep_groove.empty?
    sess.instance_variable_set(:@generation, sess.generation + 1)
  end
  cfg = dilla_resolve_config
  ENV["SWING"] = cfg[:swing].round(1).to_s if cfg[:swing]
  sess.save!
  puts "stream evolve gen=#{sess.generation} performer=#{ENV['PERFORMER']} groove=#{ENV['GROOVE_DNA']}"
end

def stream_evolve_pocket!(groove_analysis: nil)
  return unless stream_iterate_enabled?
  cfg = dilla_resolve_config
  return unless DillaComposition::Evolution.dilla_pocket_style?(cfg)
  rng = Random.new(Time.now.to_i + Process.pid + (@stream_iterate_count || 0) + 17)
  events = groove_analysis || (instance_variable_defined?(:@last_drum_events) ? @last_drum_events : nil)
  recs = events ? DillaGrooveScore.evolve_recommendations(DillaGrooveScore.analyze(events)) : {}
  @last_groove_score = recs[:score]

  ENV["SNARE_EARLY"] = recs[:snare_early] == false ? "0" : "1"
  ENV["HATS_LATE"] = recs[:hats_late] == false ? "0" : "1"
  ENV["GROOVE_LOCK"] = "kick"
  ENV["FLAM"] = "1"
  ENV["MARKOV_DRUMS"] = "1" if recs[:markov_ghosts]
  ENV["GHOST_TIER"] = recs[:ghost_tier].to_s if recs[:ghost_tier]

  delta = recs[:swing_delta] || rng.rand(-1.5..1.5)
  swing = (cfg[:swing] || 57).to_f + delta + rng.rand(-0.8..0.8)
  ENV["SWING"] = swing.clamp(52, 62).round(1).to_s
  ENV["SWING_JITTER_TICKS"] = (recs[:jitter_ticks] || 3).to_s

  if rng.rand < 0.45 || recs[:groove_pool]
    pool = recs[:groove_pool] || %w[donuts fantastic_vol2 endtroducing madvillainy]
    ENV["GROOVE_DNA"] = pool.sample(random: rng)
  end

  ENV["GHOST_BOOST_NUDGE"] = recs[:ghost_boost_nudge].round(3).to_s if recs[:ghost_boost_nudge]
  ENV["VELOCITY_SPREAD_NUDGE"] = recs[:velocity_spread_nudge].round(3).to_s if recs[:velocity_spread_nudge]

  ENV["SIDECHAIN_STYLE"] = "dilla" if cfg[:sidechain]
  score_note = @last_groove_score ? " groove_score=#{@last_groove_score}" : ""
  puts "stream pocket: swing=#{ENV['SWING']} groove=#{ENV['GROOVE_DNA']} tier=#{ENV['GHOST_TIER']}#{score_note}"
end

def load_promoted_track_bias
  return nil unless File.file?(PROMOTED_PROFILES_PATH)
  data = JSON.parse(File.read(PROMOTED_PROFILES_PATH))
  counts = data.reject { |k, _| k.start_with?("_") }
  top = counts.max_by { |_, v| v.to_i }
  top ? top.first.to_sym : nil
rescue StandardError
  nil
end

# Auto-iterate soul harmony: rotate voicing + Donuts-family tracks; bias promoted/learned profiles.
def stream_iterate_evolve_harmony!
  return [] unless stream_iterate_enabled?
  every = [(ENV["STREAM_HARMONY_EVERY"] || ENV["EVOLVE_EVERY"] || "2").to_i, 1].max
  return [] unless (@stream_iterate_count % every).zero?

  rng = Random.new(Time.now.to_i + Process.pid + (@stream_iterate_count || 0) + 31)
  notes = []

  soul_locked = ENV["STREAM_SOUL"] == "1" && ENV["STREAM_LOCK"] == "1"
  if ENV.fetch("STREAM_LEARN_BIAS", "0") != "0"
    if (hint = learn_catalog_top_hint)
      DillaSourceLearn.apply_hints_to_env!(hint)
      notes << "catalog_bias=#{hint[:track] || hint['track']}"
    end
    report = DillaSourceLearn.load_last_report
    if report && report[:engine_hints]
      DillaSourceLearn.apply_hints_to_env!(report[:engine_hints])
      notes << "learn_bias=#{report[:engine_hints][:track]}"
    end
  end

  promoted = load_promoted_track_bias
  if soul_locked
    apply_track_soul_profile!(ENV["TRACK"], force: false)
    notes << "soul_lock=#{ENV['TRACK']}"
  elsif promoted && SOUL_TRACK_FAMILY.include?(promoted) && rng.rand < 0.35
    ENV["TRACK"] = promoted.to_s
    apply_track_soul_profile!(ENV["TRACK"], force: false)
    notes << "promoted=#{promoted}"
  elsif rng.rand < 0.55
    pick = if promoted && SOUL_TRACK_FAMILY.include?(promoted) && rng.rand < 0.4
             promoted
           else
             SOUL_TRACK_FAMILY.sample(random: rng)
           end
    ENV["TRACK"] = pick.to_s
    apply_track_soul_profile!(ENV["TRACK"], force: false)
    notes << "track=#{pick}"
  end

  voicings = DillaHarmony::VOICING_STYLES
  voicing = voicings[(@stream_iterate_count + rng.rand(0..2)) % voicings.length]
  ENV["VOICING"] = voicing.to_s
  notes << "voicing=#{voicing}"

  w = (ENV["EVOLVE_HARMONY_W"] || "0.18").to_f
  ENV["EVOLVE_HARMONY_W"] = (w + rng.rand(-0.04..0.06)).clamp(0.08, 0.35).round(3).to_s
  notes << "harm_w=#{ENV['EVOLVE_HARMONY_W']}"

  notes
end

# Evolve FlyLo overlay density, grid bias, quint hats, and dual-bus mix across stream iterations.
def stream_iterate_evolve_flylo_drums!
  return [] unless flylo_drum_overlay_enabled? && stream_iterate_enabled?
  every = [(ENV["STREAM_FLYLO_EVERY"] || ENV["EVOLVE_EVERY"] || "2").to_i, 1].max
  return [] unless (@stream_iterate_count % every).zero?

  rng = Random.new(Time.now.to_i + Process.pid + (@stream_iterate_count || 0) + 67)
  notes = []
  remove_instance_variable(:@flylo_overlay_grid_cache) if instance_variable_defined?(:@flylo_overlay_grid_cache)

  ENV["FLYLO_OVERLAY_GAIN"] = rng.rand(0.62..0.88).round(2).to_s
  ENV["FLYLO_CHORD_DUCK"] = rng.rand(0.72..0.9).round(2).to_s
  ENV["FLYLO_SUB_MIX"] = rng.rand(0.42..0.58).round(2).to_s
  ENV["FLYLO_TOP_MIX"] = rng.rand(0.38..0.54).round(2).to_s
  ENV["FLYLO_GRID_BIAS"] = %i[intro main build turn breakdown outro].sample(random: rng).to_s
  ENV["FLYLO_QUINT_HATS"] = rng.rand < 0.75 ? "1" : "0"
  ENV["SIDECHAIN_STYLE"] = "flylo" if rng.rand < 0.4

  if ENV.fetch("STREAM_LEARN_BIAS", "0") != "0" && rng.rand < 0.45
    if (hint = learn_catalog_top_hint)
      DillaSourceLearn.apply_hints_to_env!(hint)
      notes << "flylo_learn=#{hint[:track] || hint['track']}"
    end
  end

  notes << "flylo_gain=#{ENV['FLYLO_OVERLAY_GAIN']}"
  notes << "flylo_grid=#{ENV['FLYLO_GRID_BIAS']}"
  notes << "flylo_quint=#{ENV['FLYLO_QUINT_HATS']}"
  notes << "drum_gain=#{ENV['DRUM_BUS_GAIN']}" if ENV["DRUM_BUS_GAIN"]
  notes << "rap_vocal=#{ENV['RAP_VOCAL']}" if rap_vocal_stream_slug
  notes
end

# Rotate Sonitex + analog grade stacks; wild random FX mashups for authentic chaos.
def stream_iterate_analog_emulation!
  return [] unless stream_iterate_enabled?
  # Camel “full sound” locks donuts_soul + summing_phasy; rotating to acetate/scuzz
  # re-introduces wall-of-noise and killed the pad character people liked.
  return [] if camel_mode? && ENV.fetch("CAMEL_LOCK_COLOR", "1") != "0"
  every = (ENV["STREAM_ANALOG_EVERY"] || "0").to_i
  return [] if every <= 0
  return [] unless (@stream_iterate_count % every).zero?

  rng = Random.new(Time.now.to_i + Process.pid + (@stream_iterate_count || 0) + 53)
  notes = []

  if ENV.fetch("STREAM_ANALOG_WILD", "1") != "0" && rng.rand < 0.35
    wild_name = build_random_wild_analog_chain!(rng)
    ENV["ANALOG_CHAIN"] = wild_name.to_s
    notes << "analog=#{wild_name}(#{@stream_wild_analog_chain[:fx].length}fx)"
  else
    pool = ANALOG_CHAIN_ROTATE + ANALOG_CHAIN_WILD_ROTATE
    pick = pool[(@stream_iterate_count + rng.rand(0..3)) % pool.length]
    ENV["ANALOG_CHAIN"] = pick.to_s
    @stream_wild_analog_chain = nil
    notes << "analog=#{pick}"
  end

  if rng.rand < 0.5
    sonitex = SONITEX_ROTATE_STREAM[(@stream_iterate_count + rng.rand(0..2)) % SONITEX_ROTATE_STREAM.length]
    ENV["SONITEX_PRESET"] = sonitex.to_s
    ENV["SONITEX"] = sonitex.to_s
    notes << "sonitex=#{sonitex}"
  end

  if rng.rand < 0.4
    cr = CONV_REVERB_ROTATE[(@stream_iterate_count + rng.rand(0..1)) % CONV_REVERB_ROTATE.length]
    ENV["CONV_REVERB"] = cr
    notes << "conv=#{cr}"
  end

  if rng.rand < 0.35
    vinyl = rng.rand(22..48).round
    ENV["VINYL"] = vinyl.to_s
    notes << "vinyl=#{vinyl}"
  end

  notes
end

# Rotate PAD_VOICE + fresh Rhodes/Prophet/Moog pool picks each stream iteration.
def stream_iterate_morph_synth!
  return [] unless synth_morph_enabled?
  voices = PAD_VOICE_MORPH_VOICES
  unless instance_variable_defined?(:@stream_user_pad_locked) && @stream_user_pad_locked
    ENV["PAD_VOICE"] = voices[(@stream_iterate_count || 0) % voices.length].to_s
  end
  @render_ep_patch = nil
  @render_warm_patch = nil
  @render_native_patch = nil
  @render_lead_patch = nil
  if lead_morph_enabled?
    unless instance_variable_defined?(:@stream_user_lead_locked) && @stream_user_lead_locked
      ENV["LEAD_MORPH_VOICE"] = LEAD_MORPH_VOICES[(@stream_iterate_count || 0) % LEAD_MORPH_VOICES.length].to_s
      arp_key = MORPH_LEAD_ARP_CYCLE[(@stream_iterate_count || 0) % MORPH_LEAD_ARP_CYCLE.length]
      ENV["LEAD_ARP_MODE"] = arp_key.to_s
    end
  end
  cfg = dilla_resolve_config
  pick_synth_patches!(cfg, bar: (@stream_iterate_count || 0) * 4)
  notes = [
    "morph_pad=#{ENV['PAD_VOICE']}",
    "ep=#{@render_ep_patch&.dig(:id)}",
    "warm=#{@render_warm_patch&.dig(:id)}"
  ]
  if lead_morph_enabled?
    notes << "morph_lead=#{ENV['LEAD_MORPH_VOICE'] || ENV['LEAD_VOICE']}"
    notes << "xlead_arp=#{ENV['LEAD_ARP_MODE']}"
    notes << "lead=#{@render_lead_patch&.dig(:id)}"
    notes << "fm_native=1" if fm_native_enabled?
  end
  notes
end

# Per-track creative rotation: new lead/scale patches, arp figures, stem balance.
def stream_iterate_creative_freedom!
  return [] unless stream_creative_freedom_enabled?
  pick_render_seed!
  @render_lead_patch = nil
  @render_scale_lead_patch = nil
  @render_arp_style = nil
  @render_scale_arp_style = nil
  notes = stream_iterate_morph_synth!
  unless notes.any?
    @render_ep_patch = nil
    @render_warm_patch = nil
    @render_native_patch = nil
    cfg = dilla_resolve_config
    pick_synth_patches!(cfg, bar: (@stream_iterate_count || 0) * 4)
  end
  rng = Random.new(Time.now.to_i + Process.pid + (@stream_iterate_count || 0) + (@render_seed || 0))
  styles = (@render_lead_patch&.dig(:arp_styles) || ARP_PATTERN_BUILDERS.keys).to_a
  @render_arp_style = styles.sample(random: rng)
  scale_styles = (@render_scale_lead_patch&.dig(:arp_styles) || styles).to_a
  @render_scale_arp_style = scale_styles.sample(random: rng)
  nudge = ->(key, field, delta) {
    base = harmonic_stem_mix_value(key, field)
    lo, hi = field == :weight ? [0.08, 1.6] : [0.4, 1.4]
    ENV["HARMONIC_#{key.to_s.upcase}_#{field.to_s.upcase}"] = (base + delta).clamp(lo, hi).round(3).to_s
  }
  nudge.call(:lead_arp, :weight, rng.rand(-0.06..0.08))
  nudge.call(:xlead, :weight, rng.rand(-0.04..0.1)) if lead_morph_enabled?
  nudge.call(:xlead, :volume, rng.rand(-0.06..0.08)) if lead_morph_enabled?
  nudge.call(:lead, :weight, rng.rand(-0.05..0.07))
  nudge.call(:scale_lead, :weight, rng.rand(-0.05..0.06))
  lead_id = @render_lead_patch&.dig(:id) || "lead"
  scale_id = @render_scale_lead_patch&.dig(:id) || "scale"
  notes + [
    "creative=#{@render_arp_style}/#{@render_scale_arp_style}",
    "leads=#{scale_id}+#{lead_id}",
    "stem_w=#{ENV['HARMONIC_LEAD_ARP_WEIGHT']}/#{ENV['HARMONIC_LEAD_WEIGHT']}"
  ]
end

def phone_preview_gate_enabled?
  ENV["PHONE_PREVIEW_GATE"] == "1"
end

def apply_render_mode!
  mode = ENV["RENDER_MODE"]&.downcase&.to_sym
  return unless mode
  table = if %i[camel dilla].include?(mode)
            DILLA_STYLE_DEFAULTS
          else
            RENDER_MODE_DEFAULTS[mode]
          end
  return unless table
  soft_fill_env!(table, label: table.equal?(DILLA_STYLE_DEFAULTS) ? "DILLA_STYLE_DEFAULTS" : "RENDER_MODE_DEFAULTS[#{mode}]")
  DillaDmesg.style!("mode=#{mode}") if ENV["DILLA_STREAMING"] != "1"
end

def motif_recall_enabled?
  ENV.fetch("MOTIF_RECALL", composition_enabled? ? "1" : "0") != "0"
end

def apply_motif_recall!(bar)
  return unless motif_recall_enabled?
  return unless composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
  return unless bar.positive? && (bar % 16).zero?
  sess = @composition_session
  cb = sess.callbacks.select { |c| c[:motif_id] == "hook" }.max_by { |c| c[:bar] }
  state = cb ? cb[:state] : :A
  sess.record_callback!(bar, "hook", state)
end

def promote_progression_hook!(track, beauty, report: nil, path: nil)
  return if track.to_s.empty?
  min = (ENV["PROMOTION_BEAUTY_MIN"] || "85").to_f
  return unless beauty >= min
  gate = DillaMaster.passes_loss_gates?(report, path: path)
  unless gate[:pass]
    warn "progression promotion blocked (loss gates): #{gate[:failures].join('; ')}"
    return
  end
  chords = DillaHarmony.last_progression_chords
  distinct = chords ? chords.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }.uniq.length : 0
  return unless distinct >= 6
  FileUtils.mkdir_p(DillaComposition::PROJECT_DIR)
  data = File.exist?(PROMOTED_PROFILES_PATH) ? JSON.parse(File.read(PROMOTED_PROFILES_PATH)) : {}
  key = track.to_s.downcase.tr("-", "_")
  data[key] = (data[key] || 0) + 1
  data["_last"] = { "track" => key, "beauty" => beauty.round(1), "at" => Time.now.utc.iso8601 }
  File.write(PROMOTED_PROFILES_PATH, JSON.pretty_generate(data) + "\n")
  remove_instance_variable(:@radio_bergen_learnings) if instance_variable_defined?(:@radio_bergen_learnings)
rescue StandardError => e
  warn "progression promotion failed: #{e.message}"
end

def apply_profile_mash!(cfg)
  mash = ENV["PROFILE_MASH"]
  return cfg unless mash&.include?("+")
  harm_key, drum_key = mash.split("+", 2).map { |s| s.strip.downcase.tr("-", "_").to_sym }
  harm_preset = track_preset(harm_key)
  drum_preset = track_preset(drum_key)
  return cfg unless harm_preset && drum_preset
  harm_sonic = sonic_profile_for(harm_key)
  feel = drum_preset[:feel] || cfg[:feel]
  cfg.merge(
    track: :"#{harm_key}_x_#{drum_key}",
    progression: (ENV["PROGRESSION"] || harm_preset.fetch(:progression, harm_key)).to_s.downcase.tr("-", "_").to_sym,
    bpm: resolve_bpm(harm_preset, harm_key, harm_sonic),
    feel: feel,
    timing: drum_preset[:timing] || cfg[:timing],
    style_family: style_family(drum_key, feel: feel),
    mashed: { harmony: harm_key, drums: drum_key }
  )
end

def slash_bass_enabled?(cfg)
  ENV["SLASH_BASS"] == "1" ||
    SLASH_BASS_PROFILES.include?(cfg[:progression].to_sym) ||
    cfg[:track].to_s.include?("slash")
end

def slash_bass_pads_for(pads, cfg)
  return nil if pads.empty?
  root = pads.first[:hz].min * 0.5
  generate_slash_progression(root_hz: root, length: pads.length, seed: cfg[:track].to_s.hash.abs)
end

def ghost_tier_for(bar, section)
  forced = ENV["GHOST_TIER"]&.to_sym
  return forced if forced && GHOST_TIERS.key?(forced)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    sect = @composition_session.section_at(bar)
    prof = @composition_session.profile_at(bar)
    case sect
    when :intro, :breakdown then :whisper
    when :hook, :solo then :accent
    else prof[:fill_rate].to_f > 0.4 ? :accent : :pocket
    end
  else
    case section
    when :intro, :breakdown then :whisper
    when :build then :accent
    else :pocket
    end
  end
end

def apply_ghost_tier_vel(vel, tier)
  (vel * GHOST_TIERS.fetch(tier, GHOST_TIERS[:pocket])[:mul]).clamp(0.03, 0.72).round(3)
end

def export_render_stems!(destination, drum_tmp, harmonic_tmp, events, duration, cfg, use_stem_harmony:)
  return unless ENV["STEM_EXPORT"] == "1" || ENV["KEEP_STEMS"] == "1"
  stem_dir = File.join(File.dirname(destination), "#{File.basename(destination, '.*')}_stems")
  FileUtils.mkdir_p(stem_dir)
  FileUtils.cp(drum_tmp, File.join(stem_dir, "drums.wav")) if File.exist?(drum_tmp)
  unless use_stem_harmony
    FileUtils.cp(harmonic_tmp, File.join(stem_dir, "harmonic.wav")) if File.exist?(harmonic_tmp)
    bass_tmp = File.join(stem_dir, ".bass_layer.wav")
    render_harmonic_wav(bass_tmp, [], [], events[:bass] || [], duration, cfg: cfg)
    FileUtils.cp(bass_tmp, File.join(stem_dir, "bass.wav")) if File.exist?(bass_tmp)
    FileUtils.rm_f(bass_tmp)
    if events[:melody]&.any?
      mel_tmp = File.join(stem_dir, ".melody_layer.wav")
      render_harmonic_wav(mel_tmp, [], [], [], duration, melody_events: events[:melody], cfg: cfg)
      FileUtils.cp(mel_tmp, File.join(stem_dir, "melody.wav")) if File.exist?(mel_tmp)
      FileUtils.rm_f(mel_tmp)
    end
  end
  FileUtils.cp(destination, File.join(stem_dir, "master#{File.extname(destination)}")) if File.exist?(destination)
  FileUtils.cp(DillaComposition::SESSION_PATH, File.join(stem_dir, "session.json")) if File.exist?(DillaComposition::SESSION_PATH)
  FileUtils.cp(DillaComposition::MOTIFS_PATH, File.join(stem_dir, "motifs.json")) if File.exist?(DillaComposition::MOTIFS_PATH)
  puts "stems: #{stem_dir}"
end

def apply_track_soul_profile!(track, force: false)
  key = track.to_s.downcase.tr("-", "_").to_sym
  [TRACK_SOUL_PAD_PROFILES[key], TRACK_SOUL_LEAD_PROFILES[key]].compact.each do |profile|
    profile.each do |env_key, value|
      next if !force && ENV[env_key] && !ENV[env_key].empty?
      # Never demote multi-layer stacks to single-voice presets mid-stream.
      if env_key == "PAD_VOICE" && ENV["PAD_VOICE"].to_s.start_with?("stack_")
        next
      end
      ENV[env_key] = value.to_s
    end
  end
end

def apply_dilla_style!(force: false)
  raw = ENV["RENDER_MODE"].to_s.downcase
  ENV["RENDER_MODE"] = "dilla" if raw.empty? || raw == "camel"
  ENV["RENDER_MODE"] = "dilla" if ENV["RENDER_MODE"].to_s.downcase == "camel"
  apply_render_mode!
  verb = force ? "force" : "fill"
  DILLA_STYLE_DEFAULTS.each do |key, value|
    next if !force && ENV[key] && !ENV[key].empty?
    ENV[key] = value.to_s
    record_config_provenance!(key, "DILLA_STYLE_DEFAULTS", verb)
  end
  track = ENV["TRACK"].to_s
  track = "get_dis_money" if track.empty?
  apply_track_soul_profile!(track, force: force)
  reassert_dilla_style_locks! if force
  reassert_pad_lead_locks!
  ensure_learned_engine_seeded!
  apply_learned_env_for_track!(track)
end

def apply_camel_profile!(force: false)
  apply_dilla_style!(force: force)
end

def pick_default_track!
  return if ENV["TRACK"] && !ENV["TRACK"].empty?
  if deep_render?
    pool = DillaLofiMachine::STREAM_ROTATION
    seed = Time.now.to_i + Process.pid + (@render_seed || 0)
    ENV["TRACK"] = pool[Random.new(seed).rand(pool.length)]
  else
    ENV["TRACK"] = DillaLofiMachine::DEFAULT_PROFILE.to_s
  end
end

def apply_best_defaults!
  return if ENV["DILLA_RAW"] == "1"
  apply_render_mode!
  soft_fill_env!(DILLA_BEST_DEFAULTS, label: "DILLA_BEST_DEFAULTS")
  soft_fill_env!(DILLA_DEEP_DEFAULTS, label: "DILLA_DEEP_DEFAULTS") if deep_render?
  pick_default_track!
end

def apply_stream_listenability_defaults!
  apply_best_defaults!
  soft_fill_env!(STREAM_EXTRA_DEFAULTS, label: "STREAM_EXTRA_DEFAULTS")
  if stream_deep?
    ENV["DILLA_DEEP"] = "1" if ENV["DILLA_DEEP"].to_s.empty?
    soft_fill_env!(DILLA_DEEP_DEFAULTS, label: "DILLA_DEEP_DEFAULTS")
  else
    fast = STREAM_FAST_DEFAULTS.dup
    if stream_iterate_enabled?
      STREAM_ITERATE_OVERRIDE_KEYS.each { |key| fast.delete(key) }
    end
    soft_fill_env!(fast, label: "STREAM_FAST_DEFAULTS")
  end
  if stream_iterate_enabled?
    soft_fill_iterate!(STREAM_ITERATE_TUNING, locked_keys: DILLA_STYLE_LOCK_KEYS)
  end
  if ENV.fetch("STREAM_SOUL", "1") != "0"
    soft_fill_env!(STREAM_SOUL_DEFAULTS, label: "STREAM_SOUL_DEFAULTS")
    ensure_learned_engine_seeded!
    apply_learned_env_for_track!(ENV["TRACK"]) if ENV["TRACK"] && !ENV["TRACK"].empty?
  end
  # Single style for stream: dilla (RENDER_MODE camel stays as alias).
  ENV["RENDER_MODE"] = "dilla" if ENV["RENDER_MODE"].to_s.empty? ||
                                  ENV["RENDER_MODE"].to_s.downcase == "camel"
  apply_dilla_style!(force: true)
  # Critical: apply_dilla_style(force) was wiping STREAM_ITERATE / RAP_VOCAL /
  # creative flags back to the conservative style table — re-force stream layer.
  force_env!(STREAM_CREATIVE_MAX, label: "STREAM_CREATIVE_MAX")
  force_env!(STREAM_ITERATE_TUNING, label: "STREAM_ITERATE_TUNING") if stream_iterate_enabled?
  ENV["PLAY_VOL"] = "1" if ENV["PLAY_VOL"].to_s.empty?
  ENV["DILLA_STREAMING"] = "1"
  record_config_provenance!("DILLA_STREAMING", "apply_stream_listenability_defaults!", "force")
end

def render_spectrum(path)
  {
    low: band_rms(path, highpass: 28, lowpass: 180),
    mid: band_rms(path, highpass: 180, lowpass: 3_500),
    high: band_rms(path, highpass: 3_500, lowpass: 16_000)
  }
end

# Objective mix meters for piping into MASTER council (not a parallel critique stack).
# Persona panel, multi-solution ideation, and cherry-pick:
#   MASTER /dilla crit [path]  or  /dilla-critique  or  /sound-critique
def mix_metrics(path)
  return nil unless path && File.file?(path)
  peak_db = -90.0
  rms_db = -90.0
  duration = 0.0
  begin
    out, err, = Open3.capture3("ffmpeg", "-hide_banner", "-nostats", "-i", path,
                               "-af", "volumedetect", "-f", "null", "-")
    blob = err.to_s + out.to_s
    peak_db = Regexp.last_match(1).to_f if blob =~ /max_volume:\s*([-\d.]+)/
    rms_db = Regexp.last_match(1).to_f if blob =~ /mean_volume:\s*([-\d.]+)/
    out2, = Open3.capture3("ffprobe", "-v", "error", "-show_entries", "format=duration",
                           "-of", "default=noprint_wrappers=1:nokey=1", path)
    duration = out2.to_s.strip.to_f
  rescue StandardError
    nil
  end
  crest = (peak_db > -80 && rms_db > -80) ? (10**((peak_db - rms_db) / 20.0)).round(3) : 0.0
  {
    peak_db: peak_db, rms_db: rms_db, crest: crest,
    duration_sec: duration.round(2),
    sub_db: band_rms(path, highpass: 40, lowpass: 100),
    pad_body_db: band_rms(path, highpass: 100, lowpass: 300),
    mids_db: band_rms(path, highpass: 300, lowpass: 1200),
    presence_db: band_rms(path, highpass: 1200, lowpass: 4000),
    air_db: band_rms(path, highpass: 4000, lowpass: 12_000)
  }
end

def crit_session_cli!(path = nil)
  path ||= File.join(OUTPUT_DIR, "demo.wav")
  path = File.join(ROOT, "demo.wav") unless File.file?(path)
  abort "crit: missing #{path} — render first, then perfect via MASTER" unless File.file?(path)
  DillaDmesg.boot!(cmd: "crit")
  DillaDmesg.read!(path)
  m = mix_metrics(path)
  DillaDmesg.metrics!(m)
  puts JSON.pretty_generate(m)
  dmesg("meters only — multi-persona cherry-pick via master /dilla crit", unit: "meter0", parent: "dilla0")
  dmesg("master: /dilla crit #{File.basename(path)} or /dilla-critique", unit: "meter0", parent: "dilla0")
  abort "crit: unusable levels" if m[:peak_db].to_f > -0.2 || (m[:rms_db] && m[:rms_db] < -40)
  dmesg("meters ok — run master council to perfect", unit: "meter0", parent: "dilla0")
end

def render_quality_acceptable?(path)
  return true unless quality_gate_enabled?
  return true unless File.file?(path)
  chords = DillaHarmony.last_progression_chords
  beauty = DillaHarmony.score_beauty(chords)
  spectrum = render_spectrum(path)
  harsh = DillaMaster.analyze_harshness(spectrum)
  sk = DillaMaster.sub_kick_balance(spectrum, beauty)
  min_beauty = if ENV["DILLA_STREAMING"] == "1"
                 STREAM_BEAUTY_MIN
               else
                 (ENV["RENDER_BEAUTY_MIN"] || "70").to_f
               end
  beauty_ok = beauty >= min_beauty && !harsh[:needs_notch]
  sub_ok = !(deep_render? && sk[:recommendation] == "boost_sub" && sk[:low_mid_delta].to_f < -9.0)
  ok = beauty_ok && sub_ok
  if ok && phone_preview_gate_enabled?
    phone_path = DillaMaster.apply_phone_preview!(path)
    phone_spec = render_spectrum(phone_path)
    phone = DillaMaster.phone_preview_acceptable?(phone_spec)
    unless phone[:ok]
      warn "phone preview gate: mid=#{phone[:mid_db]} dB, low-mid=#{phone[:low_mid_delta]} dB, " \
           "harsh=#{phone[:harshness]} — retrying"
      ok = false
    end
    FileUtils.rm_f(phone_path) if phone_path != path && phone_path.end_with?(".phone.wav")
  end
  unless ok
    unless beauty_ok
      warn "quality gate: beauty=#{beauty} (min #{min_beauty}), harsh=#{harsh[:harshness]} — retrying"
    end
    unless sub_ok
      warn "quality gate: sub=#{sk[:recommendation]} (low-mid #{sk[:low_mid_delta]} dB) — retrying"
    end
  end
  ok
end

def stream_render_acceptable?(path)
  render_quality_acceptable?(path)
end

def refine_deep_mix_env!(path)
  return unless File.file?(path)
  spectrum = render_spectrum(path)
  beauty = DillaHarmony.score_beauty(DillaHarmony.last_progression_chords)
  sk = DillaMaster.sub_kick_balance(spectrum, beauty)
  changed = false
  if sk[:recommendation] == "boost_sub"
    kg = [(ENV["KICK_GAIN"] || "0.34").to_f + 0.05, 0.48].min
    ENV["KICK_GAIN"] = kg.round(2).to_s
    changed = true
  elsif sk[:recommendation] == "reduce_sub"
    kg = [(ENV["KICK_GAIN"] || "0.34").to_f - 0.04, 0.12].max
    ENV["KICK_GAIN"] = kg.round(2).to_s
    changed = true
  end
  harm_w = (ENV["DEBUG_HARM_WEIGHT"] || "1.68").to_f
  if beauty < 72 && harm_w < 2.0
    ENV["DEBUG_HARM_WEIGHT"] = (harm_w + 0.12).round(2).to_s
    changed = true
  end
  changed
end

def log_render_meta(path)
  chords = DillaHarmony.last_progression_chords
  beauty = DillaHarmony.score_beauty(chords)
  patches = [@render_ep_patch&.dig(:id), @render_warm_patch&.dig(:id)].compact.join("/")
  leads = [@render_scale_lead_patch&.dig(:id), @render_lead_patch&.dig(:id)].compact.join("+")
  prog = chords&.map { |c| c[:name] }&.join(" → ")
  depth = deep_render? ? "deep" : "standard"
  puts "track=#{ENV['TRACK']} mode=#{depth} patches=#{patches || 'native'} pad_arp=#{pad_arp_mode} " \
       "leads=#{leads} beauty=#{beauty}"
  puts "progression: #{prog}" if prog
  puts "quality: ruby dilla.rb beauty #{path}" if File.file?(path)
end

def log_stream_render_meta(path)
  log_render_meta(path)
end

def deep_default_render!(dest, n_bars)
  ensure_external_assets_lazy!
  retries = [(ENV["RENDER_RETRIES"] || "2").to_i, 0].max
  listen_passes = [(ENV["LISTEN_PASSES"] || "0").to_i, 0].max
  (retries + 1).times do |try|
    pick_render_seed! if try.positive?
    render_dilla(dest, n_bars)
    break if render_quality_acceptable?(dest)
    warn "deep render retry #{try + 1}/#{retries + 1}"
  end
  listen_passes.times do |pass|
    break unless refine_deep_mix_env!(dest)
    warn "deep mix refine pass #{pass + 1}/#{listen_passes}"
    pick_render_seed!
    render_dilla(dest, n_bars)
  end
  log_render_meta(dest)
  dilla_quality(dest) if ENV["QUALITY_REPORT"] == "1" && File.file?(dest)
end

def default_render!(argv = ARGV)
  dest = if argv[0] && argv[0] =~ /\.(wav|mp3|flac|ogg|m4a|aiff?)\z/i
           argv.shift
         else
           DEFAULT_RENDER_OUTPUT
         end
  n_bars = argv[0]&.match?(/\A\d+\z/) ? argv.shift.to_i : nil
  FileUtils.mkdir_p(File.dirname(dest))
  if deep_render?
    deep_default_render!(dest, n_bars)
  else
    render_dilla(dest, n_bars)
  end
end

def stream_play_track!(bars_count)
  timeout = stream_track_timeout_sec
  if timeout
    Timeout.timeout(timeout) { play("dilla", bars_count) }
  else
    play("dilla", bars_count)
  end
end

# Non-stop chord/pad showcase: renders and plays each track once (full
# playback through real speakers, ffplay -autoexit), then moves on, forever.
# Ctrl-C to stop. No LLM/agent involved — plain local playback.
# Pad-first rotation (curated progressions that read as chord music).
# Stream only artist-verified song harmony (see ARTIST_VERIFIED_PROGRESSIONS).
DILLA_STREAM_PRIORITY = %w[
  get_dis_money time_donut fall_in_love climax untitled_how_does_it_feel
  maj7_minor_cycle alternating_minor7_pair syncopated_slash_ninth
].freeze

def stream_track_order
  lock = ENV["STREAM_TRACK"] || (ENV["STREAM_LOCK"] == "1" ? ENV["TRACK"] : nil)
  if lock && !lock.to_s.empty?
    key = lock.to_s.downcase.tr("-", "_").to_sym
    known = STREAM_TRACKS.include?(key) || DillaLofiMachine.harmony_profile?(key) ||
            TRACK_PRESETS.key?(key)
    return [key] if known
    dmesg_warn("stream unknown lock #{lock} — full rotation")
  end
  # Full progression pack: priority verified songs first, then shuffle the rest.
  all = STREAM_TRACKS.map(&:to_s).uniq
  priority = DILLA_STREAM_PRIORITY.select { |t| all.include?(t) }
  rest = (all - priority).shuffle
  start = rand([priority.length, 1].max)
  priority.rotate(start) + rest
end

# Per-track variety: rotate lead arp mode, lead/pad voice, force true arps + synth cycle.
def stream_rotate_voices_and_arps!(track_index)
  return if ENV["STREAM_ROTATE_LEAD"] == "0" && ENV["STREAM_ROTATE_SYNTH"] == "0"
  @stream_iterate_count = (@stream_iterate_count || 0)
  i = track_index + @stream_iterate_count
  if ENV.fetch("STREAM_ROTATE_LEAD", "1") != "0"
    ENV["LEAD_ARP"] = "1"
    ENV["LEAD_FORCE_ARP"] = "1"
    ENV["MELODIC_LEAD"] = "0"
    ENV["LEAD_ARP_MODE"] = STREAM_LEAD_ARP_ROTATION[i % STREAM_LEAD_ARP_ROTATION.length].to_s
    ENV["LEAD_VOICE"] = STREAM_LEAD_VOICE_ROTATION[i % STREAM_LEAD_VOICE_ROTATION.length]
    ENV["SCALE_LEAD"] = "1"
    ENV["HARMONY_LEAD"] = "1"
    ENV["CREATIVE_LEAD"] = (i % 2).zero? ? "1" : "0"
    ENV["EXPERIMENTAL_LEADS"] = "1"
    ENV["LEAD_MORPH"] = "1"
    ENV["STREAM_LEAD_MIDI_RICH"] = "1"
    # Louder lead stems so arps cut through pads.
    ENV["HARMONIC_LEAD_ARP_WEIGHT"] = format("%.2f", 1.65 + (i % 5) * 0.05)
    ENV["HARMONIC_LEAD_ARP_VOLUME"] = "1.95"
    ENV["HARMONIC_SCALE_LEAD_WEIGHT"] = "1.25"
    ENV["HARMONIC_SCALE_LEAD_VOLUME"] = "1.55"
  end
  if ENV.fetch("STREAM_ROTATE_SYNTH", "1") != "0"
    ENV["SYNTH_CYCLE"] = "1"
    ENV["SYNTH_MORPH"] = "1"
    ENV["PAD_TEXTURE"] = "1"
    # Mostly held pads; occasional pad figure for variety.
    ENV["PAD_ARP_MODE"] = (i % 5).zero? ? "figure" : "held"
    ENV["PAD_VOICE"] = STREAM_PAD_VOICE_ROTATION[i % STREAM_PAD_VOICE_ROTATION.length]
    # Cycle analog color + sonitex when wild mode on.
    if ENV["STREAM_ANALOG_WILD"] == "1"
      chains = %w[broadcast acetate cassette vinyl_hot summing_phasy lo_fi sp1200]
      ENV["ANALOG_CHAIN"] = chains[i % chains.length]
      soni = %w[donuts_soul donuts_warm vinyl_lab sp1200_crunch]
      ENV["SONITEX"] = soni[i % soni.length]
      ENV["SONITEX_PRESET"] = ENV["SONITEX"]
    end
  end
  # Clear cached patches so pick_synth_patches! re-rolls for this track.
  @render_ep_patch = @render_warm_patch = @render_lead_patch = nil
  @render_scale_lead_patch = @render_texture_patch = @render_native_patch = nil
  @render_arp_style = @render_scale_arp_style = nil
  pick_render_seed!
end

# Integrated loudness match so every stream track (and vocals) lands at the same level.
def normalize_track_loudness!(path, lufs: nil)
  return path unless path && File.file?(path)
  return path if ENV["DEBUG_NO_LOUDNORM"] == "1"
  lufs ||= (ENV["STREAM_LUFS"] || ENV["MASTER_LUFS"] || "-16.5").to_f
  tp = (ENV["STREAM_TRUE_PEAK"] || "-1.5").to_f
  lra = (ENV["STREAM_LRA"] || "11").to_f
  ext = File.extname(path)
  tmp = "#{path}.norm#{ext}"
  begin
    sh! "ffmpeg", "-y", "-i", path,
        "-af", "loudnorm=I=#{lufs}:TP=#{tp}:LRA=#{lra},alimiter=limit=0.95:level_out=0.96",
        "-ar", SAMPLE_RATE.to_s, "-ac", "2", *codec_for(tmp), tmp
    FileUtils.mv(tmp, path) if File.file?(tmp)
  rescue StandardError => e
    warn "normalize_track_loudness: #{e.message}"
    FileUtils.rm_f(tmp)
  end
  path
end

def stream(bars_count = STREAM_BARS_COUNT)
  require_playback_tool!
  # Non-stop outer supervisor: any exit except Ctrl-C restarts stream (agent + interactive).
  if ENV.fetch("STREAM_CONTINUOUS", "1") != "0" && ENV["DILLA_STREAM_SUPERVISOR"] != "1"
    stream_log = File.join(ROOT, "stream.log")
    env_pass = %w[
      RENDER_MODE STREAM_SOUL SPEAK RAP_VOCAL STREAM_DEMO STREAM_TRACK STREAM_LOCK
      FLYLO_TOP_MIX FLYLO_SUB_MIX FLYLO_MERGE_BOOST FLYLO_OVERLAY_GAIN
      DRUM_BUS_VOL DRUM_BUS_GAIN DRUM_MIX_WEIGHT DRUM_AIR_DB DRUM_PRESENCE_DB
      KICK_GAIN FLYLO_KICK_GAIN POCKET_KICKS FLYLO_DRUMS_ONLY
    ].filter_map { |k| ENV[k] && !ENV[k].empty? ? "#{k}=#{Shellwords.escape(ENV[k])}" : nil }
                 .join(" ")
    cmd = "cd #{Shellwords.escape(ROOT)} && while true; do " \
          "DILLA_STREAM_LAUNCHED=1 DILLA_STREAM_SUPERVISOR=1 #{env_pass} " \
          "ruby #{Shellwords.escape(__FILE__)} stream #{bars_count.to_i} 2>&1 | tee -a #{Shellwords.escape(stream_log)}; " \
          "c=$?; [ $c -eq 130 ] && break; " \
          "echo \"$(date -u +%Y-%m-%dT%H:%M:%SZ) stream exited $c — restart in 2s\" | tee -a #{Shellwords.escape(stream_log)}; " \
          "sleep 2; done"
    if darwin? && ENV["DILLA_STREAM_LAUNCHED"] != "1" &&
       (ENV["GROK_AGENT"] == "1" || !$stdout.tty? || ENV["DILLA_FORCE_TERMINAL"] == "1")
      dmesg("agent shell — open terminal for continuous stream", unit: "stream0", parent: "dilla0")
      DillaDmesg.emit("exec0", "osascript terminal stream", parent: "dilla0") if DillaDmesg.verbose?
      system("osascript", "-e", %(tell application "Terminal" to do script "#{cmd.gsub('"', '\\"')}"))
      system("osascript", "-e", 'tell application "Terminal" to activate')
      return
    end
    # In-process continuous loop (agent already has a shell / non-Terminal path).
    exec("zsh", "-c", cmd)
  end
  $stdout.sync = true
  $stderr.sync = true
  acquire_stream_lock!
  prev_track = ENV["TRACK"]
  user_pad_locked = (ENV["PAD_VOICE"] && !ENV["PAD_VOICE"].empty?) ||
                    (ENV["PAD_ARP_MODE"] && !ENV["PAD_ARP_MODE"].empty?)
  user_lead_locked = (ENV["LEAD_VOICE"] && !ENV["LEAD_VOICE"].empty?) ||
                     (ENV["LEAD_ARP_MODE"] && !ENV["LEAD_ARP_MODE"].empty?)
  @stream_user_pad_locked = user_pad_locked
  @stream_user_lead_locked = user_lead_locked
  apply_stream_listenability_defaults!
  # Random rotation by default; STREAM_TRACK= or TRACK+STREAM_LOCK=1 pins one profile.
  order = stream_track_order
  # Ruby can't safely reload this file in-process (the CLI dispatch at the
  # bottom runs unconditionally, so a mid-run `load` would re-trigger it —
  # risk of recursion). exec-ing a fresh process instead is safe: it fully
  # replaces this process with a new one that reads the file from disk
  # again, so edits since the last track take effect automatically between
  # tracks without needing a manual kill+relaunch.
  self_mtime = File.mtime(__FILE__)
  mode = if stream_deep?
           "deep+QC"
         elsif stream_iterate_enabled?
           "fast+iterate"
         else
           "fast"
         end
  DillaDmesg.boot!(mode: ENV["RENDER_MODE"] || "dilla", cmd: "stream")
  DillaDmesg.stream!(mode: mode, bars: bars_count, order_n: order.length)
  dmesg("cycle #{order.first(8).join(',')}#{order.length > 8 ? '…' : ''} (ctrl-c stop)", unit: "stream0", parent: "dilla0")
  dmesg("iterate log #{File.basename(STREAM_ITERATE_LOG.to_s)}", unit: "stream0", parent: "dilla0") if stream_iterate_enabled?
  loop do
    order.each do |t|
      if File.mtime(__FILE__) > self_mtime
        dmesg("dilla.rb mtime changed — exec restart", unit: "stream0", parent: "dilla0")
        # Keep supervisor/lock flags so we do not spawn a nested while-true
        # loop (or a second Terminal tab) on every mid-stream code reload.
        ENV["DILLA_STREAM_SUPERVISOR"] = "1"
        ENV["DILLA_STREAM_LAUNCHED"] = "1"
        exec(Gem.ruby, __FILE__, "stream", bars_count.to_s)
      end
      track = t.to_s
      # Soul profile first, then rotate lead/synth (overrides locked soul lead).
      apply_track_soul_profile!(track, force: !user_pad_locked && !user_lead_locked)
      stream_rotate_voices_and_arps!(order.index(t) || 0) unless user_lead_locked
      reassert_pad_lead_locks! unless user_pad_locked
      # Keep progression aligned with the track id (style lock would pin TRACK forever).
      ENV["TRACK"] = track
      ENV["PROGRESSION"] = track unless user_pad_locked && ENV["PROGRESSION"] && !ENV["PROGRESSION"].empty?
      reassert_camel_beauty_locks! if camel_mode? && ENV["STREAM_LOCK"] == "1"
      if radio_bergen_stream_enabled? && rand < 0.38 && (rb = pick_radio_bergen_stream_track!)
        track = rb
        apply_track_soul_profile!(track, force: !user_pad_locked && !user_lead_locked)
        stream_rotate_voices_and_arps!(order.index(t) || 0) unless user_lead_locked
        reassert_pad_lead_locks! unless user_pad_locked
        ENV["TRACK"] = track
        ENV["PROGRESSION"] = track
        reassert_camel_beauty_locks! if camel_mode? && ENV["STREAM_LOCK"] == "1"
        stream_track_banner("← playlist.brgen.no (rotation #{t})")
      else
        stream_track_banner
      end
      begin
        stream_play_track!(bars_count)
      rescue SystemExit
        raise
      rescue Timeout::Error
        warn "stream: #{ENV['TRACK'] || track} timed out after #{stream_track_timeout_sec}s — skipping"
        sleep 1.0
      rescue Exception => e
        warn "stream: #{ENV['TRACK'] || track} failed (#{e.class}) — #{e.message}"
        sleep 1.0
      end
      gap = (ENV["STREAM_GAP"] || "0.55").to_f
      xfade = (ENV["STREAM_CROSSFADE"] || "0.12").to_f
      # Soft silence between tracks (crossfade is intentional gap, not sample morph).
      sleep DillaSeeds.drift_sleep([gap + xfade, 0.05].max) if gap.positive? || xfade.positive?
    end
  end
ensure
  prev_track ? ENV["TRACK"] = prev_track : ENV.delete("TRACK")
end

# Instantly play a modulating bass tone — good for local audio system check.
def bass(root_hz = 55.0)
  require_tools! "ffplay"
  # Warbling sub bass: fundamental + slow pitch LFO + low harmonic content.
  # Models J Dilla's low-end: not a clean sine, has movement and weight.
  lfo_hz   = 0.18
  lfo_amt  = root_hz * 0.04
  expr_l   = "0.45*sin(2*PI*(#{root_hz}+#{lfo_amt}*sin(2*PI*#{lfo_hz}*t))*t)" \
             "+0.08*sin(2*PI*#{(root_hz * 2).round(2)}*t)" \
             "+0.03*sin(2*PI*#{(root_hz * 3).round(2)}*t)"
  filter = "aeval=exprs='#{expr_l}:#{expr_l}',equalizer=f=80:width_type=o:width=2:g=4,lowpass=f=200"
  puts "playing bass #{root_hz}Hz (Ctrl-C to stop)"
  exec "ffplay", "-f", "lavfi", "-i", "aevalsrc=0", "-nodisp", "-af", filter
rescue SystemCallError => e
  abort "ffplay failed: #{e.message}"
end

# --- J Dilla Time beat engine (MPC3000 cyclic microtiming) ---

COMPOSITION_SECTION_KIND = {
  intro: :intro, verse: :main, hook: :build, bridge: :main,
  solo: :build, breakdown: :breakdown, outro: :outro
}.freeze

def composition_enabled?
  ENV["COMPOSITION"] != "0"
end

def composition_session!(n_bars: nil, track: nil, force_new: false)
  if force_new
    remove_instance_variable(:@composition_session) if instance_variable_defined?(:@composition_session)
  end
  return @composition_session if !force_new && instance_variable_defined?(:@composition_session) && @composition_session && !n_bars
  track ||= (ENV["TRACK"] || "timeless").to_s
  n_bars ||= bars
  performer = (ENV["PERFORMER"] || "yancey").to_s.downcase.tr("-", "_").to_sym
  groove = (ENV["GROOVE_DNA"] || "donuts").to_s.downcase.tr("-", "_").to_sym
  apply_learned_env_for_track!(track.to_s) if track
  @composition_session = if composition_enabled? && !force_new && File.exist?(DillaComposition::SESSION_PATH)
                           DillaComposition::Session.load!(default_track: track, n_bars: n_bars)
                         else
                           DillaComposition::Session.new(track: track, performer: performer,
                                                         groove_dna: groove, n_bars: n_bars)
                         end
  composition_feed_from_learn!(@composition_session)
  @composition_session
end

def reset_composition_session!
  remove_instance_variable(:@composition_session) if instance_variable_defined?(:@composition_session)
end

def dilla_timing_ms(role, bar_index, step_index, timing = nil, beat_p = nil)
  base = cyclic_timing_offset(role, bar_index, step_index, timing, beat_p, cycle: 4)
  return base unless composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
  perf = @composition_session.performer_profile
  groove = @composition_session.groove_profile
  extra = case role
          when :kick_anchor, :kick_sync then perf[:kick_lag_ms]
          when :snare then perf[:snare_early_ms]
          when :hat_down, :hat_up then perf[:hat_late_ms]
          when :bass then (perf[:kick_lag_ms] * 1.6).round(1)
          when :ghost then (perf[:ghost_boost] * 4 - 4).round(1)
          else 0
          end
  dna = if %i[kick_anchor kick_sync].include?(role)
          groove[:kick_offset_ms][step_index % groove[:kick_offset_ms].length]
        elsif %i[hat_down hat_up].include?(role)
          groove[:hat_offset_ms][step_index % groove[:hat_offset_ms].length]
        else
          0
        end
  (base + extra + dna).round(3)
end

def time_of_day_swing_offset
  hour = Time.now.hour
  # Peaks around 2-4am (loosest/latest feel), tightest around 2pm.
  distance_from_3am = [((hour - 3) % 24), (24 - ((hour - 3) % 24))].min
  (4.0 - distance_from_3am * (4.0 / 12.0)).round(1)
end

def dilla_resolve_config
  cfg = enhanced_resolve_config
  cfg = apply_profile_mash!(cfg)
  cfg = apply_form_to_cfg!(cfg)
  prog_override = ENV["PROGRESSION"]
  if prog_override
    cfg = cfg.merge(progression: prog_override.to_s.downcase.tr("-", "_").to_sym)
  end
  cfg
end

def dilla_chord_index(bar, pad_chords, chord_bars:, phrase_bars: nil, chord_bar_lens: nil)
  return 0 if pad_chords.nil? || pad_chords.empty?
  if chord_bar_lens&.any?
    cum = 0
    chord_bar_lens.each_with_index do |len, idx|
      cum += [len, 1].max
      return idx % pad_chords.length if bar < cum
    end
    return (pad_chords.length - 1) % pad_chords.length
  end
  slot = bar / [chord_bars, 1].max
  if la_beat_progression_enabled? || ENV.fetch("LINEAR_CHORD_INDEX", "0") != "0"
    return slot % pad_chords.length
  end
  if phrase_bars
    slots_per_phrase = [phrase_bars / [chord_bars, 1].max, 1].max
    slot % [slots_per_phrase, pad_chords.length].min
  else
    slot % pad_chords.length
  end
end

def dilla_swing_offset(step_index, step_p, swing, quintuplet: false, bar: 0, bpm: 90)
  return 0.0 if swing.to_f <= 0.0 || step_index.even?
  amount = swing.clamp(0.0, 100.0) / 100.0
  unless quintuplet
    base = (step_p * amount * 0.5).round(6)
    return base + DillaGroove.swing_jitter_ms(bpm, step_index, bar)
  end
  # Real Dilla technique (Charnas/Hein analysis): the beat divides into 5
  # equal parts, not the standard 4 (16ths) or 6 (triplets) — the "and"
  # lands at the 3rd of 5 divisions, a 3:2 ratio rather than 2:1. That's a
  # different rhythmic subdivision, not just a different swing percentage.
  beat_p = step_p * 4.0
  quintuplet_pos = beat_p * 3.0 / 5.0
  straight_pos = step_p * 2.0
  base = ((quintuplet_pos - straight_pos) * amount).round(6)
  base + DillaGroove.swing_jitter_ms(bpm, step_index, bar)
end

def dilla_velocity(base, bar_index, step_index, spread: 0.10)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    spread = @composition_session.performer_profile[:velocity_spread]
    spread += (ENV["VELOCITY_SPREAD_NUDGE"] || "0").to_f
    groove = @composition_session.groove_profile
    curve = groove[:velocity_curve]
    base *= curve[step_index % curve.length] if curve
  end
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym
  spread += DillaLofiMachine.humanize_ticks_for(track) * 0.012 if DillaLofiMachine.harmony_profile?(track)
  seed = (bar_index * 1_009) + (step_index * 313) + (base * 10_000).to_i
  rng  = Random.new(seed)
  gaussian = Math.sqrt(-2.0 * Math.log([rng.rand, 1e-9].max)) * Math.cos(2.0 * Math::PI * rng.rand)
  [[base * (1.0 + gaussian * spread), 0.03].max, 1.0].min.round(3)
end

GENERATED_STYLES = %i[
  functional planing chromatic_mediant polytonal negative_harmony neapolitan
  coltrane backdoor slash modal_interchange
].freeze

def resolve_pad_chord_symbol(n)
  PAD_CHORD_LOOKUP[n] || MODAL_MINOR_CHORDS.find { |c| c[:name] == n } ||
    begin
      DillaLofiMachine.chord_from_symbol(n)
    rescue StandardError
      nil
    end
end

def curated_progression_pads(key)
  sym = key&.to_sym
  return nil unless sym
  if artist_verified_only? && !ARTIST_VERIFIED_PROGRESSIONS.key?(sym)
    return nil
  end
  names = artist_verified_chords(sym) || CHORD_PROGRESSIONS[sym]
  return nil unless names.is_a?(Array) && names.length >= 2
  pads = names.filter_map { |n| resolve_pad_chord_symbol(n) }
  pads.length >= 2 ? pads : nil
end

# Sparse boom-bap base. Bar-to-bar phrase rotation is DillaGroove.pocket_* when
# POCKET_DNA=1. Keep this simple — dense grids are why the kit sounded wrong.
FLYLO_CAMEL_SOURCE_URL = "https://www.youtube.com/watch?v=t6SXXx1Fu_4".freeze
FLYLO_CAMEL_DRUM_GRID = {
  "bpm" => 86,
  "swing" => 60,
  "source" => "pocket_dna_simple",
  "source_url" => FLYLO_CAMEL_SOURCE_URL,
  "flylo_kicks" => [0, 6, 10],
  "flylo_snares" => [4, 12],
  "flylo_ghost_snares" => [7],
  "flylo_hats" => [0, 2, 4, 6, 8, 10, 12, 14],
  "flylo_hat_ghosts" => [],
  "flylo_perc" => [],
  "flylo_claps" => [4, 12]
}.freeze
CAMEL_PROGRESSION_SYMS = %w[Dm9 Cm11nc AbMaj13s11 Gm7 Eb7 A7nc Dmaj9nc DMaj7overG].freeze

BUILTIN_LEARNED_ENGINE = {
  "progressions" => {
    "chromatic_mediant_drift" => CAMEL_PROGRESSION_SYMS,
    "quartal_west_coast" => CAMEL_PROGRESSION_SYMS,
    "flylo_camel" => CAMEL_PROGRESSION_SYMS,
    "camel_bridge" => CAMEL_BRIDGE_SYMS,
    "camel_functional" => CAMEL_FUNCTIONAL_SYMS
  },
  "drum_grids" => {
    "chromatic_mediant_drift" => FLYLO_CAMEL_DRUM_GRID,
    "quartal_west_coast" => FLYLO_CAMEL_DRUM_GRID,
    "flylo_camel" => FLYLO_CAMEL_DRUM_GRID
  },
  "calibrations" => {},
  "track_aliases" => {
    "flylo_camel" => "chromatic_mediant_drift",
    "quartal_west_coast" => "chromatic_mediant_drift"
  },
  "top_track" => nil,
  "promoted_at" => nil
}.freeze

def deep_merge_learned_engine!(base, overlay)
  overlay.each do |key, val|
    if val.is_a?(Hash) && base[key].is_a?(Hash)
      val.each { |k, v| base[key][k] = v }
    elsif !base.key?(key)
      base[key] = val
    else
      base[key] = val unless val.nil?
    end
  end
  base
end

def load_learned_engine(refresh: false)
  remove_instance_variable(:@learned_engine_cache) if refresh && instance_variable_defined?(:@learned_engine_cache)
  return @learned_engine_cache if instance_variable_defined?(:@learned_engine_cache) && @learned_engine_cache
  base = JSON.parse(JSON.generate(BUILTIN_LEARNED_ENGINE))
  if File.file?(DillaSourceLearn::LEARNED_ENGINE_PATH)
    file_data = JSON.parse(File.read(DillaSourceLearn::LEARNED_ENGINE_PATH))
    deep_merge_learned_engine!(base, file_data)
  end
  @learned_engine_cache = base
rescue StandardError
  @learned_engine_cache = JSON.parse(JSON.generate(BUILTIN_LEARNED_ENGINE))
end

def ensure_learned_engine_seeded!
  return if File.file?(DillaSourceLearn::LEARNED_ENGINE_PATH)
  DillaSourceLearn.ensure_dir!
  save_learned_engine!(JSON.parse(JSON.generate(load_learned_engine)))
end

def save_learned_engine!(data)
  DillaSourceLearn.ensure_dir!
  data["promoted_at"] = Time.now.utc.iso8601
  File.write(DillaSourceLearn::LEARNED_ENGINE_PATH, JSON.pretty_generate(data) + "\n")
  @learned_engine_cache = data
  data
end

def learned_chord_pad(sym)
  PAD_CHORD_LOOKUP[sym] || MODAL_MINOR_CHORDS.find { |c| c[:name] == sym } ||
    (DillaLofiMachine.chord_from_symbol(sym) rescue nil)
end

def learned_progression_pads(key)
  syms = load_learned_engine.dig("progressions", key.to_s)
  return nil unless syms.is_a?(Array) && syms.length >= 2
  syms.filter_map { |n| learned_chord_pad(n) }
end

def learned_drum_steps(role)
  track = (ENV["TRACK"] || "").to_s
  eng = load_learned_engine
  grid = eng.dig("drum_grids", track) || eng.dig("drum_grids", eng.dig("track_aliases", track))
  return nil unless grid.is_a?(Hash)
  case role
  when :kicks then Array(grid["kicks"] || grid[:kicks])
  when :snares then Array(grid["snares"] || grid[:snares])
  when :hats then Array(grid["hats"] || grid[:hats])
  end
end

def apply_learned_env_for_track!(track)
  return unless track && !track.to_s.empty?
  eng = load_learned_engine
  t = track.to_s
  alias_key = eng.dig("track_aliases", t)
  # Never remap a curated catalog TRACK onto a learned promo progression.
  # Opt in with LEARNED_PROGRESSION=1 when you want that behavior.
  allow_learned_prog = ENV.fetch("LEARNED_PROGRESSION", "0") != "0"
  has_catalog = CHORD_PROGRESSIONS.key?(t.to_sym) ||
                DillaLofiMachine.harmony_profile?(t.to_sym) ||
                CHORD_PROGRESSIONS.key?(ENV["PROGRESSION"].to_s.downcase.tr("-", "_").to_sym)
  if allow_learned_prog && !has_catalog
    prog_keys = [alias_key, t, eng["top_track"]].compact.uniq
    prog_keys.each do |pk|
      next unless eng.dig("progressions", pk.to_s)&.length.to_i >= 2
      ENV["PROGRESSION"] = pk.to_s if ENV["PROGRESSION"].nil? || ENV["PROGRESSION"].empty?
      break
    end
  end
  grid = eng.dig("drum_grids", t) || (alias_key && eng.dig("drum_grids", alias_key))
  if grid.is_a?(Hash)
    ENV["BPM"] = grid["bpm"].to_s if grid["bpm"] && (ENV["BPM"].nil? || ENV["BPM"].empty?)
  end
  cal = eng.dig("calibrations", "global")
  if cal.is_a?(Hash)
    ENV["SWING"] = cal["swing"].to_s if cal["swing"] && (ENV["SWING"].nil? || ENV["SWING"].empty?)
    ENV["BPM"] = cal["bpm"].to_s if cal["bpm"] && (ENV["BPM"].nil? || ENV["BPM"].empty?)
  end
end

def learn_catalog_top_hint
  eng = load_learned_engine
  if eng["top_track"]
    return { track: eng["top_track"], voicing: :kenny_barron, performer: "yancey", groove_dna: "donuts" }
  end
  cat = DillaSourceLearn.load_playlist_catalog
  tally = Hash.new(0)
  Array(cat["tracks"]).each do |row|
    eh = row["engine_hints"]
    cd = row["copyable_dna"]
    hint = (eh.is_a?(Hash) ? (eh["track"] || eh[:track]) : nil) ||
           (cd.is_a?(Hash) && cd["engine"].is_a?(Hash) ? (cd["engine"]["track"] || cd["engine"][:track]) : nil)
    tally[hint.to_s] += 1 if hint && !hint.to_s.empty?
  end
  top = tally.max_by { |_, c| c }&.first
  top ? { track: top.to_sym, performer: "yancey", groove_dna: "donuts" } : nil
end

def playlist_row_key(row)
  id = row[:youtube_id].to_s.strip
  id.empty? ? RadioBergenStudy.slug(row[:artist], row[:title]) : id
end

def learn_promote!(min_chords: 4)
  DillaSourceLearn.ensure_dir!
  catalog = DillaSourceLearn.load_playlist_catalog
  eng = load_learned_engine(refresh: true)
  promoted = 0
  Array(catalog["tracks"]).each do |raw|
    t = raw.transform_keys(&:to_s)
    next if t["id"] == "test_slug"
    dna = t["copyable_dna"] || {}
    harm = (dna["harmony"].is_a?(Hash) ? dna["harmony"]["progression"] : nil) || t["progression_symbols"]
    harm = Array(harm).map(&:to_s).reject(&:empty?)
    next unless harm.length >= min_chords
    slug = t["id"].to_s
    prog_key = "learned_#{slug}"
    eng["progressions"][prog_key] = harm
    eh = t["engine_hints"]
    engine_track = (eh.is_a?(Hash) ? (eh["track"] || eh[:track]) : nil) ||
                   (dna["engine"].is_a?(Hash) ? (dna["engine"]["track"] || dna["engine"][:track]) : nil) || slug
    eng["track_aliases"][engine_track.to_s] = prog_key
    eng["track_aliases"][slug] = prog_key
    drums = dna["drums"]
    if drums.is_a?(Hash) && (drums["kicks"] || drums["snares"])
      eng["drum_grids"][engine_track.to_s] = drums
      eng["drum_grids"][slug] = drums
    end
    promoted += 1
  end
  eng["top_track"] = learn_catalog_top_hint&.dig(:track)&.to_s || eng["top_track"]
  save_learned_engine!(eng)
  warn "learn-promote: #{promoted} progression(s) → #{DillaSourceLearn::LEARNED_ENGINE_PATH}" unless ENV["DILLA_QUIET"] == "1"
  { promoted: promoted, path: DillaSourceLearn::LEARNED_ENGINE_PATH }
end

def learn_calibrate!(audio_root: nil)
  data = RadioBergenStudy.dossiers!(audio_root: audio_root)
  eng = load_learned_engine(refresh: true)
  bpms = []
  swings = Hash.new(0)
  Array(data[:tracks]).each do |row|
    measured = row[:analysis]
    ref = row[:production_dossier]
    next unless measured&.dig(:measured)
    id = row[:id].to_s
    eng["calibrations"][id] = {
      bpm_measured: measured[:bpm_estimate],
      bpm_curated: ref&.dig(:bpm),
      swing_hint: measured.dig(:dynamics, :swing_hint)
    }.compact
    bpms << measured[:bpm_estimate] if measured[:bpm_estimate]
    sh = measured.dig(:dynamics, :swing_hint)
    swings[sh] += 1 if sh
  end
  if bpms.any?
    eng["calibrations"]["global"] = {
      "bpm" => (bpms.sum / bpms.length).round,
      "swing" => (DillaLofiMachine::DRUM_PRESETS[:dilla_slight][:swing] + (swings["laid_back"] || 0) * 2 -
                  (swings["pushed"] || 0)).clamp(52, 62)
    }
  end
  save_learned_engine!(eng)
  puts "learn-calibrate: #{eng['calibrations'].length} entries (global bpm=#{eng.dig('calibrations', 'global', 'bpm')})"
  eng
end

def learn_diff_dossiers!(audio_root: nil)
  dossiers = RadioBergenStudy.dossiers!(audio_root: audio_root)
  catalog = DillaSourceLearn.load_playlist_catalog
  cat_by_id = Array(catalog["tracks"]).to_h { |t| [t["id"], t] }
  diffs = []
  Array(dossiers[:tracks]).each do |row|
    id = row[:id].to_s
    ref = row[:production_dossier]
    measured = row[:analysis]
    learned = cat_by_id[id]
    entry = {
      id: id, artist: row[:artist], title: row[:title],
      curated_bpm: ref&.dig(:bpm), measured_bpm: measured&.dig(:bpm_estimate),
      curated_harmony: ref&.dig(:harmony), curated_drums: ref&.dig(:drums),
      measured_swing: measured&.dig(:dynamics, :swing_hint),
      learned_progression: (lp = learned&.[]("copyable_dna")) && lp["harmony"].is_a?(Hash) ? lp["harmony"]["progression"] : nil,
      learned_drums: (lp = learned&.[]("copyable_dna")) ? lp["drums"] : nil,
      calibration_notes: row[:calibration_notes]
    }
    if ref && measured&.dig(:bpm_estimate) && ref[:bpm]
      entry[:bpm_delta] = (measured[:bpm_estimate] - ref[:bpm]).round(1)
    end
    diffs << entry
  end
  payload = { generated_at: Time.now.utc.iso8601, tracks: diffs }
  DillaSourceLearn.ensure_dir!
  File.write(DillaSourceLearn::DOSSIER_DIFF_PATH, JSON.pretty_generate(payload) + "\n")
  puts "learn-diff: #{diffs.length} tracks → #{DillaSourceLearn::DOSSIER_DIFF_PATH}"
  payload
end

def composition_feed_from_learn!(sess)
  return unless sess
  apply_learned_env_for_track!(sess.track.to_s)
  eng = load_learned_engine
  prog_key = eng.dig("track_aliases", sess.track.to_s) || sess.track.to_s
  syms = eng.dig("progressions", prog_key)
  return unless syms.is_a?(Array) && syms.length >= 2
  sess.instance_variable_set(:@learned_progression, syms)
end

def safe_producer_progression(track)
  DillaLofiMachine.progression_for(track)
rescue StandardError => e
  warn "progression_for(#{track}): #{e.message}"
  nil
end

def dilla_progression(mode = :maj7_minor_cycle)
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s.downcase.tr("-", "_").to_sym
  mode_sym = mode.to_sym
  prog_env = ENV["PROGRESSION"].to_s.downcase.tr("-", "_")
  prog_sym = prog_env.empty? ? nil : prog_env.to_sym
  # Catalog first. Learned aliases were collapsing every TRACK into a truncated
  # 6-chord promo loop (Dbmaj9…Abmaj9low) — theory and sound both suffered.
  prefer_learned = ENV.fetch("LEARNED_PROGRESSION", "0") != "0"
  catalog_keys = [prog_sym, mode_sym, track].compact.uniq
  unless prefer_learned
    catalog_keys.each do |key|
      pads = curated_progression_pads(key)
      return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
      pads = safe_producer_progression(key)
      return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
    end
  end
  eng = load_learned_engine
  learned_keys = [eng.dig("track_aliases", track.to_s), track.to_s, mode_sym.to_s, prog_env].compact.uniq
  learned_keys.each do |key|
    next if key.to_s.empty?
    pads = learned_progression_pads(key)
    return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
  end
  if prefer_learned
    catalog_keys.each do |key|
      pads = curated_progression_pads(key)
      return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
      pads = safe_producer_progression(key)
      return voice_led_pad_progression(pads) if pads&.length.to_i >= 2
    end
  end
  if (producer_pads = safe_producer_progression(track))&.length.to_i >= 2
    return voice_led_pad_progression(producer_pads)
  end
  sonic = sonic_profile_for(track)
  engine_pads = progression_from_engine(sonic, mode)
  return voice_led_pad_progression(engine_pads) if engine_pads&.any?

  if GENERATED_STYLES.include?(mode.to_sym) || mode.to_sym == :generated
    root_hz = (ENV["GEN_ROOT"] || 130.81).to_f
    gen_mode = (ENV["GEN_MODE"] || "minor").to_sym
    length = (ENV["GEN_LENGTH"] || 8).to_i
    seed = ENV["GEN_SEED"]&.to_i
    style = mode.to_sym == :generated ? (ENV["GEN_STYLE"] || "functional").to_sym : mode.to_sym
    style = :functional if DillaHarmony.block_generated?(track, style)
    routed = route_generated_style(style, root_hz:, mode: gen_mode, length:, seed:)
    return voice_led_pad_progression(routed) if routed
    case style
    when :planing then return voice_led_pad_progression(generate_planing_progression(root_hz:, mode: gen_mode, length:, seed:))
    when :chromatic_mediant then return voice_led_pad_progression(generate_chromatic_mediant_progression(root_hz:, length:, seed:))
    when :polytonal then return voice_led_pad_progression(generate_polytonal_progression(root_hz:, mode: gen_mode, length:, seed:))
    when :negative_harmony then return voice_led_pad_progression(generate_negative_harmony_progression(root_hz:, mode: gen_mode, length:, seed:))
    when :neapolitan then return voice_led_pad_progression(generate_neapolitan_progression(root_hz:, length:, seed:))
    else return voice_led_pad_progression(generate_progression(root_hz:, mode: gen_mode, length:, seed:))
    end
  end
  names = CHORD_PROGRESSIONS.fetch(mode.to_sym, CHORD_PROGRESSIONS.fetch(:soul))
  voice_led_pad_progression(names.filter_map { |n| resolve_pad_chord_symbol(n) })
end

# Closest-tone voice leading + close jazz voicing so pads don't thrash register.
def voice_led_pad_progression(pads)
  return pads if pads.nil? || pads.length < 2
  return pads if ENV.fetch("VOICE_LEAD_PADS", "1") == "0"
  style = (ENV["VOICING"] || "rootless").to_s.downcase.tr("-", "_").to_sym
  style = :rootless unless DillaHarmony::VOICING_STYLES.include?(style)
  led = DillaHarmony.voice_lead_chords(pads, rootless: style != :cluster)
  return pads if led.nil? || led.empty?
  led.map.with_index do |ch, i|
    src = pads[i] || pads.last
    name = ch.is_a?(Hash) ? (ch[:name] || src[:name]) : src[:name]
    hz = ch.is_a?(Hash) ? ch[:hz] : ch
    { name: name, hz: hz, bass_hz: src[:bass_hz] || src[:hz]&.min }
  end
rescue StandardError
  pads
end

def dilla_chord_bass_hz(chord)
  return 43.65 unless chord.is_a?(Hash) && chord[:hz]&.any?
  chord[:hz].min
end

def hz_to_midi(hz)
  69.0 + 12.0 * Math.log2(hz / 440.0)
end

def midi_to_hz(midi)
  (440.0 * (2.0 ** ((midi - 69.0) / 12.0))).round(2)
end

def voice_lead_chords(chords)
  DillaHarmony.voice_lead_chords(chords)
end

def pitch_class_distance(a, b)
  diff = (a - b) % 12.0
  [diff, 12.0 - diff].min
end

def drum_feel_key(feel)
  feel = feel.to_sym
  return feel if DRUM_PATTERN_SETS.key?(feel)
  :default
end

def drum_pattern_seed(feel)
  (feel.hash.abs + (@render_seed || 0)) % 10_000
end

def drum_pattern_pick(bar, feel, role)
  if (learned = learned_drum_steps(role))&.any?
    return learned.dup
  end
  sets = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel))
  pool = sets.fetch(role)
  seed = drum_pattern_seed(feel)
  phrase = bar % 4
  idx = (phrase + seed + (bar / 8)) % pool.length
  steps = Array(pool[idx]).dup
  # Fill bar: extra kick cluster on the & of 4 (step 15) for Dilla-style turns.
  if role == :kicks && bar.positive? && (bar % 8) == 7
    steps << 15 unless steps.include?(15)
  end
  steps.uniq.sort
end

def dilla_kick_pattern(bar, _n_bars, feel)
  drum_pattern_pick(bar, feel, :kicks)
end

def dilla_snare_steps(bar, feel, section:)
  return [] if section == :breakdown
  steps = if DillaGroove.kick_snare_swap?
            drum_pattern_pick(bar, feel, :kicks)
          else
            drum_pattern_pick(bar, feel, :snares)
          end
  pool = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel), DRUM_PATTERN_SETS[:default])[:snares]&.flatten || steps
  steps = DillaGroove.markov_steps(bar, :snare, steps + pool) if steps.any?
  if halftime?
    steps = steps.map { |s| s == 4 ? 8 : s }.reject { |s| s == 12 && bar.even? }
    steps = [8] if steps.empty?
  end
  steps -= [10, 14] if section == :intro
  steps.uniq.sort
end

def dilla_fill_bar?(bar, section)
  return false if %i[intro breakdown].include?(section)
  tier = ghost_tier_for(bar, section)
  fill_mul = GHOST_TIERS.fetch(tier, GHOST_TIERS[:pocket])[:fill_mul]
  return false if tier == :whisper && bar % 16 != 15
  on_phrase = bar % 8 == 7 || (bar.positive? && bar % 16 == 15)
  return false unless on_phrase
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    prof = @composition_session.profile_at(bar)
    rate = prof[:fill_rate].to_f * fill_mul
    return Random.new(bar * 31 + @composition_session.generation).rand < rate.clamp(0.05, 0.95)
  end
  tier == :accent || bar % 8 == 7 || (bar.positive? && bar % 16 == 15)
end

def schedule_drum_fills!(events, bar, base, step_p, swing, quintuplet, timing, beat_p, sec_gain, feel, section)
  return unless dilla_fill_bar?(bar, section)
  seed = drum_pattern_seed(feel) + bar
  DRUM_FILL_SETS[:snare][(bar / 8 + seed) % DRUM_FILL_SETS[:snare].length].each do |step|
    t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
         dilla_timing_ms(:snare, bar, step, timing, beat_p) / 1000.0, 0.0].max
    vel = step >= 10 ? 0.54 : 0.46
    events[:snare] << [t.round(6), dilla_velocity(vel, bar, step, spread: 0.06) * sec_gain]
  end
  if kicks_enabled?
    DRUM_FILL_SETS[:kicks][(bar / 8 + seed) % DRUM_FILL_SETS[:kicks].length].each do |step|
      t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
           dilla_timing_ms(:kick_sync, bar, step, timing, beat_p) / 1000.0, 0.0].max
      events[:kick] << [t.round(6), dilla_velocity(0.4, bar, step, spread: 0.05) * sec_gain * kick_velocity_scale]
    end
  end
  tier = ghost_tier_for(bar, section)
  DRUM_FILL_SETS[:ghosts][(bar / 8 + seed) % DRUM_FILL_SETS[:ghosts].length].each do |step|
    t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
         dilla_timing_ms(:ghost, bar, step, timing, beat_p) / 1000.0, 0.0].max
    vel = apply_ghost_tier_vel(dilla_velocity(0.32, bar, step, spread: 0.07) * sec_gain, tier)
    events[:ghost] << [t.round(6), vel]
  end
end

def schedule_hat_roll!(events, bar, base, step_p, swing, quintuplet, timing, beat_p, sec_gain, section)
  return unless bar % 8 == 7 && !%i[intro breakdown].include?(section)
  # 32nd-note roll on the last beat of every 8-bar phrase (steps 12–15.75).
  16.times do |sub|
    step = 12.0 + sub * 0.25
    t = [base + step * step_p + dilla_swing_offset(step.floor, step_p, swing, quintuplet: quintuplet) +
         dilla_timing_ms(:hat_up, bar, step.floor, timing, beat_p) / 1000.0, 0.0].max
    accel = 0.34 + (sub / 15.0) * 0.22
    events[:hat] << [t.round(6), dilla_velocity(accel, bar, step.floor, spread: 0.1) * sec_gain]
  end
end

def dilla_ghost_steps(bar, feel, section: :main)
  steps = drum_pattern_pick(bar, feel, :ghosts)
  sets = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel))
  steps += drum_pattern_pick(bar, feel, :perc) if sets[:perc]
  pool = sets[:ghosts]&.flatten || steps
  steps = DillaGroove.markov_steps(bar, :ghost, steps + pool) if steps.any? && ENV["MARKOV_DRUMS"] != "0"
  tier = ghost_tier_for(bar, section)
  scale = GHOST_TIERS.fetch(tier, GHOST_TIERS[:pocket])[:steps_scale]
  if scale < 1.0
    steps = steps.select.with_index { |_, i| i.even? || bar.odd? }
  elsif scale > 1.0
    extras = [2, 6, 14].select { |s| !steps.include?(s) && Random.new(bar * 71 + feel.hash).rand < 0.38 }
    steps += extras
  end
  steps.uniq.sort
end

def dilla_open_steps(bar, feel, section:)
  return [] if section == :breakdown
  opens = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel))[:opens]
  return [] unless opens
  return opens if feel == :loose_pocket && bar % 8 == 5
  return [opens[(bar / 2) % opens.length]] if [1, 3].include?(bar % 4)
  []
end

def dilla_section_bounds(n_bars)
  intro = [[(n_bars * 0.12).round, 4].max, (n_bars * 0.22).round].min
  outro = [[(n_bars * 0.10).round, 4].max, (n_bars * 0.18).round].min
  body = [n_bars - intro - outro, 8].max
  cycle = [[body, 16].max, 32].min
  { intro: intro, outro: outro, cycle: cycle, body_start: intro }
end

def dilla_section_legacy(bar, n_bars)
  b = dilla_section_bounds(n_bars)
  return :outro if bar >= n_bars - b[:outro]
  return :intro if bar < b[:intro]
  pos = (bar - b[:body_start]) % b[:cycle]
  brk = (b[:cycle] * 0.75).floor
  bld = (b[:cycle] * 0.875).floor
  return :breakdown if pos >= brk && pos < bld
  return :build if pos >= bld
  :main
end

def dilla_section(bar, n_bars)
  fs = form_section_at(bar, n_bars)
  return fs if fs
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    return COMPOSITION_SECTION_KIND.fetch(@composition_session.section_at(bar), :main)
  end
  dilla_section_legacy(bar, n_bars)
end

def dilla_section_gain(bar, n_bars, chord_phases: nil, pad_chords: nil, chord_bars: 2, phrase_bars: nil)
  sec_gain = if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
               prof = @composition_session.profile_at(bar)
               tension = @composition_session.tension_at(bar)
               (prof[:drums] * 0.35 + prof[:harmony] * 0.35 + tension * 0.3).clamp(0.28, 1.0)
             else
               case dilla_section_legacy(bar, n_bars)
               when :intro then 0.72
               when :breakdown then 0.58
               when :build then 0.88
               when :outro then 0.62
               else 1.0
               end
             end
  phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars: chord_bars, phrase_bars: phrase_bars)
  sec_gain * (phase ? phase_gain_multiplier(phase) : 1.0)
end

def melody_pitch_from_chord(chord, bar, mel_step)
  return nil unless chord && chord[:hz]&.any?
  tones = chord[:hz].sort
  midis = tones.map { |h| hz_to_midi(h) }.sort
  # Rotate through upper chord tones (3rd, 5th, 7th, 9th) — not always the root.
  color_idx = [1, 2, 3, 0, 2, 1][(bar + mel_step) % 6] % midis.length
  base_midi = midis[color_idx]
  rng = Random.new((bar * 97) + (mel_step * 41) + chord[:name].to_s.hash.abs)
  approach = if composition_enabled? && rng.rand < 0.22
               neighbor = DillaComposition::Counterpoint.neighbor_tone(midi_to_hz(base_midi + 12),
                                                                     direction: rng.rand < 0.5 ? :up : :down)
               hz_to_midi(neighbor)
             elsif rng.rand < 0.28
               base_midi - (rng.rand < 0.5 ? 1 : 2)
             else
               base_midi
             end
  voiced = DillaComposition::Counterpoint.adjust_voices([midi_to_hz(approach + 12)])
  voiced.first || midi_to_hz(approach + 12)
end

def schedule_dfam_events!(events, n_bars, beat_p, swing, quintuplet, timing)
  return unless DfamEngine.enabled?
  step_p = beat_p / 4.0
  bar_p = beat_p * 4.0
  track = (ENV["TRACK"] || DillaLofiMachine::DEFAULT_PROFILE).to_s
  pattern = DfamEngine.resolve_pattern(seed: (@render_seed || 0) + track.hash.abs)
  patch = DfamEngine.resolve_patch
  ticks = DillaLofiMachine.humanize_ticks_for(track)
  n_bars.times do |bar|
    16.times do |step|
      idx = (bar * 16 + step) % DfamEngine::STEPS
      pitch = pattern[:pitch][idx] / 100.0
      vel = pattern[:velocity][idx] / 100.0
      t = bar * bar_p + step * step_p +
          dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
          dilla_timing_ms(:hat_down, bar, step, timing, beat_p) / 1000.0
      if ticks.positive?
        h_ms = DillaLofiMachine.humanize_ms(60.0 / beat_p, ticks)
        t += Random.new(bar * 97 + step * 31 + idx).rand(-h_ms..h_ms) / 1000.0
      end
      events[:dfam] << [[t, 0.0].max.round(6), vel, pitch, idx, patch]
    end
  end
end

def render_dfam_wav(path, events, duration)
  return unless events&.any?
  write_stereo_chunks(path, duration) do |chunk_start, chunk_frames, left, right|
    DfamEngine.mix_events!(left, right, events, chunk_start, chunk_frames, sample_rate: SAMPLE_RATE)
  end
  patch = DfamEngine.resolve_patch
  tmp = "#{path}.fx.wav"
  q = (patch[:res_pct] / 100.0 * 6.0 + 0.5).round(2)
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "lowpass=f=#{patch[:filter_hz]}:width_type=q:width=#{q},volume=0.62",
      "-c:a", "pcm_s16le", tmp
  FileUtils.mv(tmp, path)
  path
end

def dilla_hat_steps(bar, feel, n_bars: nil)
  steps = drum_pattern_pick(bar, feel, :hats)
  steps = DillaGroove.euclidean(5, 16, rotation: bar % 16) if ENV["EUCLIDEAN_HATS"] == "1"
  steps += DillaGroove.prime_poly_steps(bar) if ENV["PRIME_GRID"] == "1"
  pool = DRUM_PATTERN_SETS.fetch(drum_feel_key(feel), DRUM_PATTERN_SETS[:default])[:hats]&.flatten || steps
  steps = DillaGroove.markov_steps(bar, :hat, steps + pool)
  steps = DillaGroove.trap_morph_hat_density(bar, n_bars || 16, steps) if n_bars
  steps = DillaRhythm.subdivision_density_steps(steps, bar) if defined?(DillaRhythm)
  if n_bars && bar >= (n_bars * 0.82).to_i
    progress = 1.0 - ((n_bars - 1 - bar).to_f / [n_bars * 0.18, 1].max)
    steps += (0..15).select { |i| i.odd? && Random.new(bar * 421).rand < (0.25 + 0.45 * progress) }
  elsif n_bars && bar >= n_bars - 2
    progress = 1.0 - ((n_bars - 1 - bar).to_f / 2)
    steps += (0..15).select { |i| i.odd? && Random.new(bar * 421 + 7).rand < (0.35 + 0.5 * progress) }
  end
  steps.uniq.sort
end

def flylo_overlay_steps(bar, section, role)
  if (learned = learned_flylo_overlay_steps(role))&.any?
    return learned.dup
  end
  flylo_overlay_grid_pick(bar, section, role)
end

def schedule_flylo_drum_overlay!(events, bar, n_bars, base, step_p, bar_p, beat_p, swing, quintuplet, timing,
                                 sec_gain, section, pad_chords, chord_bars:, phrase_bars:, chord_phases:)
  return unless flylo_drum_overlay_enabled?
  return if camel_mode? && bar < camel_drum_entry_bar
  return if !camel_drum_lock? && drum_drop_bar?(bar, section)

  density = flylo_overlay_density(bar, n_bars, chord_bars: chord_bars, pad_chords: pad_chords,
                                  chord_phases: chord_phases, phrase_bars: phrase_bars)
  density = density.clamp(flylo_primary_drums? ? 0.7 : 0.2, 1.35)
  bar_bpm = DillaRhythm.bar_bpm(bar)
  overlay_gain = camel_drum_lock? ? density : (sec_gain * density)
  timing_use = timing || DillaLofiMachine::DILLA_TIMING
  swing_use = [swing.to_f, 60.0].max

  # --- Simplicity: sparse rotating phrases (not dense onset dumps) ---
  if DillaGroove.pocket_dna?
    kicks = DillaGroove.pocket_kicks(bar)
    hard_snares = DillaGroove.pocket_snares_hard(bar)
    ghost_snares = DillaGroove.pocket_snares_ghost(bar)
    hat_steps = DillaGroove.pocket_hats(bar)
  else
    kicks = flylo_overlay_steps(bar, section, :kicks)
    hard_snares = flylo_overlay_steps(bar, section, :snares)
    ghost_snares = Array(learned_flylo_overlay_steps(:ghost_snares)).map(&:to_i)
    hat_steps = flylo_overlay_steps(bar, section, :hats)
  end

  # --- Micro-timing: swing + snare-early / kick-late / hats-late + freehand kick ---
  place = lambda do |step, role_timing|
    t = base + step * step_p
    t += dilla_swing_offset(step, step_p, swing_use, quintuplet: false, bar: bar, bpm: bar_bpm)
    t += dilla_timing_ms(role_timing, bar, step, timing_use, beat_p) / 1000.0
    t = DillaGroove.apply_pocket_place(t, role: role_timing, beat_p: beat_p, bar: bar, step: step, bpm: bar_bpm)
    [t, 0.0].max
  end

  kicks.each do |step|
    role = step.zero? ? :kick_anchor : :kick_sync
    t = place.call(step, role)
    base_vel = step.zero? ? 0.98 : 0.78
    vel = dilla_velocity(base_vel, bar, step, spread: 0.03) *
          overlay_gain * flylo_kick_velocity_scale
    vel *= 0.75 unless step.zero? || step == 10
    sk = DillaGroove.kick_sample_key(bar, step)
    events[:flylo_kick] << [t.round(6), vel.clamp(0.55, 0.99), sk]
  end

  return if section == :breakdown && !camel_keep_flylo_on_breakdown? && !camel_drum_lock?

  (hard_snares | ghost_snares).each do |step|
    ghost = ghost_snares.include?(step) && !hard_snares.include?(step)
    t = place.call(step, ghost ? :ghost : :snare)
    base_vel = ghost ? 0.22 : 0.9
    vel = dilla_velocity(base_vel, bar, step, spread: 0.04) *
          overlay_gain * (ghost ? 1.0 : 1.75)
    sk = DillaGroove.snare_sample_key(ghost: ghost)
    events[:flylo_snare] << [t.round(6), vel.clamp(ghost ? 0.1 : 0.6, ghost ? 0.32 : 0.98), sk]
  end

  if backbeat_clap_enabled?
    hard_snares.each do |step|
      t = place.call(step, :clap)
      vel = dilla_velocity(0.32, bar, step, spread: 0.03) * overlay_gain
      events[:clap] << [t.round(6), vel.clamp(0.14, 0.48), :clap]
    end
  end

  hat_steps.each do |step|
    role = step.even? ? :hat_down : :hat_up
    t = place.call(step, role)
    base_vel = step.even? ? 0.46 : 0.32
    vel = dilla_velocity(base_vel, bar, step, spread: 0.06) * overlay_gain
    events[:flylo_hat] << [t.round(6), vel.clamp(0.16, 0.68), :hat]
  end

  if DillaGroove.pocket_open_hat?(bar)
    t = place.call(14, :open)
    vel = dilla_velocity(0.38, bar, 14, spread: 0.04) * overlay_gain
    events[:flylo_hat] << [t.round(6), vel.clamp(0.18, 0.5), :open_hat]
  end
  # No perc / quint / rim spam — simplicity is the trick.
end

def dilla_schedule(n_bars, beat_p, pad_chords, chord_bars: 4, phrase_bars: nil, drums_only: false,
                   swing: 58.0, feel: :default, timing: nil, quintuplet: false, bass_pads: nil,
                   chord_phases: nil)
  bar_p  = (beat_p * 4.0).round(6)
  step_p = (beat_p / 4.0).round(6)
  events = Hash.new { |h, k| h[k] = [] }
  groove_meta = { snare_early_ms: [], hat_late_ms: [], ghost_vel: [] }
  # Odd-meter/hemiola nod (Aydin Esen's Turkish-modal odd meters, without a
  # full rewrite of the 16-step grid): every 16th bar loses its last 2
  # steps — a real short bar, not a fake accent. Cumulative bar starts
  # since bar durations are no longer uniform.
  drop_beat_bar = ->(b) { b.positive? && b % 16 == 15 }
  bar_starts = [0.0]
  (1..n_bars).each { |b| bar_starts << bar_starts.last + (drop_beat_bar.call(b - 1) ? bar_p * 0.875 : bar_p) }
  chord_change_i = -1
  prev_bass_root = nil
  prev_pad_chord = nil
  cfg_sched = dilla_resolve_config
  bpm_base = cfg_sched[:bpm]

  if DillaRhythm.macro_enabled? && %w[1].intersect?([ENV["TEMPO_RAMP"], ENV["BPM_STAIRCASE"], ENV["TEMPO_ACCEL"]])
    bar_starts = [0.0]
    (1...n_bars).each { |b| bar_starts << bar_starts.last + DillaRhythm.bar_duration_sec(b - 1, beat_p) }
  end

  n_bars.times do |bar|
    base = bar_starts[bar]
    bar_bpm = DillaRhythm.bar_bpm(bar)
    beat_p_bar = 60.0 / bar_bpm
    section = dilla_section(bar, n_bars)
    apply_motif_recall!(bar)
    ghost_tier = ghost_tier_for(bar, section)
    sec_gain = dilla_section_gain(bar, n_bars, chord_phases: chord_phases, pad_chords: pad_chords,
                                  chord_bars: chord_bars, phrase_bars: phrase_bars)
    sec_gain *= DillaRhythm.stripdown_gain(bar, section)
    sec_gain *= DillaRhythm.element_strip_gain(base)
    sec_gain *= DillaRhythm.periodic_layer_drop_gain(bar)
    phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars: chord_bars, phrase_bars: phrase_bars)
    chop_entry = spectral_arp_chop_bar?(bar, chord_bars, drums_only, section)
    pattern = if DillaGroove.kick_snare_swap?
                dilla_snare_steps(bar, feel, section: section)
              else
                dilla_kick_pattern(bar, n_bars, feel)
              end
    pattern = (pattern + [0, 15]).uniq.sort if chop_entry && kicks_enabled?
    pattern = [7, 14] if section == :breakdown
    intro_drum_cutoff = camel_mode? ? camel_drum_entry_bar : 4
    pattern = [0, 10] if section == :intro && bar < intro_drum_cutoff
    pattern = pattern.select { |s| s < 14 } if drop_beat_bar.call(bar)

    chord_lens_sched = instance_variable_defined?(:@render_chord_bar_lens) ? @render_chord_bar_lens : nil
    cur_chord = if drums_only || pad_chords.empty?
                  nil
                else
                  pad_chords[dilla_chord_index(bar, pad_chords, chord_bars: chord_bars, phrase_bars: phrase_bars,
                                                 chord_bar_lens: chord_lens_sched)]
                end
    # Real bitonal composition, not just chord-following: when bass_pads is
    # given, the bass tracks its own independent progression instead of
    # always echoing the pad chord's root — the bass and the chords can
    # genuinely disagree, on purpose.
    bass_chord = if bass_pads && !bass_pads.empty?
                   bass_pads[dilla_chord_index(bar, bass_pads, chord_bars: chord_bars, phrase_bars: phrase_bars)]
                 else
                   cur_chord
                 end
    bass_root = dilla_chord_bass_hz(bass_chord)
    unless drums_only || section == :breakdown || bass_root.nil?
      slide_from = bass_slide_enabled? && prev_bass_root && (prev_bass_root - bass_root).abs > 0.5 ? prev_bass_root : nil
      bar_bass = [base + 0.012, dilla_velocity(0.52, bar, 99, spread: 0.04) * sec_gain, bass_root, bar_p * 0.92]
      bar_bass << slide_from if slide_from
      events[:bass] << bar_bass
      prev_bass_root = bass_root
    end
    if feel == :chromatic_planing
      pickup = base - step_p * 2
      if kicks_enabled?
        events[:kick] << [[pickup + dilla_timing_ms(:kick_sync, bar, 0, timing, beat_p) / 1000.0, 0.0].max.round(6),
                          dilla_velocity(0.88, bar, 0)]
      end
      events[:bass] << [[pickup + dilla_timing_ms(:bass, bar, 0, timing, beat_p) / 1000.0, 0.0].max.round(6),
                        dilla_velocity(0.50, bar, 0, spread: 0.05), bass_root]
    end

    drop_bar = drum_drop_bar?(bar, section)

    if dilla_pocket_drums_enabled? && kicks_enabled? && !drop_bar
      pattern.each_with_index do |step, i|
        role = (feel == :syncopated_slash_ninth || step.nonzero?) ? :kick_sync : :kick_anchor
        t = [base + step * step_p +
             dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet, bar: bar, bpm: bar_bpm) +
             dilla_timing_ms(role, bar, step, timing, beat_p) / 1000.0, 0.0].max
        t = DillaGroove.apply_event_timing!(t, role: :kick, beat_p: beat_p, bar: bar, step: step, bpm: bar_bpm)
        ks = kick_velocity_scale
        kick_role = step.zero? ? :kick_anchor : :kick_sync
        kick_vel = dilla_role_velocity(kick_role, bar, step, sec_gain: sec_gain * ks)
        events[:kick] << [t.round(6), kick_vel]
        if step.zero?
          events[:sub_osc] ||= []
          events[:sub_osc] << [t.round(6), dilla_velocity(0.06, bar, step, spread: 0.04) * sec_gain * ks, 40.0]
        end
        bass_skip = drums_only ||
                    (feel == :syncopated_slash_ninth && bar.zero? && step < 7) ||
                    (feel != :syncopated_slash_ninth && bar.zero?) ||
                    (section == :breakdown && step < 8)
        next if bass_skip
        bass_lag = feel == :syncopated_slash_ninth ? step_p * 0.12 : 0.0
        events[:bass] << [[t + dilla_timing_ms(:bass, bar, step, timing, beat_p) / 1000.0 + bass_lag, 0.0].max.round(6),
                          dilla_velocity(0.28, bar, step, spread: 0.06) * sec_gain, bass_root, step_p * 0.55]
      end
    end

    if dilla_pocket_drums_enabled? && !(section == :intro && bar < intro_drum_cutoff)
      dilla_snare_steps(bar, feel, section:).each_with_index do |step, si|
        next if drop_bar
        next if section == :breakdown
        t = [base + step * step_p +
             dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet, bar: bar, bpm: bar_bpm) +
             dilla_timing_ms(:snare, bar, step, timing, beat_p) / 1000.0 +
             DillaGroove.flam_offset_sec, 0.0].max
        t = DillaGroove.apply_event_timing!(t, role: :snare, beat_p: beat_p, bar: bar, step: step, bpm: bar_bpm)
        backbeat = halftime? ? [8].include?(step) : [4, 12].include?(step)
        groove_meta[:snare_early_ms] << dilla_timing_ms(:snare, bar, step, timing, beat_p) if backbeat
        snare_vel = dilla_role_velocity(:snare, bar, step, sec_gain: sec_gain, backbeat: backbeat)
        events[:snare] << [t.round(6), snare_vel]
        if backbeat && backbeat_clap_enabled? && %i[main build].include?(section)
          events[:clap] ||= []
          events[:clap] << [t.round(6), dilla_role_velocity(:clap, bar, step, sec_gain: sec_gain), :clap]
        end
        if backbeat && si.zero?
          ghost_vel = apply_ghost_tier_vel(dilla_role_velocity(:ghost, bar, step, sec_gain: sec_gain) * 0.72, ghost_tier)
          groove_meta[:ghost_vel] << ghost_vel
          events[:ghost] << [(t - 0.001).round(6).clamp(0.0, Float::INFINITY), ghost_vel]
        end
      end
    end

    if dilla_pocket_drums_enabled?
      ghost_steps = dilla_ghost_steps(bar, feel, section: section)
      ghost_steps += [1, 9] if feel == :loose_pocket && bar.odd?
      ghost_steps += [5] if feel == :loose_pocket && bar.even?
      ghost_steps.uniq.each do |step|
        next if drop_bar
        t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
             dilla_timing_ms(:ghost, bar, step, timing, beat_p) / 1000.0, 0.0].max
        ghost_vel = apply_ghost_tier_vel(dilla_role_velocity(:ghost, bar, step, sec_gain: sec_gain), ghost_tier)
        ghost_vel = (ghost_vel * 1.12).clamp(0.03, 0.72).round(3) if feel == :loose_pocket
        groove_meta[:ghost_vel] << ghost_vel
        events[:ghost] << [t.round(6), ghost_vel]
      end

      hat_steps = dilla_hat_steps(bar, feel, n_bars:)
      hat_steps = hat_steps.select.with_index { |_, i| i.even? } if section == :breakdown || chop_entry
      hat_steps.each_with_index do |step, i|
        next if drop_bar
        next if DillaGroove.hat_should_drop?(bar, step)
        role = if [3, 11].include?(step) && feel == :syncopated_slash_ninth
                 :hat_up
               elsif feel == :loose_pocket && step.odd?
                 :hat_up
               else
                 i.even? ? :hat_down : :hat_up
               end
        t = [base + step * step_p +
             dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet, bar: bar, bpm: bar_bpm) +
             dilla_timing_ms(role, bar, step, timing, beat_p) / 1000.0, 0.0].max
        t = DillaGroove.apply_event_timing!(t, role: role, beat_p: beat_p, bar: bar, step: step, bpm: bar_bpm)
        hat_role = role == :hat_up ? :hat_up : :hat_down
        groove_meta[:hat_late_ms] << dilla_timing_ms(hat_role, bar, step, timing, beat_p)
        events[:hat] << [t.round(6), dilla_role_velocity(hat_role, bar, step, sec_gain: sec_gain)]
      end

      dilla_open_steps(bar, feel, section:).each do |open_step|
        events[:open] << [[base + open_step * step_p + dilla_swing_offset(open_step, step_p, swing, quintuplet: quintuplet) + 0.008, 0.0].max.round(6),
                          dilla_role_velocity(:open, bar, open_step, sec_gain: sec_gain)]
      end
      if feel == :loose_pocket && section == :main && bar % 6 == 4
        events[:ghost] << [[base + 10 * step_p + dilla_swing_offset(10, step_p, swing, quintuplet: quintuplet), 0.0].max.round(6),
                           dilla_velocity(0.22, bar, 10, spread: 0.04) * sec_gain]
      end

      schedule_hat_roll!(events, bar, base, step_p, swing, quintuplet, timing, beat_p, sec_gain, section) unless drop_bar
      schedule_drum_fills!(events, bar, base, step_p, swing, quintuplet, timing, beat_p, sec_gain, feel, section) unless drop_bar
    end
    schedule_flylo_drum_overlay!(events, bar, n_bars, base, step_p, bar_p, beat_p, swing, quintuplet, timing,
                                 sec_gain, section, pad_chords, chord_bars: chord_bars, phrase_bars: phrase_bars,
                                 chord_phases: chord_phases)

    next if drums_only
    next if section == :intro && bar < 2

    chord_lens = instance_variable_defined?(:@render_chord_bar_lens) ? @render_chord_bar_lens : nil
    cur_idx = dilla_chord_index(bar, pad_chords, chord_bars: chord_bars, phrase_bars: phrase_bars,
                                chord_bar_lens: chord_lens)
    prev_idx = bar.positive? ? dilla_chord_index(bar - 1, pad_chords, chord_bars: chord_bars,
                                                 phrase_bars: phrase_bars, chord_bar_lens: chord_lens) : -1
    if chord_lens&.any?
      next unless bar.zero? || cur_idx != prev_idx
    else
      next unless (bar % chord_bars).zero?
    end

    chord_change_i += 1
    chord = pad_chords[cur_idx]
    pad_chord = if section == :breakdown && DillaHarmony.soul_profile?(cfg_sched[:track])
                  DillaHarmony.strip_voices(chord, count: 2)
                else
                  chord
                end
    pad_chord = DillaHarmony.fix_chord_for_schedule(pad_chord, prev_pad_chord,
                                                    curated: curated_progression?(cfg_sched))
    cvar = dilla_chord_change_variation(chord_change_i, bar, section, feel, step_p, pad_chord)
    pad_t = base + cvar[:pad_offset] + dilla_timing_ms(:pad, bar, 0, timing, beat_p) / 1000.0
    if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
      lead_role = DillaComposition::Conversation.turn_order(bar).first
      pad_t += DillaComposition::Conversation.answer_offset(lead_role, beat_p) * 0.12
    end
    hold_bars = chord_lens&.dig(cur_idx) || chord_bars
    legato_mul = if la_beat_progression_enabled?
                   rng_leg = Random.new(patch_cycle_seed(cur_idx + bar))
                   rng_leg.rand(0.78..1.12)
                 else
                   1.0
                 end
    sustain = (hold_bars * bar_p * 0.97 * cvar[:sustain_mul] * legato_mul *
               DillaHarmony.pad_overlap_mul(prev_pad_chord, pad_chord)).round(4)
    prev_pad_chord = pad_chord
    pad_vel = dilla_velocity(phase == :recapitulation ? 0.96 : 0.92, bar, 0, spread: 0.03) * sec_gain
    pad_vel *= 0.88 if phase == :development
    pad_vel *= cvar[:pad_vel_mul]
    events[:pad] << [[pad_t, 0.0].max.round(6), pad_vel, pad_chord, sustain]
    if cvar[:double_pad]
      events[:pad] << [[pad_t + cvar[:double_pad_delay], 0.0].max.round(6),
                       dilla_velocity(cvar[:double_pad_vel], bar, 1, spread: 0.05) * sec_gain, pad_chord, sustain * 0.68]
    elsif (feel == :timeless || LOFI_DRUM_FEELS.include?(feel)) && section == :main && bar % 4 == 1 && phase != :development
      events[:pad] << [[pad_t + step_p * 0.5, 0.0].max.round(6),
                       dilla_velocity(0.22, bar, 1, spread: 0.05) * sec_gain, pad_chord, sustain * 0.72]
    end
    unless section == :breakdown || phase == :development
      chop_steps = cvar[:chop_steps]
      chop_steps = chop_steps.select { |s| s < 12 } if phase != :recapitulation && chop_steps.length > 4
      chop_steps << 15 if phase == :recapitulation && chord_change_i % 3 == 1
      chop_chord = if DillaSpectral.breath_mode?
                     { name: "breath", hz: DillaSpectral.breath_perc_hz }
                   elsif DillaHarmony.soul_profile?(cfg_sched[:track])
                     DillaHarmony.chop_tones(pad_chord)
                   else
                     pad_chord
                   end
      chop_steps.uniq.sort.each do |chop_step|
        chop_t = [base + chop_step * step_p + dilla_swing_offset(chop_step, step_p, swing, quintuplet: quintuplet) +
                  cvar[:chop_jitter], 0.0].max
        chop_vel = phase == :recapitulation ? 0.58 : 0.52
        events[:chop] << [chop_t.round(6), dilla_velocity(chop_vel, bar, chop_step, spread: 0.04) * sec_gain, chop_chord]
      end
    end
    mel_allowed = !drums_only && section == :main && phase != :coda &&
                  (phase == :recapitulation || (bar % 4 == 2 && phase != :development))
    if mel_allowed
      mel_step = [2, 6, 10][bar % 3]
      mel_hz = melody_pitch_from_chord(chord, bar, mel_step)
      if mel_hz
        mel_t = [base + mel_step * step_p + dilla_swing_offset(mel_step, step_p, swing, quintuplet: quintuplet) + 0.006, 0.0].max
        mel_vel = phase == :recapitulation ? 0.44 : 0.38
        events[:melody] << [mel_t.round(6), dilla_velocity(mel_vel, bar, mel_step, spread: 0.06) * sec_gain, mel_hz]
      end
    end
  end
  schedule_dfam_events!(events, n_bars, beat_p, swing, quintuplet, timing)
  events[:_groove_meta] = groove_meta
  events
end

def dilla_kick_wave(t, v, *)
  c = @dilla_cycle
  tm = (t % c).round(6)
  "between(mod(t,#{c}),#{tm},#{(tm + 0.42).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*7.4)*sin(2*PI*(45+115*exp(-20*(mod(t,#{c})-#{tm})))*(mod(t,#{c})-#{tm}))"
end

def dilla_bass_wave(t, v, root_hz = 43.0)
  c = @dilla_cycle
  tm = (t % c).round(6)
  lfo = "0.03*sin(2*PI*0.12*(mod(t,#{c})-#{tm}))"
  sustain = BASS_SUSTAIN_SEC.round(3)
  decay = BASS_DECAY_RATE.round(3)
  "between(mod(t,#{c}),#{tm},#{(tm + sustain).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*#{decay})*sin(2*PI*(#{root_hz}+#{root_hz}*#{lfo})*(mod(t,#{c})-#{tm}))"
end

def dilla_snare_env(events)
  c = @dilla_cycle
  hits = events.fetch(:snare, []).map { |t, v| [t, v, 0.18] } + events.fetch(:ghost, []).map { |t, v| [t, v, 0.09] }
  return "0" if hits.empty?
  hits.map do |t, v, d|
    tm = (t % c).round(6)
    "between(mod(t,#{c}),#{tm},#{(tm + d).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*#{(d < 0.12 ? 35 : 23).round(1)})"
  end.join("+")
end

def dilla_hat_env(events, key, decay: 78)
  c = @dilla_cycle
  dur = key == :open ? 0.25 : 0.06
  list = events.fetch(key, [])
  return "0" if list.empty?
  list.map do |t, v|
    tm = (t % c).round(6)
    "between(mod(t,#{c}),#{tm},#{(tm + dur).round(6)})*#{v}*exp(-(mod(t,#{c})-#{tm})*#{decay})"
  end.join("+")
end

def dilla_pad_layers(f, t, sustain, bar_i, gain: 0.035)
  drift = 1.0 + (Math.sin((bar_i + 1) * 1.7) * 0.0012)
  ff = (f * drift).round(4)
  atk = 0.072
  layers = [
    "sin(2*PI*#{ff}*(t-#{t}))",
    "0.58*sin(2*PI*#{(ff * 1.006).round(4)}*(t-#{t}))",
    "0.34*sin(2*PI*#{(ff * 2.008).round(4)}*(t-#{t}))",
    "0.18*sin(2*PI*#{(ff * 3.01).round(4)}*(t-#{t}))",
    "0.14*sin(2*PI*#{(ff * 0.5).round(4)}*(t-#{t}))"
  ].join("+")
  env = "min(1,pow((t-#{t})/#{atk},1.35))*exp(-(t-#{t})*0.07)*(0.80+0.20*sin(2*PI*0.18*(t-#{t})))"
  "between(t,#{t},#{(t + sustain).round(4)})*#{gain}*#{env}*(#{layers})"
end

def dilla_pad_wave(t, v, chord, sustain, bar_i = 0)
  voices = chord[:hz].each_with_index.map { |f, i| dilla_pad_layers(f, t, sustain, bar_i + i, gain: 0.028 + i * 0.003) }
  "(#{voices.join('+')})"
end

def dilla_drum_filter(snare_env, hat_env, open_env, duration, sample_input: nil)
  filter = []
  filter << "[0:a]aformat=channel_layouts=stereo[kick]"
  filter << "[1:a]aformat=channel_layouts=stereo,lowpass=f=140[bass]"
  filter << "[2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no]"
  filter << "[ns]volume='(#{snare_env})':eval=frame,highpass=f=160,bandpass=f=1600:w=2600[snare]"
  filter << "[nh]volume='(#{hat_env})':eval=frame,highpass=f=6500[hats]"
  filter << "[no]volume='(#{open_env})':eval=frame,bandpass=f=5600:w=5200[open]"
  filter << "[4:a]aformat=channel_layouts=stereo,#{DillaAutomation.pad_character_filter(cutoff_hz: 2800, phaser_speed: 0.12, phaser_decay: 0.35)},adelay=9|13,aecho=0.18:0.22:120:0.22[pads]"
  filter << "[5:a]aformat=channel_layouts=stereo,highpass=f=120,lowpass=f=5000,aecho=0.18:0.22:90:0.28[chop]"
  labels  = %w[[kick] [bass] [snare] [hats] [open] [pads] [chop]]
  weights = %w[1.15 0.88 0.82 0.42 0.35 0.90 0.55]
  if sample_input
    filter << "[#{sample_input}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
              "highpass=f=80,lowpass=f=14000,acrusher=bits=12:samples=2:mix=0.22[sample]"
    labels  << "[sample]"
    weights << "0.72"
  end
  filter << "[3:a]volume=0.06,highpass=f=120,lowpass=f=6000[vinyl]"
  sat = Math.tanh(1.55).round(6)
  filter << "#{labels.join}[vinyl]amix=inputs=#{labels.length + 1}:weights=#{weights.join(' ')} 0.08:duration=first," \
            "aeval=exprs='tanh(1.55*val(0))/#{sat}|tanh(1.55*val(1))/#{sat}'," \
            "acompressor=threshold=-22dB:ratio=2.8:attack=18:release=110:makeup=4," \
            "acrusher=bits=12:samples=1.69:mix=0.18," \
            "equalizer=f=45:width_type=o:width=1.2:g=2," \
            "alimiter=limit=0.93:level_out=0.95[out]"
  filter.join(";")
end

# --- Sample-based drum engine (MPC one-shots + Ruby mixer) ---

def drum_kit_ready?
  %w[kick.wav snare.wav ghost.wav hat.wav open_hat.wav bass_43.wav
     ind_kick.wav ind_clap.wav ind_hat.wav ind_bass_e.wav ind_bass_bb.wav ind_stab.wav].all? do |name|
    File.exist?(File.join(DRUM_DIR, name))
  end
end

# kick.wav deliberately excluded: it's a 4-layer synthesis (sample + sub
# drop + body punch + click transient via layered_kick_sample) tuned
# across many iterations — swapping its base sample for a random external
# one-shot and re-layering synthesis on top produced an unpredictable,
# bad-sounding result ("that stupid kickdrum sound" — direct feedback).
DRUM_SAMPLE_SUBDIR = {
  "snare.wav" => "snares", "hat.wav" => "hi-hats",
  "open_hat.wav" => "open-hats", "ghost.wav" => "claps", "bass_43.wav" => "808s"
}.freeze
EXTERNAL_DRUM_KITS = %w[01-hard-trap 02-bounce 03-soulful-vintage].freeze

# One choice per render (called once at the top of render_dilla, not per
# sample), matching how EP/warm-pad/lead voices already vary per render
# rather than per hit — a real drum kit doesn't swap character mid-hit.
def pick_render_seed!
  DillaSeeds.apply!
  @render_seed = DillaSeeds.render_seed
end

def pick_external_drum_kit!
  @current_external_kit = nil
  return unless ensure_external_assets_lazy!
  if (kit = ENV["EXTERNAL_KIT"]) && !kit.empty?
    kit_dir = File.join(EXTERNAL_DRUM_KIT_CACHE, "drum-samples", kit)
    if Dir.exist?(kit_dir)
      @current_external_kit = kit
      return
    end
  end
  track = (ENV["TRACK"] || "").to_s
  soul = DillaHarmony.soul_profile?(track) || ENV["DILLA_STREAMING"] == "1"
  roll = rand
  @current_external_kit = if soul
                            if roll < 0.72
                              "03-soulful-vintage"
                            elsif roll < 0.88
                              "02-bounce"
                            else
                              EXTERNAL_DRUM_KITS.sample
                            end
                          elsif roll < 0.35
                            EXTERNAL_DRUM_KITS.sample
                          end
end

# Hats/snares/claps synthesized from a bandpassed noise burst (generate_drum_kit!)
# are thin/harsh by construction — pure noise decaying in ~20ms has no body.
# pick_external_drum_kit! rolls a real-sample kit only 35-88% of the time
# (track-dependent); these three roles matter enough to the drum sound that
# they should reach for real samples whenever the (already-fetched) kit
# cache exists, not just when the roll happened to land on it.
ALWAYS_SAMPLED_DRUM_ROLES = %w[hat.wav open_hat.wav snare.wav ghost.wav].freeze

def drum_sample_path(name)
  custom = File.join(CUSTOM_DRUM_DIR, name)
  return custom if File.exist?(custom)

  subdir = DRUM_SAMPLE_SUBDIR[name]
  if subdir
    kit = @current_external_kit
    kit ||= "03-soulful-vintage" if ALWAYS_SAMPLED_DRUM_ROLES.include?(name) && Dir.exist?(EXTERNAL_DRUM_KIT_CACHE)
    if kit
      kit_dir = File.join(EXTERNAL_DRUM_KIT_CACHE, "drum-samples", kit, subdir)
      picked = Dir.glob(File.join(kit_dir, "*.wav")).sample
      return picked if picked
    end
  end

  File.join(DRUM_DIR, name)
end

def generate_drum_kit!
  require_tools! "ffmpeg"
  FileUtils.mkdir_p(DRUM_DIR)
  FileUtils.mkdir_p(CUSTOM_DRUM_DIR)
  force = ENV["FORCE_KIT"] == "1"
  sr = SAMPLE_RATE
  recipes = [
    ["kick.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.9*exp(-t*7.5)*sin(2*PI*(48+210*exp(-t*28))*t)+0.55*exp(-t*95)*sin(2*PI*3200*t)*between(t,0,0.006)':d=0.55:s=#{sr}"],
     "lowpass=f=180,acrusher=bits=12:samples=2:mix=0.42,equalizer=f=55:t=o:w=0.8:g=4,acompressor=threshold=-20dB:ratio=3:attack=3:release=50"],
    ["snare.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.32:color=white:amplitude=0.95", "-f", "lavfi", "-i", "sine=f=195:d=0.32"],
     "[0:a]asplit=2[n][n2];[n]highpass=f=1200,lowpass=f=7000,aeval=exprs='val(0)*exp(-t*32)'[crack];" \
     "[n2]bandpass=f=350:w=500,aeval=exprs='val(0)*exp(-t*18)'[rattle];[1:a]aeval=exprs='val(0)*exp(-t*22)'[body];" \
     "[crack][rattle][body]amix=inputs=3:weights=0.75 0.35 0.45,acrusher=bits=10:samples=2:mix=0.38"],
    ["ghost.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.14:color=pink:amplitude=0.7"],
     "highpass=f=900,lowpass=f=5500,aeval=exprs='val(0)*exp(-t*48)',volume=0.55"],
    ["hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.07:color=white:amplitude=1"],
     "highpass=f=7500,lowpass=f=15000,aeval=exprs='val(0)*exp(-t*140)',acrusher=bits=8:samples=1:mix=0.55"],
    ["open_hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.42:color=white:amplitude=0.85"],
     "highpass=f=6000,bandpass=f=9000:w=5000,aeval=exprs='val(0)*exp(-t*9)'"],
    ["bass_43.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.75*exp(-t*1.1)*sin(2*PI*(43+5*sin(2*PI*0.28*t))*t)':d=1.35:s=#{sr}"],
     "lowpass=f=120,equalizer=f=50:t=o:w=1:g=6"],
    ["ind_kick.wav",
     ["-f", "lavfi", "-i", "aevalsrc='0.95*exp(-t*5.5)*sin(2*PI*(50+520*exp(-t*45))*t)':d=0.65:s=#{sr}"],
     "aeval=exprs='tanh(5.5*val(0))/tanh(5.5)',lowpass=f=140,equalizer=f=52:t=o:w=0.6:g=9,acompressor=threshold=-16dB:ratio=10:attack=1:release=35"],
    ["ind_clap.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.22:color=white:amplitude=1"],
     "[0:a]asplit=3[a][b][c];[a]adelay=0|3,highpass=f=1400,aeval=exprs='val(0)*exp(-t*24)'[c1];" \
     "[b]adelay=12|15,highpass=f=1800,aeval=exprs='val(0)*exp(-(t-0.012)*30)'[c2];[c]bandpass=f=900:w=1800,aeval=exprs='val(0)*exp(-t*20)'[c3];" \
     "[c1][c2][c3]amix=inputs=3,acompressor=threshold=-14dB:ratio=6:attack=1:release=25"],
    ["ind_hat.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.05:color=white:amplitude=1"],
     "highpass=f=9000,aeval=exprs='val(0)*exp(-t*160)',equalizer=f=12000:t=o:w=2:g=4"],
    ["ind_bass_e.wav",
     ["-f", "lavfi", "-i", "aevalsrc='(2*mod(41.2*t,1)-1)*exp(-t*7)*0.8':d=0.24:s=#{sr}"],
     "lowpass=f=420,aeval=exprs='tanh(2.8*val(0))/tanh(2.8)'"],
    ["ind_bass_bb.wav",
     ["-f", "lavfi", "-i", "aevalsrc='(2*mod(58.27*t,1)-1)*exp(-t*7)*0.8':d=0.24:s=#{sr}"],
     "lowpass=f=420,aeval=exprs='tanh(2.8*val(0))/tanh(2.8)'"],
    ["ind_stab.wav",
     ["-f", "lavfi", "-i", "anoisesrc=d=0.35:color=white:amplitude=0.9", "-f", "lavfi", "-i", "sine=f=164.81:d=0.35"],
     "[0:a]bandpass=f=280:w=900,aeval=exprs='val(0)*exp(-t*14)'[m];[1:a]aeval=exprs='val(0)*exp(-t*11)'[t];" \
     "[m][t]amix=inputs=2:weights=0.7 0.35,lowpass=f=2800"]
  ]
  recipes.each do |name, inputs, chain|
    dest = File.join(DRUM_DIR, name)
    next if File.exist?(dest) && !force
    if chain.include?("[") || chain.include?(";")
      sh! "ffmpeg", "-y", *inputs, "-filter_complex", chain, "-ar", SAMPLE_RATE.to_s, dest
    else
      sh! "ffmpeg", "-y", *inputs, "-af", chain, "-ar", SAMPLE_RATE.to_s, dest
    end
    puts "kit: #{name}"
  end
end

def ensure_drum_kit!
  generate_drum_kit! unless drum_kit_ready?
end

# Optional one-shots sliced from demucs drums (path under samples/) for DRUM_CHOPS=1.
DRUM_CHOP_SOURCE = "samples/demux/htdemucs_6s/flylo_camel_source/drums.wav"
DRUM_CHOP_DIR = "samples/drums/custom/grid_chops"
DRUM_CHOP_BPM = 86.0

def ensure_drum_chops!
  dest = File.join(ROOT, DRUM_CHOP_DIR)
  return dest if %w[kick.wav snare.wav hat.wav].all? { |n| File.file?(File.join(dest, n)) }
  src = File.join(ROOT, DRUM_CHOP_SOURCE)
  return nil unless File.file?(src)
  FileUtils.mkdir_p(dest)
  step = 60.0 / DRUM_CHOP_BPM / 4.0
  bar8 = 8 * 4 * step
  { "kick.wav" => 0, "snare.wav" => 4, "hat.wav" => 2 }.each do |name, step_i|
    t0 = (bar8 + step_i * step + 0.5).round(3)
    dur = name.start_with?("kick") ? 0.28 : (name.start_with?("snare") ? 0.22 : 0.12)
    out = File.join(dest, name)
    system("ffmpeg", "-y", "-ss", t0.to_s, "-t", dur.to_s, "-i", src,
           "-af", "aformat=sample_rates=44100:channel_layouts=mono,highpass=f=30,alimiter=limit=0.95",
           "-c:a", "pcm_s16le", out, out: File::NULL, err: File::NULL)
  end
  File.file?(File.join(dest, "kick.wav")) ? dest : nil
end

def wav_sample_rate(path)
  out, = Open3.capture2("ffprobe", "-v", "error", "-show_entries", "stream=sample_rate",
                        "-of", "default=noprint_wrappers=1:nokey=1", path)
  out.to_s.strip.to_i
rescue StandardError
  0
end

def load_kit_wav(path)
  return nil unless path && File.file?(path)
  # DillaMusicGems.read_mono_wav (wavefile gem) decodes raw samples with NO
  # resample — fine for our own kit (already SAMPLE_RATE-native), wrong for
  # external samples at a different native rate (free-drum-samples ships
  # 22050Hz). Loaded at the wrong rate, a hit plays back half-speed and an
  # octave low — this was making the whole external-kit drum sound "horrible".
  # ffprobe first; only take the no-resample fast path when the rate already
  # matches, otherwise force the ffmpeg fallback below which does resample.
  if defined?(DillaMusicGems) && DillaMusicGems.respond_to?(:read_mono_wav) && wav_sample_rate(path) == SAMPLE_RATE
    samples = DillaMusicGems.read_mono_wav(path)
    return samples if samples && !samples.empty?
  end
  # ffmpeg fallback — resamples to SAMPLE_RATE, no wavefile gem required
  raw, = Open3.capture2("ffmpeg", "-v", "error", "-i", path,
                        "-f", "f32le", "-ac", "1", "-ar", SAMPLE_RATE.to_s, "pipe:1")
  return nil if raw.nil? || raw.empty?
  raw.unpack("e*")
rescue StandardError
  nil
end

# True if drum_sample_path(name) resolved to a real sample (custom dir or
# the external free-drum-samples kit) rather than the synthesized fallback
# in DRUM_DIR — used to stop the camel/grid one-shot chops below from
# silently clobbering a better sample that already won.
def external_sample_used?(name)
  !drum_sample_path(name).start_with?(DRUM_DIR)
end

def apply_drum_chops_to_kit!(kit)
  # Prefer pre-cut Camel oneshots, then grid_chops from demucs stem — but
  # only for roles that didn't already resolve to a real external-kit
  # sample. These one-shots are all sliced from a single FlyLo Camel
  # render (camel_chops and grid_chops are literally byte-identical files),
  # so they were unconditionally overwriting the hat/snare fix above with
  # the same narrow, zero-variety source every render.
  dirs = [
    File.join(CUSTOM_DRUM_DIR, "camel_chops"),
    File.join(ROOT, DRUM_CHOP_DIR),
    ensure_drum_chops!
  ].compact.uniq
  roles = { kick: "kick.wav", snare: "snare.wav", hat: "hat.wav" }
           .reject { |_, file| external_sample_used?(file) }
  return kit if roles.empty?
  dirs.each do |dest|
    next unless dest && Dir.exist?(dest)
    roles.each do |role, file|
      path = File.join(dest, file)
      samples = load_kit_wav(path)
      kit[role] = samples if samples && !samples.empty?
    end
    # Keep a second kick body for alternation (MPC two-kick habit).
    if roles.key?(:kick)
      alt = load_kit_wav(File.join(dest, "kick.wav"))
      kit[:ind_kick] = alt if alt && !alt.empty? && kit[:ind_kick].nil?
    end
    break if (!roles.key?(:kick) || kit[:kick]) && (!roles.key?(:snare) || kit[:snare])
  end
  kit
end

# Explicit, opt-in external asset fetch (never runs on its own — the whole
# engine is otherwise pure-Ruby/ffmpeg synthesis with zero external assets).
# Caches into the same ~/.cache/dilla-soundfonts dir GeneralUser-GS already
# uses, plus a sibling ~/.cache/dilla-samples for one-shot drum WAVs.
EXTERNAL_SOUNDFONTS = {
  "galaxy-electric-pianos.sf2" => "https://smpldsnds.github.io/soundfonts/soundfonts/galaxy-electric-pianos.sf2",
  "supersaw-collection.sf2" => "https://smpldsnds.github.io/soundfonts/soundfonts/supersaw-collection.sf2"
}.freeze
EXTERNAL_DRUM_KIT_REPO = "https://github.com/Boochi44/free-drum-samples"
EXTERNAL_DRUM_KIT_CACHE = File.expand_path("~/.cache/dilla-samples/free-drum-samples")

# Fetched assets are pinned by content: the first fetch records each file's
# SHA256 (and the drum-kit repo's HEAD commit) into checksums.json next to
# the cache; later runs verify and warn on drift instead of silently
# rendering with different-sounding assets. Warn, not abort — upstream may
# have legitimately updated, and the fix is deleting the manifest entry.
def assets_verify_or_record!(manifest_path, key, actual)
  require "digest" # cheap, but only needed on this path
  manifest = File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path)) : {}
  if manifest.key?(key)
    return if manifest[key] == actual
    warn "warn: #{key} changed since first fetch (#{manifest[key][0, 12]}… -> #{actual[0, 12]}…) — " \
         "renders may sound different; delete its entry in #{manifest_path} to accept the new version"
  else
    manifest[key] = actual
    File.write(manifest_path, JSON.pretty_generate(manifest))
  end
end

def fetch_assets!
  require_tools! "curl"
  require "digest"
  sf_dir = File.expand_path("~/.cache/dilla-soundfonts")
  FileUtils.mkdir_p(sf_dir)
  manifest_path = File.join(sf_dir, "checksums.json")
  EXTERNAL_SOUNDFONTS.each do |name, url|
    dest = File.join(sf_dir, name)
    if File.exist?(dest)
      puts "have: #{name}"
    else
      puts "fetching #{name}..."
      sh! "curl", "-sL", "--fail", "-o", dest, url
    end
    assets_verify_or_record!(manifest_path, name, Digest::SHA256.file(dest).hexdigest)
  end

  if Dir.exist?(EXTERNAL_DRUM_KIT_CACHE)
    puts "have: free-drum-samples"
  else
    require_tools! "git"
    puts "fetching free-drum-samples (CC0)..."
    FileUtils.mkdir_p(File.dirname(EXTERNAL_DRUM_KIT_CACHE))
    sh! "git", "clone", "--depth", "1", EXTERNAL_DRUM_KIT_REPO, EXTERNAL_DRUM_KIT_CACHE
  end
  head, _err, status = capture("git", "-C", EXTERNAL_DRUM_KIT_CACHE, "rev-parse", "HEAD")
  assets_verify_or_record!(manifest_path, "free-drum-samples@HEAD", head.strip) if status.success?
  puts "assets cached. Use DILLA_SOUNDFONT=#{sf_dir}/<file>.sf2, or `ruby dilla.rb use-external-kit <01-hard-trap|02-bounce|03-soulful-vintage>`."
end

# Copies one kit's one-shots into CUSTOM_DRUM_DIR, which drum_sample_path
# already prefers over the synthesized kit — no synthesis code changes
# needed, this just populates the existing override hook.
def use_external_kit!(kit_name)
  src_dir = File.join(EXTERNAL_DRUM_KIT_CACHE, "drum-samples", kit_name)
  abort "kit '#{kit_name}' not found — run `ruby dilla.rb fetch-assets` first" unless Dir.exist?(src_dir)
  FileUtils.mkdir_p(CUSTOM_DRUM_DIR)
  {
    "kick.wav" => "kicks", "snare.wav" => "snares", "hat.wav" => "hi-hats",
    "open_hat.wav" => "open-hats", "ghost.wav" => "claps", "bass_43.wav" => "808s"
  }.each do |dest_name, subdir|
    src = Dir.glob(File.join(src_dir, subdir, "*.wav")).min_by { |f| File.size(f) }
    next unless src
    FileUtils.cp(src, File.join(CUSTOM_DRUM_DIR, dest_name))
    puts "installed #{dest_name} <- #{kit_name}/#{subdir}/#{File.basename(src)}"
  end
  puts "custom kit installed — clear #{CUSTOM_DRUM_DIR} to go back to synthesized drums."
end

def load_mono_sample(path)
  floats = DillaMusicGems.read_mono_wav(path) if defined?(DillaMusicGems)
  return floats if floats&.any?
  pipe_floats(path, "aformat=channel_layouts=mono:sample_fmts=flt")
end

# Abstract-kit kicks are never one thin
# sample — they stack a pitch-dropping sub body for weight, a short
# broadband click for attack/definition, and mild saturation for character.
# Layers on top of the existing sample rather than replacing it.
# Synthesized since no shaker/cowbell samples exist in the kit — filtered
# noise burst for the shaker (broadband "shhh" with a fast-then-slow
# double-envelope, real shaker physics: an initial hit then beads settling)
def synth_shaker_sample(seed: 11)
  len = (0.09 * SAMPLE_RATE).round
  rng = Random.new(seed)
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 24.0) + 0.3 * Math.exp(-t * 60.0)
    out[i] = 0.5 * env * (rng.rand * 2.0 - 1.0)
  end
  peak = out.map(&:abs).max || 1.0
  out.map { |s| s / [peak, 0.01].max * 0.8 }
end

# Classic two-oscillator 808/909 cowbell: two square-ish tones (540Hz and
# 800Hz, the real ratio used in analog cowbell circuits) with a fast decay.
def synth_cowbell_sample
  len = (0.18 * SAMPLE_RATE).round
  out = Array.new(len, 0.0)
  len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 14.0)
    tone1 = Math.sin(2 * Math::PI * 540.0 * t) > 0 ? 1.0 : -1.0
    tone2 = Math.sin(2 * Math::PI * 800.0 * t) > 0 ? 1.0 : -1.0
    out[i] = 0.42 * env * (0.6 * tone1 + 0.4 * tone2)
  end
  out
end

# Karplus-Strong plucked-string synthesis (Stanford/CCRMA algorithm,
# exact) — a genuinely new instrument timbre, not another oscillator/
# soundfont voice. Fill a ring buffer of noise, then average adjacent
# samples with a stretch factor for decay/damping control.
def karplus_strong_pluck(freq, duration_sec, seed: nil, stretch: 0.996, damping: 0.5)
  n = (SAMPLE_RATE / freq).round.clamp(2, SAMPLE_RATE)
  rng = seed ? Random.new(seed) : Random.new
  buf = Array.new(n) { rng.rand * 2.0 - 1.0 }
  total = (duration_sec * SAMPLE_RATE).round
  out = Array.new(total, 0.0)
  total.times do |i|
    idx = i % n
    if i < n
      out[i] = buf[idx]
    else
      prev = out[i - n]
      prev2 = out[i - n - 1] || prev
      averaged = damping * prev + (1.0 - damping) * prev2
      out[i] = stretch * averaged
    end
  end
  out
end

def layered_kick_sample(base_sample, seed: 7)
  # True 808-style envelope, not a short punch: a fast pitch drop (150Hz ->
  # 42Hz over ~55ms, the "pluck") into a genuinely sustained low tone
  # (~350ms total, slow decay) — the long boom is the whole point of an
  # 808, not an incidental side effect of layering.
  sub_len = (0.35 * SAMPLE_RATE).round
  click_len = (0.009 * SAMPLE_RATE).round
  out = base_sample.dup
  out.concat(Array.new(sub_len - out.length, 0.0)) if out.length < sub_len
  sub_len.times do |i|
    t = i.to_f / SAMPLE_RATE
    pitch = 42.0 + 108.0 * Math.exp(-t * 55.0)
    env = Math.exp(-t * 9.0)
    out[i] += 0.34 * env * Math.sin(2 * Math::PI * pitch * t)
  end
  rng = Random.new(seed)
  click_len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 380.0)
    out[i] += 0.14 * env * (rng.rand * 2.0 - 1.0)
  end
  # Body layer: a short mid-punch (~150Hz) between the sub and the click —
  # definition that survives on small speakers where the 42Hz fundamental
  # barely reproduces at all.
  body_len = (0.05 * SAMPLE_RATE).round
  body_len.times do |i|
    t = i.to_f / SAMPLE_RATE
    env = Math.exp(-t * 55.0)
    out[i] += 0.18 * env * Math.sin(2 * Math::PI * 150.0 * t)
  end
  peak = out.map(&:abs).max || 1.0
  gain = peak > 0.95 ? 0.95 / peak : 1.0
  # A single gentle saturation pass, not stacked with anything downstream —
  # double saturation (this plus a second stage on the whole drum bus) is
  # what made it sound bad, not the layering itself.
  drive = 1.1
  ceiling = Math.tanh(drive)
  # Old formula (0.16*KICK_GAIN+0.06) crushed kicks to ~0.2 peak before the bus —
  # inaudible under pads. Camel/FlyLo needs near-unity sample level.
  sample_mul = if flylo_primary_drums?
                 ENV.fetch("KICK_SAMPLE_GAIN", "0.95").to_f.clamp(0.4, 1.2)
               else
                 (0.16 * kick_velocity_scale + 0.06).clamp(0.08, 0.55)
               end
  out.map { |s| (Math.tanh(s * gain * drive) / ceiling) * sample_mul }
end

def mix_sine!(left, right, frame, frames_n, hz, amp, decay: 2.6, mod_hz: 0.23, chorus: false,
              source_offset: 0)
  voices = if chorus
             [{ cents: 0.0, pan: 0.0, gain: 0.55 }, { cents: 5.5, pan: -0.42, gain: 0.28 },
              { cents: -5.5, pan: 0.42, gain: 0.28 }, { cents: 11.0, pan: -0.18, gain: 0.12 }]
           else
             [{ cents: 0.0, pan: 0.0, gain: 1.0 }]
           end
  frames_n.times do |i|
    idx = frame + i
    break if idx >= left.length
    t = (source_offset + i).to_f / SAMPLE_RATE
    env = Math.exp(-t * decay) * (0.78 + 0.22 * Math.sin(2 * Math::PI * mod_hz * t))
    voices.each do |voice|
      fh = hz * (2 ** (voice[:cents] / 1200.0))
      s = amp * voice[:gain] * env * Math.sin(2 * Math::PI * fh * t)
      pan = voice[:pan]
      left[idx]  += s * (0.5 - pan * 0.5)
      right[idx] += s * (0.5 + pan * 0.5)
    end
  end
end

# Rhodes/Juno-style pad voice — slow attack, detuned stack, harmonic bloom, stereo spread.
def mix_dilla_pad_voice!(left, right, frame, frames_n, hz, amp, voice_i: 0, bar_i: 0, sub: false,
                         source_offset: 0, total_frames: frames_n, absolute_frame_origin: 0)
  attack_n  = (0.072 * SAMPLE_RATE).round
  release_n = (0.48 * SAMPLE_RATE).round
  wow_hz    = 0.16 + voice_i * 0.025
  flutter   = 4.1 + voice_i * 0.35
  pan_base  = [-0.38, -0.12, 0.14, 0.36, 0.22][voice_i % 5]
  oscs = [
    { cents: 0.0,  gain: sub ? 0.52 : 0.38, pan: pan_base,        harm: 0.16 },
    { cents: 7.5,  gain: 0.20,              pan: pan_base + 0.18, harm: 0.08 },
    { cents: -6.0, gain: 0.16,              pan: pan_base - 0.16, harm: 0.05 },
    { cents: 13.0, gain: 0.07,              pan: pan_base + 0.28, harm: 0.03 }
  ]
  frames_n.times do |i|
    idx = frame + i
    break if idx >= left.length
    source_i = source_offset + i
    t = source_i.to_f / SAMPLE_RATE
    t_abs = (absolute_frame_origin + frame + i).to_f / SAMPLE_RATE
    attack = source_i < attack_n ? (source_i.to_f / attack_n) ** 1.35 : 1.0
    rel_i = total_frames - source_i
    release = rel_i < release_n ? (rel_i.to_f / release_n) ** 0.75 : 1.0
    sustain = Math.exp(-t * (sub ? 0.05 : 0.07))
    breathe = 0.80 + 0.20 * Math.sin(2 * Math::PI * wow_hz * t_abs + bar_i * 0.55)
    drift = 1.0 + 0.0014 * Math.sin(2 * Math::PI * 0.065 * t_abs + voice_i * 0.9)
    flutter_mod = 1.0 + 0.005 * Math.sin(2 * Math::PI * flutter * t_abs)
    env = amp * attack * release * sustain * breathe * flutter_mod
    oscs.each do |o|
      fh = hz * drift * (2 ** (o[:cents] / 1200.0))
      phase = 2 * Math::PI * fh * t
      body = Math.sin(phase)
      warm = 0.72 * body + 0.28 * Math.sin(phase * 3) / 3.0
      s = env * o[:gain] * (warm + o[:harm] * Math.sin(phase * 2))
      pan = o[:pan].clamp(-0.48, 0.48)
      left[idx]  += s * (0.5 - pan * 0.5)
      right[idx] += s * (0.5 + pan * 0.5)
    end
  end
end

STREAM_CHUNK_SECONDS = 4
PAD_RENDER_SAMPLE_RATE = 22_050

def soft_clip_sample(sample, knee: 0.85)
  magnitude = sample.abs
  return sample if magnitude <= knee

  sample.negative? ? -(knee + (1.0 - knee) * Math.tanh((magnitude - knee) / (1.0 - knee))) :
                     knee + (1.0 - knee) * Math.tanh((magnitude - knee) / (1.0 - knee))
end

def soft_clip_stereo_chunk!(left, right)
  left.map! { |sample| soft_clip_sample(sample) }
  right.map! { |sample| soft_clip_sample(sample) }
end

# Write long buses incrementally. At 44.1 kHz a five-minute stereo Float array
# can exceed a gigabyte in Ruby; fixed-size chunks keep the render bounded while
# preserving oscillator phase and one-shot tails across chunk boundaries.
def write_stereo_chunks(path, duration, chunk_seconds: STREAM_CHUNK_SECONDS)
  total_frames = (duration * SAMPLE_RATE).ceil
  chunk_frames = [(chunk_seconds * SAMPLE_RATE).to_i, 1].max
  stdin, stdout, stderr, wait = Open3.popen3(
    "ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", SAMPLE_RATE.to_s,
    "-ac", "2", "-i", "-", "-c:a", "pcm_s16le", path
  )
  out_reader = Thread.new { stdout.read }
  err_reader = Thread.new { stderr.read }
  chunk_start = 0
  while chunk_start < total_frames
    count = [chunk_frames, total_frames - chunk_start].min
    left = Array.new(count, 0.0)
    right = Array.new(count, 0.0)
    yield chunk_start, count, left, right
    # A fixed transfer curve is invariant across chunk boundaries; per-chunk
    # normalization would audibly pump a sustained pad every four seconds.
    soft_clip_stereo_chunk!(left, right)
    interleaved = Array.new(count * 2)
    count.times do |i|
      interleaved[i * 2] = left[i]
      interleaved[i * 2 + 1] = right[i]
    end
    stdin.write(interleaved.pack("e*"))
    chunk_start += count
  end
  stdin.close
  status = wait.value
  out_reader.value
  error = err_reader.value
  abort "wav stream failed: #{error}" unless status.success?
  path
ensure
  stdin&.close unless stdin&.closed?
end

def overlap_window(event_frame, event_frames, chunk_start, chunk_frames)
  overlap_start = [event_frame, chunk_start].max
  overlap_end = [event_frame + event_frames, chunk_start + chunk_frames].min
  return nil if overlap_end <= overlap_start

  [overlap_start - chunk_start, overlap_start - event_frame, overlap_end - overlap_start]
end

def warm_dilla_pad_post(path, cfg: nil, sonic: nil)
  cfg ||= dilla_resolve_config
  sonic ||= cfg[:sonic]
  warm_dilla_pad_post_enhanced(path, sonic, cfg)
end

def fm_native_enabled?
  return false if ENV["FM_NATIVE"] == "0"
  return true if ENV["FM_NATIVE"] == "1"
  synth_morph_enabled? || lead_morph_enabled?
end

def fm_ratio_for_chord(event_idx)
  FM_RATIO_POOL[event_idx % FM_RATIO_POOL.length]
end

def fm_mod_ratio_expr(m_start, m_end, sustain, irrational:)
  return m_start.round(4).to_s unless irrational && m_start != m_end
  s = [sustain, 0.01].max.round(4)
  ms = m_start.round(4)
  me = m_end.round(4)
  "#{ms}+(#{me}-#{ms})*min(1,t/#{s})"
end

def fm_index_from_velocity(velocity, base_index:, role: :pad)
  vel = velocity.to_f.clamp(0.05, 1.0)
  scale = role == :xlead ? FM_INDEX_VEL_SCALE : (FM_INDEX_VEL_SCALE * 0.75)
  (base_index * (0.45 + vel * scale * 0.18)).round(3)
end

def fm_mod_envelope(role: :pad, atk: nil, decay: nil, sustain_level: nil)
  case role
  when :xlead
    a = (atk || 0.004).round(4)
    d = (decay || 0.28).round(4)
    s = (sustain_level || 0.35).round(3)
  else
    a = ((atk || 0.004) * 2.5).round(4)
    d = ((decay || 0.28) * 0.55).round(4)
    s = ((sustain_level || 0.35) * 0.9).round(3)
  end
  "min(1,pow(t/#{[a, 0.001].max},0.9))*((1-#{s})*exp(-t*#{d})+#{s})"
end

def native_fm_waveform_body(frequency, index_expr:, bloom: 0.2, drift: "1", detune: 0.004,
                            feedback: 0.0, phase_seed: 0.0, mod_ratio_expr: "1")
  f = frequency.round(4)
  det_up = (frequency * (1.0 + detune)).round(4)
  f_m = "(#{f}*(#{mod_ratio_expr}))"
  mod = "sin(2*PI*#{f_m}*#{drift}*t+#{phase_seed.round(3)})"
  phase_arg = "2*PI*#{f}*#{drift}*t+(#{index_expr})*#{mod}"
  fb = feedback.to_f.round(3)
  phase_arg = "#{phase_arg}+#{fb}*sin(#{phase_arg})" if fb.positive?
  carrier = "sin(#{phase_arg})"
  "0.70*#{carrier}+#{bloom.round(3)}*sin(2*PI*#{f}*#{drift}*t)+0.12*sin(2*PI*#{det_up}*#{drift}*t)"
end

def native_waveform_body(frequency, wave:, bloom: 0.2, drift: "1", detune: 0.004, phase_seed: 0.0,
                         fm_index_expr: nil, mod_ratio_expr: nil, fm_feedback: 0.0)
  f = frequency.round(4)
  det_up = (frequency * (1.0 + detune)).round(4)
  det_dn = (frequency * (1.0 - detune)).round(4)
  case wave
  when :saw
    "0.55*(2*mod(#{f}*#{drift}*t,1)-1)+0.22*(2*mod(#{det_up}*#{drift}*t,1)-1)+0.18*(2*mod(#{det_dn}*#{drift}*t,1)-1)"
  when :triangle
    "0.62*(2*abs(2*mod(#{f}*#{drift}*t,1)-1)-1)+0.20*sin(2*PI*#{f}*#{drift}*t)"
  when :square
    "0.48*(2*floor(2*mod(#{f}*#{drift}*t,1))-1)+0.28*sin(2*PI*#{f * 2.0}*#{drift}*t)"
  when :pwm
    pw = "0.35+0.15*sin(2*PI*0.4*t+#{phase_seed.round(3)})"
    "0.5*(2*floor(mod(#{f}*#{drift}*t,1)/(#{pw}))-1)+0.25*sin(2*PI*#{det_up}*#{drift}*t)"
  when :fm
    idx = fm_index_expr || "2.2"
    return native_fm_waveform_body(frequency, index_expr: idx, bloom: bloom, drift: drift,
                                   detune: detune, feedback: fm_feedback, phase_seed: phase_seed,
                                   mod_ratio_expr: mod_ratio_expr || "1.5")
  when :organ
    "0.42*sin(2*PI*#{f}*#{drift}*t)+0.28*sin(2*PI*#{f * 2.0}*#{drift}*t)+0.18*sin(2*PI*#{f * 3.0}*#{drift}*t)+0.12*sin(2*PI*#{f * 4.0}*#{drift}*t)"
  when :bowed
    "0.55*sin(2*PI*#{f}*#{drift}*t)+0.25*sin(2*PI*#{f * 2.0}*#{drift}*t)+0.12*sin(2*PI*#{f * 3.0}*#{drift}*t)"
  when :juno
    "0.50*sin(2*PI*#{f}*#{drift}*t)+0.30*sin(2*PI*#{det_up}*#{drift}*t)+0.20*sin(2*PI*#{det_dn}*#{drift}*t)+" \
    "#{bloom.round(3)}*sin(2*PI*#{f * 2.0}*#{drift}*t)"
  when :moog
    sub = (frequency * 0.5).round(4)
    f2 = (frequency * 2.0).round(4)
    # Ladder-ish: saw stack + sub octave, soft triangle body for warmth.
    "0.46*(2*mod(#{f}*#{drift}*t,1)-1)+0.20*(2*mod(#{det_up}*#{drift}*t,1)-1)+" \
    "0.14*(2*mod(#{det_dn}*#{drift}*t,1)-1)+#{bloom.round(3)}*(2*mod(#{sub}*#{drift}*t,1)-1)+" \
    "0.12*(2*abs(2*mod(#{f}*#{drift}*t,1)-1)-1)+0.08*sin(2*PI*#{f2}*#{drift}*t)"
  when :prophet
    det2 = (frequency * (1.0 + detune * 1.8)).round(4)
    det3 = (frequency * (1.0 - detune * 1.8)).round(4)
    # Prophet-5 unison: five slightly detuned saws + gentle 2nd harmonic.
    "0.30*(2*mod(#{f}*#{drift}*t,1)-1)+0.20*(2*mod(#{det_up}*#{drift}*t,1)-1)+" \
    "0.20*(2*mod(#{det_dn}*#{drift}*t,1)-1)+0.14*(2*mod(#{det2}*#{drift}*t,1)-1)+" \
    "0.12*(2*mod(#{det3}*#{drift}*t,1)-1)+#{bloom.round(3)}*sin(2*PI*#{f * 2.0}*#{drift}*t)+" \
    "0.06*sin(2*PI*#{f}*#{drift}*t)"
  else # :rhodes default — tine fundamental + odd harmonics + stereo detune
    f3 = (frequency * 3.0).round(4)
    f5 = (frequency * 5.0).round(4)
    bell = "exp(-t*18)*sin(2*PI*#{f * 4.0}*t)"
    "0.58*sin(2*PI*#{f}*#{drift}*t)+#{bloom.round(3)}*sin(2*PI*#{f3}*#{drift}*t)+" \
    "0.06*sin(2*PI*#{f5}*#{drift}*t)+0.22*sin(2*PI*#{det_up}*#{drift}*t)+" \
    "0.22*sin(2*PI*#{det_dn}*#{drift}*t)+0.12*#{bell}"
  end
end

def native_pad_voice_expression(hz, amp, voice_i, pan, phase_seed, native_patch: nil,
                                event_i: 0, velocity: 0.72, sustain: 8.0)
  frequency = hz.round(4)
  drift = "(1+0.0014*sin(2*PI*0.065*t+#{phase_seed.round(3)}))"
  wave = @render_pad_native_wave || DillaLofiMachine.native_wave_for_pad
  native = native_patch&.dig(:native) || @render_native_patch&.dig(:native) ||
           { wave: wave, detune: 0.004, bloom: 0.28 }
  pad_gain = @render_pad_gain || 1.0
  wave_sym = native[:wave] || :rhodes
  fm_index_expr = nil
  mod_ratio_expr = nil
  fm_feedback = native[:fm_feedback] || 0.0
  if wave_sym == :fm && fm_native_enabled?
    ratio = fm_ratio_for_chord(event_i + voice_i)
    mod_ratio_expr = fm_mod_ratio_expr(ratio[:m], ratio[:target_m], sustain, irrational: ratio[:irrational])
    base_idx = fm_index_from_velocity(velocity, base_index: native[:fm_index] || FM_INDEX_BASE_PAD, role: :pad)
    mod_env = fm_mod_envelope(role: :pad)
    fm_index_expr = "(#{base_idx})*#{mod_env}"
    fm_feedback = native[:fm_feedback] || FM_FEEDBACK_DEFAULT * 0.65
  end
  body = native_waveform_body(frequency, wave: wave_sym, bloom: native[:bloom] || 0.2,
                              drift: drift, detune: native[:detune] || 0.004, phase_seed: phase_seed,
                              fm_index_expr: fm_index_expr, mod_ratio_expr: mod_ratio_expr,
                              fm_feedback: fm_feedback)
  breathe = "(0.80+0.20*sin(2*PI*#{(0.16 + voice_i * 0.025).round(3)}*t+#{phase_seed.round(3)}))"
  atk = (@render_pad_attack_sec || 0.072).round(4)
  rel = (@render_pad_release_decay || 0.07).round(4)
  env = "min(1,pow(t/#{atk},1.15))*exp(-t*#{rel})*#{breathe}"
  ["#{(amp * pad_gain).round(6)}*#{(0.5 - pan * 0.5).round(4)}*#{env}*#{body}",
   "#{(amp * pad_gain).round(6)}*#{(0.5 + pan * 0.5).round(4)}*#{env}*#{body}"]
end

def render_native_pad_wav(path, pad_events, duration)
  filters = []
  labels = []
  pad_events.each_with_index do |(time, velocity, chord, sustain), event_i|
    next unless chord
    left_parts = []
    right_parts = []
    chord[:hz].sort.each_with_index do |hz, voice_i|
      pan = [-0.38, -0.12, 0.14, 0.36, 0.22][voice_i % 5]
      amp = velocity * (0.058 + voice_i * 0.0048)
      pair = native_pad_voice_expression(hz, amp, voice_i, pan, event_i * 0.55 + voice_i * 0.9,
                                        event_i: event_i, velocity: velocity, sustain: sustain)
      left_parts << pair[0]
      right_parts << pair[1]
      next unless voice_i.zero?

      sub_pair = native_pad_voice_expression(hz * 0.5, amp * 0.42, voice_i + 5, pan, event_i * 0.61,
                                             event_i: event_i, velocity: velocity * 0.82, sustain: sustain)
      left_parts << sub_pair[0]
      right_parts << sub_pair[1]
    end
    delay = [(time * 1000.0).round, 0].max
    label = "pad#{event_i}"
    # The pad is low-passed below 3 kHz later, so a half-rate oscillator bed is
    # lossless for its audible band and roughly halves long-render DSP time.
    filters << "aevalsrc=exprs='#{expr_sum(left_parts)}|#{expr_sum(right_parts)}':d=#{sustain.round(4)}:s=#{PAD_RENDER_SAMPLE_RATE}," \
               "adelay=#{delay}|#{delay}[#{label}]"
    labels << "[#{label}]"
  end
  if labels.empty?
    filters << "anullsrc=r=#{PAD_RENDER_SAMPLE_RATE}:cl=stereo:d=#{duration}[pads]"
  else
    filters << "#{labels.join}amix=inputs=#{labels.length}:duration=longest:normalize=0," \
               "atrim=0:#{duration},alimiter=limit=0.95:level_out=0.96[pads]"
  end
  sh! "ffmpeg", "-y", "-filter_complex", filters.join(";"), "-map", "[pads]", "-c:a", "pcm_s16le", path
  path
end

# --- FluidSynth pad rendering (real sampled electric-piano tone instead of ---
# --- the pure-additive-sine aevalsrc engine above) -------------------------

# GM program 4 = "Electric Piano 1" (Rhodes-style) — the classic Dilla/neo-soul
# keys tone. Overridable since a different soundfont's map may differ.
PAD_GM_PROGRAM = ENV.fetch("DILLA_PAD_PROGRAM", "4").to_i
# Electric-piano family (Dilla/neo-soul: Rhodes, Wurlitzer-adjacent DX EP)
# and warm-analog-pad family (Prophet/Moog-adjacent GM pad patches) — a
# different pair picked per render instead of the same two programs every
# time.
EP_GM_PROGRAMS = [4, 5, 0, 2, 1, 3].freeze # Rhodes, DX EP, acoustic, Electric Grand, Wurlitzer-adjacent
# Full GM Pad 1-8 family plus researched additions: Synth Strings 1/2 (Juno/
# Solina-style analog string pad), String Ensemble 2 (slow-attack, functions
# as a pad), Choir Aahs, Drawbar Organ (fits the soul-sample aesthetic,
# GeneralUser GS's patch here is a specifically strong one).
WARM_PAD_GM_PROGRAMS = [88, 89, 90, 91, 92, 93, 94, 95, 50, 51, 49, 52, 16].freeze
SMF_PPQN = 480
SMF_TICKS_PER_SECOND = SMF_PPQN * 2 # fixed internal reference tempo of 120 BPM

def pad_soundfont_path
  return ENV["DILLA_SOUNDFONT"] if ENV["DILLA_SOUNDFONT"] && File.exist?(ENV["DILLA_SOUNDFONT"])

  # GeneralUser GS (mrbumpy409/GeneralUser-GS on GitHub, free-for-any-use
  # license) — a real 261-preset GM bank, cached locally rather than
  # committed to the repo. Falls back to fluid-synth's small bundled test
  # font if it hasn't been fetched.
  cached = File.expand_path("~/.cache/dilla-soundfonts/GeneralUser-GS.sf2")
  return cached if File.exist?(cached)

  Dir.glob("/opt/homebrew/Cellar/fluid-synth/*/share/fluid-synth/sf2/*.sf2")
     .find { |f| f.match?(/VintageDreamsWaves-v2\.sf2\z/) }
end

def fluidsynth_pad_available?
  tool_available?("fluidsynth") && !pad_soundfont_path.nil?
end

def midi_vlq(number)
  bytes = [number & 0x7f]
  number >>= 7
  while number.positive?
    bytes.unshift((number & 0x7f) | 0x80)
    number >>= 7
  end
  bytes.pack("C*")
end

def midi_fx_specs_for_role(role, patch = nil)
  base = patch&.dig(:midi_fx)
  if role == :lead || role == :lead_arp
    rich = ENV.fetch("STREAM_LEAD_MIDI_RICH", "1") != "0"
    return (rich ? MIDI_FX_LEAD_RICH : MIDI_FX_LEAD) unless base && !base.empty?
    rich ? (base + MIDI_FX_LEAD_RICH.last(3)) : base
  elsif role == :scale_lead
    (base && !base.empty?) ? base : MIDI_FX_SCALE_LEAD
  else
    base || case role
            when :ep then MIDI_FX_PAD_EP
            when :warm, :texture then MIDI_FX_PAD_WARM
            end
  end
end

def midi_fx_automation(duration, specs, channel: 0)
  return [] unless duration && specs && !specs.empty?
  ticks_total = (duration * SMF_TICKS_PER_SECOND).round
  out = []
  specs.each do |spec|
    if spec[:bend]
      rate = spec.fetch(:rate_hz, 0.3)
      depth = spec.fetch(:depth_cents, 10)
      samples = (duration * 6).ceil.clamp(8, 48)
      samples.times do |i|
        tick = (i * ticks_total.to_f / samples).round
        t = i.to_f / samples
        cents = depth * Math.sin(2 * Math::PI * rate * duration * t)
        bend_val = (8192 + (cents / 100.0 * 4096)).round.clamp(0, 16_383)
        lsb = bend_val & 0x7f
        msb = (bend_val >> 7) & 0x7f
        out << [tick, [0xE0 | channel, lsb, msb]]
      end
      next
    end
    cc = spec[:cc]
    depth = spec.fetch(:depth, 40)
    base = spec.fetch(:base, 30)
    rate = spec.fetch(:rate_hz, 0.25)
    curve = spec.fetch(:curve, :sine)
    samples = (duration * 6).ceil.clamp(8, 48)
    samples.times do |i|
      tick = (i * ticks_total.to_f / samples).round
      t = i.to_f / [samples - 1, 1].max
      val = case curve
            when :sine then base + depth * Math.sin(2 * Math::PI * rate * duration * (i.to_f / samples))
            when :swell then base + depth * Math.sin(Math::PI * t * 0.85)
            when :slow_open then spec.fetch(:start, 60) + (spec.fetch(:end, 110) - spec.fetch(:start, 60)) * t
            else base
            end
      out << [tick, [0xB0 | channel, cc, val.round.clamp(0, 127)]]
    end
  end
  out.sort_by { |tick, _| tick }
end

# Writes SMF with note events plus MIDI CC / pitch-bend automation.
def write_smf(path, note_events, program: PAD_GM_PROGRAM, bank: 0, duration: nil, midi_fx: nil, channel: 0,
              lead_mode: false)
  timed = []
  note_events.each do |parts|
    time, velocity, chord, sustain = parts[0], parts[1], parts[2], parts[3]
    next unless chord && chord[:hz]&.any?
    chord[:hz].each do |hz|
      note = hz_to_midi(hz).round.clamp(0, 127)
      on_tick = (time * SMF_TICKS_PER_SECOND).round
      off_tick = (on_tick + (sustain * SMF_TICKS_PER_SECOND)).round
      vel_mul = lead_mode ? 100 : 108
      vel_min = lead_mode ? 36 : 48
      vel = (velocity.clamp(0.0, 1.0) * vel_mul).round.clamp(vel_min, 127)
      timed << [on_tick, :on, note, vel]
      timed << [off_tick, :off, note, 0]
    end
  end
  midi_fx_automation(duration, midi_fx, channel: channel).each do |tick, bytes|
    timed << [tick, :cc, bytes]
  end
  timed.sort_by! { |tick, kind, *| [tick, kind == :off ? 0 : 1, kind == :cc ? 1 : 2] }

  track_events = [[0, [0xB0 | channel, 0x00, bank & 0x7f].pack("C*")],
                  [0, [0xC0 | channel, program].pack("C*")]]
  last_tick = 0
  timed.each do |entry|
    tick = entry[0]
    kind = entry[1]
    delta = [tick - last_tick, 0].max
    bytes = if kind == :cc
              entry[2].pack("C*")
            else
              status = kind == :on ? (0x90 | channel) : (0x80 | channel)
              [status, entry[2], entry[3]].pack("C*")
            end
    track_events << [delta, bytes]
    last_tick = tick
  end
  track_events << [0, [0xFF, 0x2F, 0x00].pack("C*")]

  track_data = track_events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  File.binwrite(path, header + track_chunk)
  path
end

# Per-chord bank/program changes — morph Rhodes / Prophet / Moog presets across a progression.
def write_smf_morph(path, pad_events, duration:, role:, midi_fx: nil, channel: 0, lead_mode: false)
  timed = []
  first_patch = nil
  pad_events.each_with_index do |parts, i|
    patch = morph_patch_for_chord(i, role: role)
    next unless patch
    first_patch ||= patch
    voice = patch_voice_for(patch)
    time, velocity, chord, sustain = parts[0], parts[1], parts[2], parts[3]
    next unless chord && chord[:hz]&.any?
    on_tick = (time * SMF_TICKS_PER_SECOND).round
    off_tick = (on_tick + (sustain * SMF_TICKS_PER_SECOND)).round
    timed << [on_tick, :bank, voice[:bank]]
    timed << [on_tick, :prog, voice[:program]]
    chord[:hz].each do |hz|
      note = hz_to_midi(hz).round.clamp(0, 127)
      vel_mul = lead_mode ? 100 : 108
      vel_min = lead_mode ? 36 : 48
      vel = (velocity.clamp(0.0, 1.0) * vel_mul).round.clamp(vel_min, 127)
      timed << [on_tick, :on, note, vel]
      timed << [off_tick, :off, note, 0]
    end
  end
  if la_beat_progression_enabled? && pad_events.length >= 2
    pad_events.each_with_index do |parts, i|
      on_tick = (parts[0] * SMF_TICKS_PER_SECOND).round
      seg_dur = [parts[3], 0.5].max
      fx = LA_BEAT_MIDI_FX_ROTATE[i % LA_BEAT_MIDI_FX_ROTATE.length]
      midi_fx_automation(seg_dur, [fx], channel: channel).each do |tick, bytes|
        timed << [on_tick + tick, :cc, bytes]
      end
    end
  end
  midi_fx_automation(duration, midi_fx, channel: channel).each do |tick, bytes|
    timed << [tick, :cc, bytes]
  end
  kind_prio = { bank: 0, prog: 1, on: 2, cc: 3, off: 4 }
  timed.sort_by! { |tick, kind, *| [tick, kind_prio.fetch(kind, 5)] }

  track_events = []
  last_tick = 0
  timed.each do |entry|
    tick = entry[0]
    kind = entry[1]
    delta = [tick - last_tick, 0].max
    bytes = case kind
            when :bank
              [0xB0 | channel, 0x00, entry[2] & 0x7f].pack("C*")
            when :prog
              [0xC0 | channel, entry[2]].pack("C*")
            when :cc
              entry[2].pack("C*")
            else
              status = kind == :on ? (0x90 | channel) : (0x80 | channel)
              [status, entry[2], entry[3]].pack("C*")
            end
    track_events << [delta, bytes]
    last_tick = tick
  end
  track_events << [0, [0xFF, 0x2F, 0x00].pack("C*")]

  track_data = track_events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  File.binwrite(path, header + track_chunk)
  [path, first_patch]
end

def write_smf_timed(path, timed, duration:, midi_fx: nil, channel: 0, lead_mode: false)
  midi_fx_automation(duration, midi_fx, channel: channel).each do |tick, bytes|
    timed << [tick, :cc, bytes]
  end
  kind_prio = { bank: 0, prog: 1, on: 2, cc: 3, off: 4 }
  timed.sort_by! { |tick, kind, *| [tick, kind_prio.fetch(kind, 5)] }

  track_events = []
  last_tick = 0
  timed.each do |entry|
    tick = entry[0]
    kind = entry[1]
    delta = [tick - last_tick, 0].max
    bytes = case kind
            when :bank
              [0xB0 | channel, 0x00, entry[2] & 0x7f].pack("C*")
            when :prog
              [0xC0 | channel, entry[2]].pack("C*")
            when :cc
              entry[2].pack("C*")
            else
              status = kind == :on ? (0x90 | channel) : (0x80 | channel)
              vel_mul = lead_mode ? 100 : 108
              vel_min = lead_mode ? 36 : 48
              vel = kind == :on ? entry[3] : 0
              vel = (vel.is_a?(Float) ? (vel.clamp(0.0, 1.0) * vel_mul).round.clamp(vel_min, 127) : vel)
              [status, entry[2], vel].pack("C*")
            end
    track_events << [delta, bytes]
    last_tick = tick
  end
  track_events << [0, [0xFF, 0x2F, 0x00].pack("C*")]

  track_data = track_events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  File.binwrite(path, header + track_chunk)
  path
end

def render_xlead_native_fm(path, pad_events, duration, cfg)
  return nil unless lead_morph_enabled? && fm_native_enabled?
  return nil if pad_events.empty?

  filters = []
  labels = []
  note_i = 0
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars_est = ((pad_events.last[0] / bar_p).ceil + 1)
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    patch = morph_lead_patch_for_chord(i)
    next unless chord && chord[:hz]&.any?
    arp_cfg = morph_lead_arp_cfg_for_chord(i, patch)
    chord_events = lead_arp_events_for_chord(time, velocity, chord, sustain, i, cfg, arp_cfg, patch,
                                             role: :xlead, n_bars_est: n_bars_est, skip_intro: false)
    next if chord_events.empty?
    ratio = fm_ratio_for_chord(i)
    mod_ratio_expr = fm_mod_ratio_expr(ratio[:m], ratio[:target_m], sustain, irrational: ratio[:irrational])
    chord_events.each do |(t, vel, ch, dur)|
      hz = ch[:hz].first
      next unless hz&.positive?
      base_idx = fm_index_from_velocity(vel, base_index: FM_INDEX_BASE_XLEAD, role: :xlead)
      mod_env = fm_mod_envelope(role: :xlead)
      index_expr = "(#{base_idx})*#{mod_env}"
      drift = "1"
      body = native_fm_waveform_body(hz, index_expr: index_expr, bloom: 0.22, drift: drift,
                                     feedback: FM_FEEDBACK_DEFAULT, phase_seed: note_i * 0.71,
                                     mod_ratio_expr: mod_ratio_expr)
      amp = (vel * 0.12).round(5)
      atk = 0.003
      rel = (1.0 / [dur, 0.02].max).round(3)
      env = "min(1,pow(t/#{atk},0.9))*exp(-t*#{rel})"
      expr = "#{amp}*#{env}*#{body}"
      delay = [(t * 1000.0).round, 0].max
      label = "xl#{note_i}"
      filters << "aevalsrc=exprs='#{expr}|#{expr}':d=#{dur.round(4)}:s=#{PAD_RENDER_SAMPLE_RATE}," \
                 "adelay=#{delay}|#{delay}[#{label}]"
      labels << "[#{label}]"
      note_i += 1
    end
  end
  return nil if labels.empty?

  filters << "#{labels.join}amix=inputs=#{labels.length}:duration=longest:normalize=0," \
             "atrim=0:#{duration},highpass=f=180,lowpass=f=8200,alimiter=limit=0.94:level_out=0.92[xlead]"
  sh! "ffmpeg", "-y", "-filter_complex", filters.join(";"), "-map", "[xlead]",
      "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", path
  path
end

def blend_xlead_stems(destination, fs_path, native_path, duration)
  return fs_path if native_path.nil? || !File.exist?(native_path)
  return native_path if fs_path.nil? || !File.exist?(fs_path)
  tmp = "#{destination}.blend.wav"
  sh! "ffmpeg", "-y", "-i", fs_path, "-i", native_path,
      "-filter_complex",
      "[0:a][1:a]amix=inputs=2:weights=1.0 #{FM_XLEAD_NATIVE_MIX}:duration=longest:normalize=0," \
      "alimiter=limit=0.96:level_out=0.96[out]",
      "-map", "[out]", "-t", duration.to_s, "-c:a", "pcm_s16le", tmp
  FileUtils.mv(tmp, destination)
  destination
end

def render_xlead_morph_fluidsynth(path, pad_events, duration, cfg)
  return nil unless lead_morph_enabled? && fluidsynth_pad_available?
  return nil if pad_events.empty?

  timed = []
  first_patch = nil
  beat_p = 60.0 / cfg[:bpm]
  bar_p = beat_p * 4.0
  n_bars_est = ((pad_events.last[0] / bar_p).ceil + 1)
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    patch = morph_lead_patch_for_chord(i)
    next unless patch && chord && chord[:hz]&.any?
    first_patch ||= patch
    voice = patch_voice_for(patch)
    arp_cfg = morph_lead_arp_cfg_for_chord(i, patch)
    chord_events = lead_arp_events_for_chord(time, velocity, chord, sustain, i, cfg, arp_cfg, patch,
                                             role: :xlead, n_bars_est: n_bars_est, skip_intro: false)
    next if chord_events.empty?
    on_tick = (time * SMF_TICKS_PER_SECOND).round
    timed << [on_tick, :bank, voice[:bank]]
    timed << [on_tick, :prog, voice[:program]]
    chord_events.each do |(t, vel, ch, dur)|
      note = hz_to_midi(ch[:hz].first).round.clamp(0, 127)
      note_on = (t * SMF_TICKS_PER_SECOND).round
      note_off = (note_on + (dur * SMF_TICKS_PER_SECOND)).round
      v = (vel.clamp(0.0, 1.0) * 100).round.clamp(40, 127)
      timed << [note_on, :on, note, v]
      timed << [note_off, :off, note, 0]
    end
  end
  return nil if timed.empty?

  midi_path = "#{path}.smf.mid"
  write_smf_timed(midi_path, timed, duration: duration, midi_fx: MIDI_FX_LEAD, lead_mode: true)
  fs_gain = first_patch&.fetch(:fs_gain, 1.38) || 1.38
  sh! "fluidsynth", "-ni", "-g", fs_gain.to_s, "-F", path, "-r", SAMPLE_RATE.to_s, pad_soundfont_path, midi_path
  FileUtils.rm_f(midi_path)
  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  boost_db = (LEAD_TARGET_RMS_DB - measured_rms).clamp(0.0, 26.0)
  sh! "ffmpeg", "-y", "-i", path, "-af", lead_post_fx_chain(first_patch, duration, boost_db),
      "-c:a", "pcm_s16le", "#{path}.xlead.wav"
  FileUtils.mv("#{path}.xlead.wav", path)
  path
end

def write_pad_smf(path, pad_events, program: PAD_GM_PROGRAM, bank: 0, duration: nil, midi_fx: nil, patch: nil,
                    role: :ep)
  cfg = dilla_resolve_config
  events = pad_midi_events_for_layer(pad_events, cfg, patch, role: role, duration: duration || 0)
  fx = midi_fx || resolve_midi_fx_for(patch, role: role)
  write_smf(path, events, program: program, bank: bank, duration: duration, midi_fx: fx)
end

PAD_TARGET_RMS_DB = -17.5

# Lazily, silently fetches EXTERNAL_SOUNDFONTS/EXTERNAL_DRUM_KIT_REPO on
# first use so nothing needs to be typed/remembered — but any network
# hiccup (offline, GitHub down) must never break a render, hence the
# broad rescue (fetch_assets! can raise SystemExit via abort on a missing
# curl/git, not just StandardError).
def ensure_external_assets_lazy!
  return @external_assets_checked if defined?(@external_assets_checked)
  @external_assets_checked =
    begin
      sf_dir = File.expand_path("~/.cache/dilla-soundfonts")
      have_all = EXTERNAL_SOUNDFONTS.keys.all? { |n| File.exist?(File.join(sf_dir, n)) } &&
                 Dir.exist?(EXTERNAL_DRUM_KIT_CACHE)
      fetch_assets! unless have_all
      true
    rescue StandardError, SystemExit
      false
    end
end

# galaxy-electric-pianos.sf2's presets are scattered across non-standard
# banks (measured via its phdr chunk): "Galaxy EP 1..8" live at
# bank=2..5, program=4 or 5 — not bank 0, hence the explicit bank list
# rather than a GM program number.
EXTERNAL_EP_BANKS = [2, 3, 4, 5].freeze

def resolve_ep_voice
  if ENV["DILLA_PAD_PROGRAM"]
    return { sf2: pad_soundfont_path, bank: 0, program: PAD_GM_PROGRAM, patch: nil }
  end
  patch_voice_for(@render_ep_patch) || begin
    program = EP_GM_PROGRAMS.sample
    { sf2: pad_soundfont_path, bank: 0, program: program, patch: nil }
  end
end

# Lead voice from SYNTH_PATCH_CATALOG — supersaw, prophet, FM bell, etc.
def resolve_lead_voice
  if ENV["DILLA_LEAD_PROGRAM"]
    return { sf2: pad_soundfont_path, bank: 0, program: ENV["DILLA_LEAD_PROGRAM"].to_i, patch: @render_lead_patch }
  end
  patch_voice_for(@render_lead_patch) || { sf2: pad_soundfont_path, bank: 0, program: LEAD_GM_PROGRAMS.sample, patch: nil }
end

def resolve_warm_voice
  if ENV["DILLA_WARM_PAD_PROGRAM"]
    return { sf2: pad_soundfont_path, bank: 0, program: ENV["DILLA_WARM_PAD_PROGRAM"].to_i, patch: @render_warm_patch }
  end
  patch_voice_for(@render_warm_patch) || { sf2: pad_soundfont_path, bank: 0, program: WARM_PAD_GM_PROGRAMS.sample, patch: nil }
end

def resolve_texture_voice
  patch_voice_for(@render_texture_patch)
end

# Rhodes alone (GM 4) is Dilla's half of the research (Rhodes/Wurlitzer);
# blending in a warm analog pad voice covers the other half — both artists'
# keyboards used real analog synths (Minimoog Voyager, Prophet 6/5, Yamaha
# CS-60) alongside the electric piano, not instead of it. A different pair
# picked per render rather than always the same two programs. The EP voice
# also has a 40% chance of pulling from the fetched Galaxy Electric Pianos
# soundfont instead of GeneralUser-GS's single Rhodes patch.
def render_pad_morph_fluidsynth(path, pad_events, duration)
  @render_used_fluidsynth_pad = true
  ep_path = "#{path}.ep.wav"
  warm_path = "#{path}.warm.wav"
  texture_path = "#{path}.texture.wav"
  ep_mix = 1.0
  warm_mix = 0.68
  ep_midi = "#{ep_path}.smf.mid"
  _, ep_anchor = write_smf_morph(ep_midi, pad_events, duration: duration, role: :ep, midi_fx: MIDI_FX_PAD_EP)
  ep_mix = ep_anchor&.fetch(:mix, 1.0) || 1.0
  sh! "fluidsynth", "-ni", "-g", (ep_anchor&.fetch(:fs_gain, 1.5) || 1.5).to_s,
      "-F", ep_path, "-r", SAMPLE_RATE.to_s, pad_soundfont_path, ep_midi
  FileUtils.rm_f(ep_midi)

  warm_midi = "#{warm_path}.smf.mid"
  _, warm_anchor = write_smf_morph(warm_midi, pad_events, duration: duration, role: :warm,
                                   midi_fx: MIDI_FX_PAD_WARM)
  warm_mix = warm_anchor&.fetch(:mix, 0.68) || 0.68
  sh! "fluidsynth", "-ni", "-g", (warm_anchor&.fetch(:fs_gain, 1.5) || 1.5).to_s,
      "-F", warm_path, "-r", SAMPLE_RATE.to_s, pad_soundfont_path, warm_midi
  FileUtils.rm_f(warm_midi)

  texture_voice = resolve_texture_voice
  if texture_voice
    texture_midi = "#{texture_path}.smf.mid"
    write_pad_smf(texture_midi, pad_events, program: texture_voice[:program], bank: texture_voice[:bank],
                  duration: duration, patch: texture_voice[:patch], role: :texture)
    sh! "fluidsynth", "-ni", "-g", (texture_voice[:patch]&.fetch(:fs_gain, 1.2) || 1.2).to_s,
        "-F", texture_path, "-r", SAMPLE_RATE.to_s, texture_voice[:sf2], texture_midi
    FileUtils.rm_f(texture_midi)
  end

  inputs = ["-i", ep_path, "-i", warm_path]
  filt = "[0:a]apad=whole_dur=#{duration}[ep];" \
         "[1:a]apad=whole_dur=#{duration}[warmsrc];" \
         "[warmsrc]asplit=2[w1][w2];" \
         "[w1]asetrate=44100*1.0022,aresample=44100[wup];" \
         "[w2]asetrate=44100*0.9978,aresample=44100[wdown];" \
         "[wup][wdown]amix=inputs=2:weights=0.52 0.52:duration=first:normalize=0[wdetuned];" \
         "[ep][wdetuned]amix=inputs=2:weights=#{ep_mix} #{warm_mix}:duration=first:normalize=0[blend]"
  map_label = "[blend]"
  if texture_voice && File.exist?(texture_path)
    filt += ";[2:a]apad=whole_dur=#{duration}[tex];[blend][tex]amix=inputs=2:weights=1.0 #{texture_voice[:patch]&.fetch(:mix, 0.15) || 0.15}:duration=first:normalize=0[blend2]"
    map_label = "[blend2]"
    inputs << "-i" << texture_path
  end
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filt, "-map", map_label, "-c:a", "pcm_s16le", path
  FileUtils.rm_f(ep_path)
  FileUtils.rm_f(warm_path)
  FileUtils.rm_f(texture_path)
  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  boost_db = (PAD_TARGET_RMS_DB - measured_rms).clamp(0.0, 18.0)
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "equalizer=f=280:t=o:w=1:g=1.2,equalizer=f=1800:t=h:w=1200:g=0.7," \
      "volume=#{boost_db.round(2)}dB,alimiter=limit=0.95:level_out=0.96",
      "-c:a", "pcm_s16le", "#{path}.pad.wav"
  FileUtils.mv("#{path}.pad.wav", path)
  path
end

def pad_layer_specs_for_voice(voice)
  stack = PAD_LAYER_STACKS[voice]
  return stack if stack && ENV.fetch("PAD_LAYERS", "1") != "0"
  preset = PAD_VOICE_PRESETS[voice] || PAD_VOICE_PRESETS[:stack_soul]
  layers = []
  layers << { id: preset[:ep], mix: 1.15, role: :ep } if preset[:ep]
  layers << { id: preset[:warm], mix: 0.85, role: :warm } if preset[:warm]
  layers << { id: preset[:warm2], mix: 0.55, role: :warm } if preset[:warm2]
  layers << { id: preset[:texture], mix: 0.3, role: :texture } if preset[:texture]
  layers
end

def render_one_pad_layer!(voice_path, pad_events, duration, voice, role)
  midi_path = "#{voice_path}.smf.mid"
  write_pad_smf(midi_path, pad_events, program: voice[:program], bank: voice[:bank],
                duration: duration, patch: voice[:patch], role: role)
  fs_gain = voice[:patch]&.fetch(:fs_gain, 1.5) || 1.5
  sh! "fluidsynth", "-ni", "-g", fs_gain.to_s, "-F", voice_path, "-r", SAMPLE_RATE.to_s, voice[:sf2], midi_path
  FileUtils.rm_f(midi_path)
  return unless voice[:patch]&.dig(:fx) && tool_available?("ffmpeg")
  fx_tmp = "#{voice_path}.fx.wav"
  begin
    sh! "ffmpeg", "-y", "-i", voice_path, "-af", voice[:patch][:fx], "-c:a", "pcm_s16le", fx_tmp
    FileUtils.mv(fx_tmp, voice_path)
  rescue StandardError => e
    warn "patch fx skipped (#{voice[:patch][:id]}): #{e.message}"
    FileUtils.rm_f(fx_tmp)
  end
end

def render_pad_via_fluidsynth(path, pad_events, duration)
  # Morph path is opt-in only — multi-layer stack is the quality default.
  return render_pad_morph_fluidsynth(path, pad_events, duration) if synth_morph_enabled? && ENV["PAD_LAYERS"] == "0"
  @render_used_fluidsynth_pad = true
  voice_key = ENV["PAD_VOICE"]&.downcase&.to_sym
  specs = pad_layer_specs_for_voice(voice_key)
  if specs.nil? || specs.empty?
    # Fallback 2-layer
    specs = [
      { id: :rhodes_cafe_warm, mix: 1.15, role: :ep },
      { id: :moog_model_d, mix: 0.85, role: :warm },
      { id: :prophet_5_pad, mix: 0.55, role: :warm }
    ]
  end
  # Always force at least EP + two warm beds when stack requested.
  if ENV.fetch("PAD_LAYERS", "1") != "0" && specs.length < 3
    specs = PAD_LAYER_STACKS[:stack_soul]
  end

  rendered = []
  specs.each_with_index do |spec, i|
    patch = synth_patch_by_id(spec[:id])
    next unless patch
    voice = patch_voice_for(patch) || resolve_ep_voice
    voice = voice.merge(patch: patch) if voice[:patch].nil?
    layer_path = "#{path}.L#{i}.wav"
    render_one_pad_layer!(layer_path, pad_events, duration, voice, spec[:role] || :warm)
    next unless File.file?(layer_path)
    # Unison detune on warm layers only (width without mush).
    if spec[:role] == :warm && i.positive?
      det = "#{layer_path}.det.wav"
      sh! "ffmpeg", "-y", "-i", layer_path, "-filter_complex",
          "[0:a]asplit=2[a][b];[a]asetrate=#{SAMPLE_RATE}*1.0018,aresample=#{SAMPLE_RATE}[u];" \
          "[b]asetrate=#{SAMPLE_RATE}*0.9982,aresample=#{SAMPLE_RATE}[d];" \
          "[u][d]amix=inputs=2:weights=0.5 0.5:normalize=0",
          "-c:a", "pcm_s16le", det
      FileUtils.mv(det, layer_path) if File.file?(det)
    end
    rendered << [layer_path, spec[:mix].to_f]
  end
  if rendered.empty?
    return render_native_pad_wav(path, pad_events, duration)
  end
  if rendered.length == 1
    FileUtils.mv(rendered[0][0], path)
  else
    inputs = rendered.flat_map { |(p, _)| ["-i", p] }
    labels = rendered.each_index.map { |i| "p#{i}" }
    filt_parts = rendered.each_with_index.map do |(_, mix), i|
      "[#{i}:a]apad=whole_dur=#{duration},volume=#{mix}[#{labels[i]}]"
    end
    weights = rendered.map { |(_, m)| m }.join(" ")
    filt = "#{filt_parts.join(';')};" \
           "#{labels.map { |l| "[#{l}]" }.join}amix=inputs=#{rendered.length}:weights=#{weights}:" \
           "duration=first:normalize=0[blend]"
    sh! "ffmpeg", "-y", *inputs, "-filter_complex", filt, "-map", "[blend]", "-c:a", "pcm_s16le", path
    rendered.each { |(p, _)| FileUtils.rm_f(p) }
  end
  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  boost_db = (PAD_TARGET_RMS_DB - measured_rms).clamp(0.0, 20.0)
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "equalizer=f=280:t=o:w=1:g=1.6,equalizer=f=900:t=o:w=1.2:g=0.8," \
      "equalizer=f=2200:t=h:w=1400:g=1.0,volume=#{boost_db.round(2)}dB," \
      "alimiter=limit=0.95:level_out=0.97",
      "-c:a", "pcm_s16le", "#{path}.pad.wav"
  FileUtils.mv("#{path}.pad.wav", path)
  path
end

# 81 Sawtooth (original), 87 Lead 8 "bass+lead" (GM's own name traces to the
# classic Prophet-5 "BigLead" patch — literally the historical big-lead
# archetype), 84 Lead 5 Charang (aggressive/bright, cuts through), 86 Lead 7
# Fifths (built-in parallel fifths give arps instant harmonic width free).
LEAD_GM_PROGRAMS = [81, 87, 84, 86].freeze
# Hotter lead target so arps cut over multi-layer pads.
LEAD_TARGET_RMS_DB = -14.5

def invert_motif(motif)
  top = motif.max
  motif.map { |d| top - d }
end

# Leitmotif seeded from the progression's own opening chord — stable for
# a given piece, so the lead states one real idea and develops it
# (inversion/retrograde/augmentation) instead of generating a fresh,
# unrelated arp pattern at every chord change.
def leitmotif_for(pad_events)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    hook = @composition_session.motifs.find { |m| m.id == "hook" }
    return hook.degrees_for_playback if hook
  end
  seed_source = pad_events.first&.dig(2, :name).to_s
  rng = Random.new(seed_source.hash.abs % 100_000)
  length = [3, 4].sample(random: rng)
  Array.new(length) { rng.rand(4) }
end

# A real arpeggiator, not a held note: steps through the chord's own tones
# (up an octave, lead register). The pattern is a motivic development of
# one fixed leitmotif (stated, inverted, reversed, augmented) rather than
# an independent pattern per chord — plus a quieter call-and-response
# "answer" voice on alternating phrases, an octave down, offset in time.
def lead_events_from_pads(pad_events, duration: nil, n_bars: nil)
  cfg = dilla_resolve_config
  scale = lead_events_scale_arp(pad_events, cfg, duration: duration, n_bars: n_bars)
  arp_cfg = lead_arp_cfg_for(@render_lead_patch)
  arp = lead_arp_events(pad_events, cfg, arp_cfg)
  creative = lead_events_creative(pad_events, cfg, duration: duration, n_bars: n_bars)
  { scale: scale, lead_arp: arp, creative: creative }
end

def resolve_scale_lead_voice
  if ENV["DILLA_SCALE_LEAD_PROGRAM"]
    return { sf2: pad_soundfont_path, bank: 0, program: ENV["DILLA_SCALE_LEAD_PROGRAM"].to_i,
             patch: @render_scale_lead_patch }
  end
  patch_voice_for(@render_scale_lead_patch) ||
    patch_voice_for(@render_lead_patch) ||
    { sf2: pad_soundfont_path, bank: 0, program: LEAD_GM_PROGRAMS.sample, patch: nil }
end

# Interesting default lead FX — delay, chorus, subtle phaser, air shelf, soft drive.
LEAD_FX_RICH_DEFAULT = [
  "highpass=f=180",
  "equalizer=f=2800:t=o:w=1.4:g=2.8",
  "equalizer=f=5200:t=h:w=1.2:g=1.6",
  "chorus=0.48:0.68:36|48:0.22|0.18:0.26|0.22:1.1|1.35",
  "aecho=0.48:0.42:140|280:0.28|0.14",
  "aphaser=speed=0.14:decay=0.45",
  "vibrato=f=0.32:d=0.011",
  "lowpass=f=6200:width_type=q:width=0.85"
].join(",").freeze

LEAD_FX_VARIANTS = [
  LEAD_FX_RICH_DEFAULT,
  "highpass=f=200,tremolo=f=4.2:d=0.08,chorus=0.4:0.6:30|40:0.18|0.14:0.22|0.18:1.0|1.25,aecho=0.42:0.36:100|190:0.24|0.12,lowpass=f=5400",
  "highpass=f=160,aecho=0.55:0.5:180|320:0.32|0.16,aphaser=speed=0.2:decay=0.5,equalizer=f=3200:t=o:w=1.3:g=3.2,lowpass=f=7000",
  "highpass=f=220,acrusher=bits=12:samples=1.5:mix=0.06,chorus=0.52:0.72:40|52:0.24|0.2:0.28|0.24:1.15|1.4,aecho=0.4:0.35:90|160:0.2|0.1,lowpass=f=5000",
  "highpass=f=190,vibrato=f=0.55:d=0.016,tremolo=f=0.35:d=0.06,aecho=0.5:0.44:150|260:0.26|0.14,lowpass=f=5800"
].freeze

def lead_post_fx_chain(patch, duration, boost_db)
  base = "volume=#{boost_db.round(2)}dB"
  patch_fx = patch&.dig(:fx)
  # Blend patch identity FX with a rotating rich chain so every take has motion.
  variant = LEAD_FX_VARIANTS[((@render_seed || 0) + Process.pid) % LEAD_FX_VARIANTS.length]
  rich = ENV.fetch("LEAD_FX_RICH", "1") != "0"
  body = if patch_fx && !patch_fx.empty?
           rich ? "#{patch_fx},#{variant}" : patch_fx
         else
           rich ? variant : LEAD_FX_RICH_DEFAULT
         end
  [base, body, "apad=whole_dur=#{duration}", "alimiter=limit=0.94:level_out=0.97"].join(",")
end

HARMONIC_STEM_MIX = {
  pads:          { volume: 1.35, weight: 1.7 },
  tones:         { volume: 0.72, weight: 0.55 },
  harmony_lead:  { volume: 1.15, weight: 0.72 },
  scale_lead:    { volume: 1.2, weight: 0.78 },
  lead_arp:      { volume: 1.45, weight: 1.05 },
  lead:          { volume: 1.1, weight: 0.55 },
  xlead:         { volume: 0.74, weight: 0.36 }
}.freeze

def harmonic_stem_mix_value(key, field)
  env_key = "HARMONIC_#{key.to_s.upcase}_#{field.to_s.upcase}"
  raw = ENV[env_key]
  return raw.to_f if raw && !raw.empty?
  HARMONIC_STEM_MIX.dig(key, field) || 1.0
end

def mix_harmonic_wav_stems(destination, duration, **stem_paths)
  lanes = HARMONIC_STEM_MIX.filter_map do |key, _mix|
    path = stem_paths[key]
    next unless path && File.exist?(path)
    [key, path, harmonic_stem_mix_value(key, :volume), harmonic_stem_mix_value(key, :weight)]
  end
  return false if lanes.length < 2

  filter_labels = []
  mix_in = []
  lanes.each_with_index do |(_key, _path, volume, _weight), idx|
    label = "h#{idx}"
    filter_labels << "[#{idx}:a]volume=#{volume}[#{label}]"
    mix_in << "[#{label}]"
  end
  weights = lanes.map { |l| l[3] }.join(" ")
  filter = "#{filter_labels.join(';')};" \
             "#{mix_in.join}amix=inputs=#{lanes.length}:weights=#{weights}:duration=longest:normalize=0," \
             "aresample=#{SAMPLE_RATE},alimiter=limit=0.96:level_out=0.98[harmonic]"
  args = ["ffmpeg", "-y"]
  lanes.each { |(_, path)| args << "-i" << path }
  sh!(*args, "-filter_complex", filter, "-map", "[harmonic]",
      "-t", duration.to_s, "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", destination)
  lanes.drop(2).each { |(_, path)| FileUtils.rm_f(path) }
  true
end

def render_lead_via_fluidsynth(path, lead_events, duration, scale_arp: false)
  return nil if lead_events.empty? || !fluidsynth_pad_available?
  midi_path = "#{path}.smf.mid"
  lead_voice = scale_arp ? resolve_scale_lead_voice : resolve_lead_voice
  patch = lead_voice[:patch] || (scale_arp ? @render_scale_lead_patch : @render_lead_patch)
  role = scale_arp ? :scale_lead : :lead
  write_smf(midi_path, lead_events, program: lead_voice[:program], bank: lead_voice[:bank],
            duration: duration, midi_fx: resolve_midi_fx_for(patch, role: role), lead_mode: true)
  fs_gain = lead_voice[:patch]&.fetch(:fs_gain, 1.3) || 1.3
  sh! "fluidsynth", "-ni", "-g", fs_gain.to_s, "-F", path, "-r", SAMPLE_RATE.to_s, lead_voice[:sf2], midi_path
  FileUtils.rm_f(midi_path)
  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  target_db = scale_arp ? (LEAD_TARGET_RMS_DB + 1.5) : LEAD_TARGET_RMS_DB
  boost_db = (target_db - measured_rms).clamp(0.0, 24.0)
  patch = lead_voice[:patch] || (scale_arp ? @render_scale_lead_patch : @render_lead_patch)
  sh! "ffmpeg", "-y", "-i", path, "-af", lead_post_fx_chain(patch, duration, boost_db),
      "-c:a", "pcm_s16le", "#{path}.lead.wav"
  FileUtils.mv("#{path}.lead.wav", path)
  path
end

def render_harmonic_wav(path, pad_events, chop_events, bass_events, duration, melody_events: [], cfg: nil, dfam_events: nil)
  cfg ||= dilla_resolve_config
  pick_synth_patches!(cfg) unless @render_ep_patch
  @render_used_fluidsynth_pad = false
  tones_path = "#{path}.tones.wav"
  pads_path = "#{path}.pads.wav"
  lead_path = "#{path}.lead.wav"
  lead_arp_path = "#{path}.lead_arp.wav"
  xlead_path = "#{path}.xlead.wav"
  harmony_lead_path = "#{path}.harmony_lead.wav"
  scale_lead_path = "#{path}.scale_lead.wav"
  if fluidsynth_pad_available?
    render_pad_via_fluidsynth(pads_path, pad_events, duration)
  else
    render_native_pad_wav(pads_path, pad_events, duration)
  end
  n_bars_est = (duration / ((60.0 / cfg[:bpm]) * 4.0)).ceil
  # One clean melodic lead by default — scale/creative layers turned the top line into soup.
  scale_on = lead_arp_enabled? && ENV.fetch("SCALE_LEAD", "0") != "0"
  creative_on = lead_arp_enabled? && ENV.fetch("CREATIVE_LEAD", "0") != "0"
  scale_events = scale_on ? lead_events_scale_arp(pad_events, cfg, duration: duration, n_bars: n_bars_est) : []
  lead_arp_cfg = lead_arp_cfg_for(@render_lead_patch)
  lead_arp_ev = lead_arp_enabled? ? lead_arp_events(pad_events, cfg, lead_arp_cfg) : []
  harmony_lead_cfg = harmony_lead_cfg_for(@render_scale_lead_patch)
  insight = instance_variable_defined?(:@progression_insight) ? @progression_insight : nil
  harmony_lead_ev = harmony_lead_enabled? && ENV.fetch("HARMONY_LEAD", "0") != "0" ?
                    harmony_lead_events(pad_events, cfg, harmony_lead_cfg, progression_insight: insight) : []
  creative_events = creative_on ? lead_events_creative(pad_events, cfg, duration: duration, n_bars: n_bars_est) : []
  scale_lead_rendered = scale_events.any? ? render_lead_via_fluidsynth(scale_lead_path, scale_events, duration, scale_arp: true) : nil
  harmony_lead_rendered = harmony_lead_ev.any? ? render_lead_via_fluidsynth(harmony_lead_path, harmony_lead_ev, duration, scale_arp: true) : nil
  lead_arp_rendered = lead_arp_ev.any? ? render_lead_via_fluidsynth(lead_arp_path, lead_arp_ev, duration) : nil
  xlead_rendered = nil
  if lead_morph_enabled?
    xlead_fs = render_xlead_morph_fluidsynth(xlead_path, pad_events, duration, cfg)
    xlead_native = render_xlead_native_fm("#{xlead_path}.native.wav", pad_events, duration, cfg)
    xlead_rendered = blend_xlead_stems(xlead_path, xlead_fs, xlead_native, duration)
    FileUtils.rm_f("#{xlead_path}.native.wav")
  end
  lead_rendered = creative_events.any? ? render_lead_via_fluidsynth(lead_path, creative_events, duration) : nil
  # Karplus-Strong plucked-string accent on each chord's root — a genuinely
  # new instrument timbre (real physical-modeling algorithm, not another
  # oscillator/soundfont voice), pre-rendered per chord since the algorithm
  # itself needs a contiguous buffer, then windowed into the tones stream
  # the same way chop/melody events already are.
  pluck_buffers = pad_events.filter_map do |(t, v, chord, _sustain)|
    next unless chord && chord[:hz]&.any?
    [t, v, karplus_strong_pluck(chord[:hz].min, 1.1, seed: chord[:name].to_s.hash.abs % 100_000)]
  end
  write_stereo_chunks(tones_path, duration) do |chunk_start, chunk_frames, left, right|
    pluck_buffers.each do |(t, v, buf)|
      event_frame = (t * SAMPLE_RATE).round
      window = overlap_window(event_frame, buf.length, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      count.times do |i|
        sample = buf[source_offset + i] * v * 0.16
        left[local_start + i] += sample
        right[local_start + i] += sample
      end
    end
    chop_events.each do |(t, v, chord)|
      hz_list = chop_hz(chord)
      next if hz_list.empty?
      event_frame = (t * SAMPLE_RATE).round
      total = (0.28 * SAMPLE_RATE).round
      window = overlap_window(event_frame, total, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      frequency = hz_list[((t * 10).to_i) % hz_list.length]
      mix_sine!(left, right, local_start, count, frequency, v * 0.13,
                decay: 2.0, mod_hz: 0.45, source_offset:)
    end

    melody_events.each do |(t, v, hz)|
      event_frame = (t * SAMPLE_RATE).round
      total = (0.18 * SAMPLE_RATE).round
      window = overlap_window(event_frame, total, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      frequency = hz.is_a?(Numeric) ? hz : MELODY_CHOP_HZ.first
      count.times do |i|
        tt = (source_offset + i).to_f / SAMPLE_RATE
        sample = v * 0.11 * Math.exp(-tt * 8.5) * Math.sin(2 * Math::PI * frequency * tt)
        left[local_start + i] += sample * 0.55
        right[local_start + i] += sample * 0.45
      end
    end

    bass_events.each do |hit|
      t, v = hit[0], hit[1]
      root = hit[2].is_a?(Numeric) ? hit[2] : 43.65
      slide_from = hit[4].is_a?(Numeric) ? hit[4] : nil
      total = [((hit[3] || BASS_SUSTAIN_SEC) * SAMPLE_RATE).round, 1].max
      event_frame = (t * SAMPLE_RATE).round
      window = overlap_window(event_frame, total, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      slide_portion = bass_slide_enabled? && slide_from ? 0.38 : 0.0
      count.times do |i|
        tt = (source_offset + i).to_f / SAMPLE_RATE
        lfo = 0.03 * Math.sin(2 * Math::PI * 0.12 * tt)
        progress = i.to_f / [count - 1, 1].max
        freq = if slide_portion.positive? && progress < slide_portion
                 slide_from + (root - slide_from) * (progress / slide_portion)
               else
                 root
               end
        sample = v * 0.30 * Math.exp(-tt * BASS_DECAY_RATE) *
                 Math.sin(2 * Math::PI * freq * (1.0 + lfo) * tt)
        left[local_start + i] += sample
        right[local_start + i] += sample
      end
    end
  end
  # Balance pads and tones (chop+melody+bass) independently before mixing —
  # a shared limiter meant a loud bass transient in "tones" ducked the pad
  # chords along with it. Static gain staging (volume=), not a limiter per
  # stem, does that same job with zero dynamic/gain-reduction interaction —
  # a limiter's job is peak safety, and stacking one per stem plus another
  # on the combine (mastering-engineer critique: too many cascaded limiter
  # stages loses transient definition) bought nothing a plain gain match
  # didn't already cover. One limiter at the combine stage remains as the
  # actual safety net; master_bus_filters is the real mastering-stage limit
  # downstream.
  mix_harmonic_wav_stems(path, duration,
                         pads: pads_path, tones: tones_path,
                         harmony_lead: (harmony_lead_rendered ? harmony_lead_path : nil),
                         scale_lead: (scale_lead_rendered ? scale_lead_path : nil),
                         lead_arp: (lead_arp_rendered ? lead_arp_path : nil),
                         xlead: (xlead_rendered ? xlead_path : nil),
                         lead: (lead_rendered ? lead_path : nil))
  FileUtils.rm_f(pads_path)
  FileUtils.rm_f(tones_path)
  if dfam_events&.any?
    dfam_path = "#{path}.dfam.wav"
    render_dfam_wav(dfam_path, dfam_events, duration)
    tmp = "#{path}.dfam_mix.wav"
    sh! "ffmpeg", "-y", "-i", path, "-i", dfam_path,
        "-filter_complex", "[0:a][1:a]amix=inputs=2:weights=1.0 0.26:duration=first:normalize=0,alimiter=limit=0.96[out]",
        "-map", "[out]", "-t", duration.to_s, "-c:a", "pcm_s16le", tmp
    FileUtils.mv(tmp, path)
    FileUtils.rm_f(dfam_path)
  end
  warm_dilla_pad_post(path, cfg: cfg || dilla_resolve_config)
end

def write_stereo_wav(path, left, right)
  frames = [left.length, right.length].min
  pcm = (0...frames).flat_map { |i| [left[i], right[i]] }.pack("e*")
  stdin, stdout, stderr, wait = Open3.popen3(
    "ffmpeg", "-y", "-f", "f32le", "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-i", "-",
    "-c:a", "pcm_s16le", path
  )
  stdin.write(pcm)
  stdin.close
  err = stderr.read
  abort "wav write failed: #{err}" unless wait.value.success?
  path
end

def mix_sample!(left, right, sample, frame, vel, pan = 0.0)
  sample.each_with_index do |s, i|
    idx = frame + i
    break if idx >= left.length
    v = s * vel
    left[idx]  += v * (0.5 - pan * 0.35)
    right[idx] += v * (0.5 + pan * 0.35)
  end
end

def render_sample_bus(events, duration, kit, mapping)
  frames = (duration * SAMPLE_RATE).ceil + SAMPLE_RATE
  left  = Array.new(frames, 0.0)
  right = Array.new(frames, 0.0)
  mapping.each do |event_key, default_key|
    events.fetch(event_key, []).each do |hit|
      t, v = hit[0], hit[1]
      sk = hit[2].is_a?(Symbol) ? hit[2] : default_key
      pan = hit[3].is_a?(Numeric) ? hit[3].to_f : 0.0
      mix_sample!(left, right, kit.fetch(sk), (t * SAMPLE_RATE).round, v, pan)
    end
  end
  peak = left.zip(right).flat_map { |l, r| [l.abs, r.abs] }.max || 1.0
  if peak > 0.98
    gain = 0.92 / peak
    left.map!  { |s| s * gain }
    right.map! { |s| s * gain }
  end
  [left, right]
end

# Measured (not guessed) via zero-crossing analysis of the sample body,
# post-attack — the "43" in the filename doesn't reliably encode a MIDI
# note. Only sample keys listed here get pitch-shifted to a target hz;
# everything else (kick/snare/hat/ghost) plays at native pitch.
SAMPLE_NATURAL_HZ = { bass_43: 49.0, cowbell: 670.0 }.freeze

def render_sample_bus_wav(path, events, duration, kit, mapping)
  write_stereo_chunks(path, duration) do |chunk_start, chunk_frames, left, right|
    mapping.each do |event_key, default_key|
      events.fetch(event_key, []).each do |hit|
        time, velocity = hit[0], hit[1]
        target_hz = hit[2].is_a?(Numeric) ? hit[2] : nil
        sample_key = hit[2].is_a?(Symbol) ? hit[2] : default_key
        pan = hit[3].is_a?(Numeric) ? hit[3].to_f : 0.0
        sample = kit.fetch(sample_key)
        natural_hz = SAMPLE_NATURAL_HZ[sample_key]
        # Sample-based bass ignored bass_root entirely — every hit played
        # samples/drums/bass_43.wav at its own fixed pitch regardless of the
        # actual chord, so the loudest, most frequent low-end voice in the
        # mix never followed the harmony. Resample (classic MPC-style pitch
        # shift) toward the chord root instead.
        ratio = (target_hz && natural_hz) ? (target_hz / natural_hz) : 1.0
        src_len = ratio == 1.0 ? sample.length : (sample.length / ratio).floor
        event_frame = (time * SAMPLE_RATE).round
        window = overlap_window(event_frame, src_len, chunk_start, chunk_frames)
        next unless window
        local_start, source_offset, count = window
        count.times do |i|
          value =
            if ratio == 1.0
              sample[source_offset + i] * velocity
            else
              src_pos = (source_offset + i) * ratio
              i0 = src_pos.floor
              frac = src_pos - i0
              s0 = sample[i0] || 0.0
              s1 = sample[i0 + 1] || s0
              (s0 + (s1 - s0) * frac) * velocity
            end
          left[local_start + i] += value * (0.5 - pan * 0.35)
          right[local_start + i] += value * (0.5 + pan * 0.35)
        end
      end
    end
  end
end

def gate_expr(hits, hold: 0.38, scale: 1.0)
  parts = hits.map do |hit|
    t, v = hit[0], hit[1]
    "between(t,#{t.round(4)},#{(t + hold).round(4)})*#{(v * scale).round(4)}"
  end
  parts.empty? ? "0" : parts.join("+")
end

def pad_gate_expr(pad_events)
  parts = pad_events.map do |(t, v, _chord, sustain)|
    "between(t,#{t.round(4)},#{(t + sustain).round(4)})*#{(v * 0.85).round(4)}"
  end
  parts.empty? ? "0.22" : "(#{parts.join('+')})"
end

def dilla_stem_paths
  paths = {}
  paths[:mids]    = STEM_MIDS    if File.exist?(STEM_MIDS)
  paths[:highs]   = STEM_HIGHS   if File.exist?(STEM_HIGHS)
  paths[:sub]     = STEM_SUB     if File.exist?(STEM_SUB)
  paths[:center]  = STEM_CENTER  if File.exist?(STEM_CENTER)
  paths
end

PROGRESSION_LOG_PATH = File.join(SCRATCH_DIR, "progressions_log.txt")
LEGACY_PROGRESSION_LOGS = [
  File.join(OUTPUT_DIR, ".dilla_progressions_log.txt"),
  File.join(ROOT, ".dilla_progressions_log.txt")
].freeze

# Older versions wrote the log as a dotfile into the invoking directory —
# fold any of those into the canonical log the first time we write, so the
# "nothing explored is lost" guarantee survives the path change.
def migrate_legacy_progression_logs!
  LEGACY_PROGRESSION_LOGS.each do |legacy|
    next unless File.exist?(legacy)
    File.open(PROGRESSION_LOG_PATH, "a") { |f| f.write(File.read(legacy)) }
    FileUtils.rm_f(legacy)
    puts "migrated legacy progression log #{legacy} -> #{PROGRESSION_LOG_PATH}"
  end
end

# Every chord walked during a render, appended so nothing explored is lost —
# generated progressions especially never repeat, so this is the only
# record of what actually played if it's worth turning into a real song.
def log_progression!(track, bpm, pads)
  return if pads.empty?
  FileUtils.mkdir_p(SCRATCH_DIR)
  migrate_legacy_progression_logs!
  lines = pads.map do |chord|
    notes = chord[:hz].map { |hz| nearest_note(hz) }.join(" ")
    "  #{chord[:name]}: #{notes}  (#{chord[:hz].map { |h| h.round(1) }.join(', ')} Hz)"
  end
  File.open(PROGRESSION_LOG_PATH, "a") do |f|
    f.puts "=== #{Time.now.iso8601} — TRACK=#{track} BPM=#{bpm.round(1)} ==="
    f.puts lines
    f.puts
  end
rescue StandardError => e
  warn "progression log write failed: #{e.message}"
end

# Full Jay Dee render: sample drums + stem chops, Dilla Time scheduling.
SELF_SAMPLE_CACHE = File.join(SCRATCH_DIR, "self_sample.wav")

# "Collapse over accretion": before this render's predecessor is deleted,
# grab a short slice of it and cache it — the next render can layer that
# slice back in as texture, a real feedback loop across renders rather
# than each one starting from nothing.
def cache_self_sample!(destination)
  return if ENV.fetch("SELF_SAMPLE", "1") == "0"
  return unless File.exist?(destination) && tool_available?("ffprobe")
  # Not media_metadata: it calls abort() on failure, which would kill the
  # whole render for what's meant to be a best-effort optional step.
  output, _err, status = capture("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                                  "default=noprint_wrappers=1:nokey=1", destination)
  return unless status.success?
  duration = output.to_f
  return if duration < 2.0
  offset = (rand * [duration - 1.5, 0.1].max).round(2)
  FileUtils.mkdir_p(SCRATCH_DIR)
  sh! "ffmpeg", "-y", "-i", destination, "-ss", offset.to_s, "-t", "1.2",
      "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", SELF_SAMPLE_CACHE
rescue StandardError
  FileUtils.rm_f(SELF_SAMPLE_CACHE)
end

def render_dilla(destination = File.join(OUTPUT_DIR, "beat.mp3"), bars_count = nil, keep_stems: false)
  require_tools! "ffmpeg"
  cleanup_render_scratch!
  pick_render_seed!
  remove_instance_variable(:@resolve_form_map) if instance_variable_defined?(:@resolve_form_map)
  @chord_motif_cache = {}
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  cache_self_sample!(destination)
  FileUtils.rm_f(destination)
  cfg      = dilla_resolve_config
  cfg      = DillaSeeds.apply_to_cfg!(cfg)
  n_bars   = bars_count || bars
  DillaRhythm.configure!(n_bars: n_bars, bpm: cfg[:bpm])
  @render_pad_attack_sec = (cfg[:sonic]&.dig("synth", "pad_attack_ms") || 72).to_f / 1000.0
  rel_ms = (cfg[:sonic]&.dig("synth", "pad_release_ms") || 1400).to_f
  @render_pad_release_decay = (1.0 / [rel_ms / 1000.0, 0.25].max).round(4)
  @render_pad_native_wave = DillaLofiMachine.native_wave_for_pad
  @render_pad_gain = (cfg[:sonic]&.dig("synth", "pad_volume_pct") || 40).to_f / 100.0
  composition_session!(n_bars: n_bars, track: cfg[:track].to_s)
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    cfg = cfg.merge(swing: @composition_session.groove_profile[:swing].to_f)
  end
  pick_synth_patches!(cfg, bar: n_bars / 2, n_bars: n_bars)
  beat_p   = 60.0 / cfg[:bpm]
  duration = (beat_p * 4.0 * n_bars).round(3)
  needed_chords = (n_bars.to_f / cfg[:chord_bars]).ceil + 1
  if GENERATED_STYLES.include?(cfg[:progression].to_sym) || cfg[:progression].to_sym == :generated
    ENV["GEN_LENGTH"] = needed_chords.to_s
  end
  pads = dilla_progression(cfg[:progression])
  if pads.length < 2
    fallback = curated_progression_pads(:maj7_minor_cycle) ||
               curated_progression_pads(cfg[:progression])
    if fallback&.length.to_i >= 2
      warn "progression collapsed to #{pads.length} chord(s) for #{cfg[:track]} — using #{fallback.length}-chord fallback"
      pads = fallback
    else
      abort "progression too short (#{pads.length} chords) for track=#{cfg[:track]} — check chord symbols"
    end
  end
  fugue_phases = []
  chord_bar_lens = nil
  unless pads.empty?
    pads, fugue_phases, chord_bar_lens = if camel_mode? && la_beat_progression_enabled? && !soul_progression_locked?
                                           arrange_camel_beat_progression(pads, needed_chords, cfg)
                                         elsif la_beat_progression_enabled? && !soul_progression_locked?
                                           arrange_la_beat_progression(pads, needed_chords, cfg)
                                         elsif curated_progression?(cfg)
                                           lp = arrange_loop_progression(pads, needed_chords, cfg)
                                           [lp[0], lp[1], nil]
                                         else
                                           fp = arrange_fugue_progression(pads, needed_chords, cfg)
                                           [fp[0], fp[1], nil]
                                         end
  end
  @render_chord_bar_lens = chord_bar_lens
  pedal_prob = if curated_progression?(cfg)
                 0.0
               else
                 DillaHarmony.pedal_probability(cfg)
               end
  pedal_prob = 0.18 if pedal_prob.zero? && !curated_progression?(cfg)
  pads = apply_pedal_point(pads, probability: pedal_prob, seed: cfg[:track].hash.abs) unless pedal_prob.zero?
  pads, fugue_phases = if curated_progression?(cfg)
                           DillaHarmony.beautify_curated_pipeline(pads, cfg, phases: fugue_phases)
                         else
                           DillaHarmony.beautify_pipeline(pads, cfg, phases: fugue_phases)
                         end
  @chord_phases = fugue_phases
  @progression_chords = pads
  DillaHarmony.remember_progression(pads)
  symbols = pads.map { |c| c[:name].to_s.sub(/_pedal\z/, "").sub(/_t\d+\z/, "") }
  @progression_insight = pads.length >= 2 ? DillaHarmony.progression_insight(pads) : nil
  @progression_insight ||= DillaMusicGems.progression_analysis(symbols) if defined?(DillaMusicGems)
  @render_chord_bars = cfg[:chord_bars]
  @render_phrase_bars = cfg[:phrase_bars]
  log_progression_phases!(cfg[:track], cfg[:bpm], pads, fugue_phases)
  bass_pads = nil
  if slash_bass_enabled?(cfg) && !pads.empty?
    bass_pads = slash_bass_pads_for(pads, cfg)
  elsif !curated_progression?(cfg) && Random.new(cfg[:track].to_s.hash.abs).rand < 0.1
    bass_pads = voice_lead_chords(generate_progression(root_hz: pads.first[:hz].min * 0.5, mode: :minor,
                                                         length: pads.length))
  end
  events   = dilla_schedule(
    n_bars, beat_p, pads,
    chord_bars: cfg[:chord_bars], phrase_bars: cfg[:phrase_bars],
    swing: cfg[:swing], feel: cfg[:feel], timing: cfg[:timing], quintuplet: cfg[:quintuplet],
    bass_pads:, chord_phases: fugue_phases
  )
  @last_drum_events = events

  pick_external_drum_kit!
  kit = extended_drum_kit(
    kick: layered_kick_sample(load_mono_sample(drum_sample_path("kick.wav"))),
    snare: load_mono_sample(drum_sample_path("snare.wav")),
    ghost: load_mono_sample(drum_sample_path("ghost.wav")),
    hat: load_mono_sample(drum_sample_path("hat.wav")),
    open_hat: load_mono_sample(drum_sample_path("open_hat.wav")),
    bass_43: load_mono_sample(drum_sample_path("bass_43.wav")),
    shaker: synth_shaker_sample,
    cowbell: synth_cowbell_sample
  )
  # Always prefer real chopped one-shots when available (pocket DNA default).
  apply_drum_chops_to_kit!(kit) if ENV.fetch("DRUM_CHOPS", "1") != "0"
  unless dilla_pocket_drums_enabled?
    bar_p = beat_p * 4.0
  else
    # Polyrhythm layer: a 3-against-4 cycle (bar/3 spacing) independent of the
    # main 16-grid groove entirely — real polyrhythm, not a variation of the
    # existing pattern. Reuses the ghost-hit sample at low, varying velocity.
    poly_beat = (beat_p * 4.0) / 3.0
    events[:poly] = (0...(duration / poly_beat).floor).map do |i|
      t = (i * poly_beat).round(6)
      [t, (0.16 + 0.07 * Math.sin(i * 1.7)).clamp(0.08, 0.3), :ghost]
    end
    # Shaker: steady 8th-note pulse (the "shhh" bed real shakers provide),
    # velocity-humanized. Cowbell: sparse, syncopated, deliberately random —
    # a real cowbell part is never on a predictable grid.
    step_p8 = beat_p / 2.0
    events[:shaker] = (0...(duration / step_p8).floor).map do |i|
      t = (i * step_p8).round(6)
      [t, dilla_velocity(0.55, i / 8, i % 8, spread: 0.15)]
    end
    cowbell_rng = Random.new((cfg[:track].to_s.hash.abs % 100_000) + 41)
    events[:cowbell] = (0...(duration / beat_p).floor).filter_map do |i|
      next unless cowbell_rng.rand < 0.07
      t = (i * beat_p + cowbell_rng.rand(beat_p * 0.6)).round(6)
      [t, dilla_velocity(0.3, i, 0, spread: 0.1)]
    end
    bar_p = beat_p * 4.0
    schedule_eclectic_percussion!(events, duration, beat_p, bar_p, cfg, n_bars)
  end

  drum_tmp     = dilla_render_tmp("drums")
  harmonic_tmp = dilla_render_tmp("harmonic")
  render_sample_bus_wav(drum_tmp, events, duration, kit, drum_bus_mapping)
  if flylo_drum_overlay_enabled?
    flylo_sub_tmp = dilla_render_tmp("flylo_sub")
    flylo_top_tmp = dilla_render_tmp("flylo_top")
    begin
      render_sample_bus_wav(flylo_sub_tmp, events, duration, kit, flylo_sub_bus_mapping)
      render_sample_bus_wav(flylo_top_tmp, events, duration, kit, flylo_top_bus_mapping)
      merge_flylo_dual_bus!(drum_tmp, flylo_sub_tmp, flylo_top_tmp)
    ensure
      FileUtils.rm_f(flylo_sub_tmp)
      FileUtils.rm_f(flylo_top_tmp)
      FileUtils.rm_f("#{drum_tmp}.merged.#{Process.pid}.wav")
    end
  end
  # Peak lift only — full loudnorm on the drum bus killed punch and made kicks
  # sound flat/wrong. Keep transient dynamics, just prevent digi-clip.
  if File.file?(drum_tmp)
    # DRUM_PEAK_DB was fetched but ignored (always +3.5dB). Peak-normalize to target.
    peak_db = ENV.fetch("DRUM_PEAK_DB", flylo_primary_drums? ? "-1.0" : "-3.0").to_f
    lift_db = flylo_primary_drums? ? 5.5 : 3.5
    normed = "#{drum_tmp}.norm.wav"
    sh! "ffmpeg", "-y", "-i", drum_tmp,
        "-af", "volume=#{lift_db}dB,alimiter=limit=#{(10**(peak_db / 20.0)).round(4)}:level_out=0.97:attack=1:release=50",
        "-c:a", "pcm_s16le", normed
    FileUtils.mv(normed, drum_tmp) if File.file?(normed)
  end

  chop_gate = gate_expr(events[:chop], hold: 0.32, scale: 0.95)
  pad_gate  = pad_gate_expr(events[:pad])
  stems = dilla_stem_paths
  stem_tempo = (cfg[:bpm] / 90.0).round(4)
  pan_hz = (cfg[:bpm] / 15.0).round(3)
  use_stem_harmony = !stems.empty?
  unless use_stem_harmony
    render_harmonic_wav(harmonic_tmp, events[:pad], events[:chop], events[:bass], duration,
                        melody_events: events[:melody], cfg: cfg, dfam_events: events[:dfam])
  end

  command = ["ffmpeg", "-y", "-i", drum_tmp]
  idx = 1
  unless use_stem_harmony
    command += ["-i", harmonic_tmp]
    idx += 1
  end
  stem_map = {}
  stems.each do |key, path|
    command += ["-stream_loop", "-1", "-i", path]
    stem_map[key] = idx
    idx += 1
  end
  self_sample_idx = nil
  # Previous-render feedback can re-inject full Get Dis Money / prior mix as a "sample".
  if File.exist?(SELF_SAMPLE_CACHE) && ENV.fetch("SELF_SAMPLE", "1") != "0"
    command += ["-stream_loop", "-1", "-i", SELF_SAMPLE_CACHE]
    self_sample_idx = idx
    idx += 1
  end
  ir_input_idx = nil
  unless ENV["CONV_REVERB"] == "0"
    ir_room = ENV["CONV_REVERB"]&.to_sym
    ir_room = :chamber if deep_render? && (!ir_room || !CONVOLUTION_ROOMS.key?(ir_room))
    ir_room ||= CONVOLUTION_ROOMS.keys.sample
    ir_path = DillaMaster.club_ir_path || synth_impulse_response!(ir_room)
    command += ["-i", ir_path]
    ir_input_idx = idx
    idx += 1
  end
  ghost_n = events[:ghost]&.length || 0
  kick_n = events[:kick]&.length || 1
  vinyl_base = sonic_vinyl_level(cfg[:sonic])
  vinyl_amp = vinyl_base.positive? ? DillaMl.groove_synced_vinyl(ghost_n, kick_n, base: vinyl_base) : 0.0
  if vinyl_amp.positive?
    command += ["-f", "lavfi", "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=#{vinyl_amp}:d=#{duration}"]
  end
  turntable_rumble = vinyl_amp.positive? && sonitex_enabled? &&
                     TURNTABLE_RUMBLE_VARIANTS.include?(analog_resolve_variant(track: cfg[:track].to_s))
  command += ["-f", "lavfi", "-i", "anoisesrc=color=brown:r=#{SAMPLE_RATE}:amplitude=0.02:d=#{duration}"] if turntable_rumble

  # Every attempt to fix chord audibility by tuning EQ/weights/sidechain
  # *within* the elaborate mix chain (NY parallel drum compression, a
  # sub-150Hz sidechain duck keyed off the harm bus, per-bus RMS-matched
  # boosts, loudnorm) failed in real listening even when measurements said
  # it should work — confirmed by a from-scratch minimal mix (plain per-bus
  # volume + amix + one limiter, no sidechain/compression stack at all)
  # that DID produce audible chords. That proves the elaborate chain itself
  # was the problem, not the balance numbers. This mirrors that minimal,
  # proven-working mix instead of layering another fix onto the old one.
  # SP-1200-style crunch (that machine IS drum-sampler heritage: 12-bit,
  # tape-saturated) directly on the drum bus, on top of whatever the
  # whole-mix Sonitex pass adds later — more analog grit specifically where
  # it was asked for, not spread thin across the entire mix.
  # Complementary EQ carving, not just level: drums get a shallow dip right
  # where pad-chord fundamentals sit (300-700Hz) so the harm bus doesn't
  # have to fight for that space; the harm bus (below) gets the matching
  # cut down where the kick/bass actually live. Genuine frequency-slotting,
  # not another gain adjustment.
  filt = [build_drum_bus_filter(cfg, cfg[:sonic], duration:)]
  mix_labels = ["[drums]"]
  mix_weights = [ENV.fetch("DRUM_MIX_WEIGHT", "0.72").to_s]
  intro_bars = cfg.fetch(:intro_bars, 4)
  harm_fade_start = (beat_p * 4.0 * [intro_bars, 2].min).round(2)
  harm_fade_dur = (beat_p * 4.0 * 1.25).round(2)
  unless use_stem_harmony
    filt << build_harm_bus_filter(1, duration, cfg, cfg[:sonic], harm_fade_start, harm_fade_dur, beat_p, n_bars)
    if cfg[:sidechain]
      filt.concat(sidechain_filter_chain(cfg))
      mix_labels = ["[sc_mix]"]
      mix_weights = ["1.0"]
    else
      mix_labels << "[harm]"
      mix_weights << ENV.fetch("HARM_MIX_WEIGHT", deep_render? ? "1.55" : "1.38").to_s
    end
  end

  if stem_map[:mids]
    pan_fx = cfg[:stereo_pan] ? ",apulsator=mode=sine:hz=#{pan_hz}:amount=0.38" : ""
    filt << "[#{stem_map[:mids]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo},atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=3400,volume='#{pad_gate}':eval=frame,aphaser=speed=0.11:decay=0.4#{pan_fx}[padbed]"
    mix_labels << "[padbed]"
    mix_weights << "0.82"
  end
  if stem_map[:highs]
    filt << "[#{stem_map[:highs]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo},atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "highpass=f=400,volume='#{chop_gate}':eval=frame,aecho=0.35:0.4:90:0.25[chops]"
    mix_labels << "[chops]"
    mix_weights << "0.68"
  end
  if stem_map[:sub]
    filt << "[#{stem_map[:sub]}:a]aformat=channel_layouts=stereo,atempo=#{stem_tempo},atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=180,equalizer=f=72:t=o:w=1:g=4,volume=0.68[subbed]"
    mix_labels << "[subbed]"
    mix_weights << "0.72"
  end
  if stem_map[:center] && !stem_map[:mids]
    filt << "[#{stem_map[:center]}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=3000,volume='#{pad_gate}':eval=frame[padbed]"
    mix_labels << "[padbed]"
    mix_weights << "0.75"
  end

  if vinyl_amp.positive?
    filt << "[#{idx}:a]highpass=f=120,lowpass=f=6000,volume=0.045[vinyl]"
    mix_labels << "[vinyl]"
    mix_weights << "0.35"
  end
  if turntable_rumble
    rumble_idx = vinyl_amp.positive? ? idx + 1 : idx
    filt << "[#{rumble_idx}:a]lowpass=f=40,highpass=f=22,volume=0.04[rumble]"
    mix_labels << "[rumble]"
    mix_weights << "0.25"
  end
  if self_sample_idx
    # Previous render feedback — off by default on Camel (re-injects prior vocals/sample).
    filt << "[#{self_sample_idx}:a]atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=1800,areverse,volume=0.06[selfsample]"
    mix_labels << "[selfsample]"
    mix_weights << "0.55"
  end
  filt << "#{mix_labels.join}amix=inputs=#{mix_labels.length}:weights=#{mix_weights.join(' ')}:duration=first:normalize=0[mix]"
  filt.concat(master_bus_filters("mix", track: cfg[:track].to_s, duration:, ir_input_idx:, cfg:))

  # Drop empty segments so a stray "" never becomes "No such filter: ''".
  filt_graph = filt.flatten.compact.map(&:to_s).map(&:strip).reject(&:empty?).join(";")
  command += ["-filter_complex", filt_graph, "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  File.write("/tmp/last_filter_graph.txt", filt_graph.gsub(";", ";\n")) if ENV["DEBUG_FILTER_DUMP"]
  sh!(*command)
  # Parallel dry kit after Sonitex — measured demo was peak 0.27 with flat 16ths
  # (pattern erased). Blend pre-master drums back so Camel grid is audible.
  if camel_mode? && ENV.fetch("CAMEL_DRY_DRUMS", "1") != "0" && File.file?(drum_tmp) && File.file?(destination)
    # Default dry kit quiet under pads (0.55); raise CAMEL_DRY_DRUM_WEIGHT for kit-forward.
    dry_w = ENV.fetch("CAMEL_DRY_DRUM_WEIGHT", "0.55").to_f
    bed_w = ENV.fetch("CAMEL_BED_WEIGHT", "1.3").to_f
    dry_mix = "#{destination}.drykit#{File.extname(destination)}"
    begin
      sh! "ffmpeg", "-y", "-i", destination, "-i", drum_tmp,
          "-filter_complex",
          "[1:a]aformat=channel_layouts=stereo,equalizer=f=55:t=o:w=0.8:g=2.5," \
          "equalizer=f=200:t=o:w=1:g=1.5,equalizer=f=4500:t=o:w=1.5:g=3,volume=#{dry_w}[dk];" \
          "[0:a]volume=#{bed_w}[bed];" \
          "[bed][dk]amix=inputs=2:weights=1.25 0.75:duration=first:normalize=0," \
          "alimiter=limit=0.97:level_out=0.98[out]",
          "-map", "[out]", *codec_for(dry_mix), dry_mix
      FileUtils.mv(dry_mix, destination) if File.file?(dry_mix)
    rescue StandardError => e
      warn "camel dry drums: #{e.message}"
      FileUtils.rm_f(dry_mix)
    end
  end
  if (rap_slug = rap_vocal_stream_slug)
    begin
      fit = rap_vocal_fit!(rap_slug, beat_bpm: cfg[:bpm], n_bars: n_bars)
      if fit && File.file?(fit)
        rap_tmp = "#{destination}.rap#{File.extname(destination)}"
        mix_rap_vocal_layer!(destination, fit, rap_tmp)
        FileUtils.mv(rap_tmp, destination)
        puts "rap-vocal: mixed #{rap_slug} → #{destination}"
      end
    rescue StandardError, SystemExit => e
      warn "rap-vocal: skipped (#{e.class}) — #{e.message}"
    end
  end
  # Final integrated loudness — every track (with or without vocals) same level.
  if ENV.fetch("STREAM_NORMALIZE", "1") != "0" || ENV["DILLA_STREAMING"] == "1"
    normalize_track_loudness!(destination)
  end
  export_render_stems!(destination, drum_tmp, harmonic_tmp, events, duration, cfg,
                       use_stem_harmony: use_stem_harmony)
  keep_stems ||= ENV["KEEP_STEMS"] == "1"
  unless keep_stems
    FileUtils.rm_f(drum_tmp)
    FileUtils.rm_f(harmonic_tmp) unless use_stem_harmony
  end
  stem_note = use_stem_harmony ? stems.keys.join("+") : "synth-harmony+melody"
  mix_note  = sonitex_label
  lead_arp_style = lead_arp_cfg_for(@render_lead_patch)&.dig(:style)
  patch_note = [@render_ep_patch&.dig(:id), @render_warm_patch&.dig(:id),
                @render_scale_lead_patch&.dig(:id), @render_scale_arp_style,
                @render_lead_patch&.dig(:id), @render_arp_style, lead_arp_style].compact.join("/")
  kick_note = kicks_enabled? ? "kicks" : "no-kicks"
  comp_note = ""
  if composition_enabled? && instance_variable_defined?(:@composition_session) && @composition_session
    @composition_session.save!
    s = @composition_session
    comp_note = ", performer=#{s.performer}/#{s.groove_dna} gen=#{s.generation}"
  end
  puts "wrote #{destination} (#{cfg[:bpm].to_i} BPM, #{n_bars} bars, #{cfg[:track]}, #{kick_note}, #{mix_note}, #{stem_note}, patches=#{patch_note}#{comp_note})"
end

def industrial_techno_section(bar)
  case bar
  when 0..7   then :intro
  when 8..31  then :groove
  when 32..39 then :breakdown
  when 40..47 then :build
  when 48..111 then :main
  when 112..119 then :peak
  else :outro
  end
end

# Arranged industrial techno: intro → groove → breakdown → build → main → peak → outro.
def industrial_techno_schedule(n_bars, beat_p)
  bar_p  = (beat_p * 4.0).round(6)
  step_p = (bar_p / 16.0).round(6)
  events = Hash.new { |h, k| h[k] = [] }

  n_bars.times do |bar|
    base    = bar * bar_p
    section = industrial_techno_section(bar)

    case section
    when :intro
      events[:kick] << [base, 0.82] if bar % 4 == 0
      events[:kick] << [base + step_p * 8, 0.55] if bar >= 4
    when :breakdown
      events[:kick] << [base, 0.65] if bar.even?
      events[:kick] << [base + step_p * 8, 0.45] if bar >= 36
    else
      [0, 4, 8, 12].each do |step|
        vel = section == :peak ? 1.0 : 0.9
        events[:kick] << [base + step * step_p, vel]
      end
      events[:kick] << [base + step_p * 14, 0.62] if section == :peak && bar.odd?
      events[:kick] << [base + step_p * 15, 0.48] if section == :build && bar >= 44
    end

    unless section == :intro && bar < 2
      clap_vel = section == :peak ? 0.78 : 0.62
      events[:clap] << [base + step_p * 4, clap_vel * 0.85] unless section == :breakdown && bar < 36
      events[:clap] << [base + step_p * 12, clap_vel]
      events[:clap] << [base + step_p * 14, 0.42] if section == :peak && bar % 2 == 1
    end

    hat_active = !(section == :breakdown && bar >= 34)
    16.times do |step|
      next unless hat_active
      seed = (bar * 97) + (step * 31)
      next if section == :groove && step.even? && seed % 9 == 0
      next if section == :main && step % 4 == 0 && seed % 11 == 0
      accent = step.odd? ? 1.08 : 1.0
      vel = (0.16 + (seed % 11) * 0.022) * accent
      vel *= 1.25 if section == :peak
      events[:hat] << [base + step * step_p, vel]
    end

    if hat_active && [1, 3, 5, 7].include?(bar % 8) && section != :intro
      events[:open] << [base + step_p * 6, section == :peak ? 0.42 : 0.32]
      events[:open] << [base + step_p * 14, 0.28] if section == :main || section == :peak
    end

    bass_active = section != :breakdown || bar < 35
    if bass_active
      acid_steps = section == :intro ? [0, 8] : [0, 2, 3, 5, 8, 10, 11, 14]
      acid_steps.each do |step|
        note = ((bar / 2 + step) % 4) >= 2 ? :ind_bass_bb : :ind_bass_e
        vel  = section == :peak ? 0.82 : 0.68
        vel *= 0.5 if section == :intro
        events[:bass] << [base + step * step_p, vel, note]
      end
    end

    if section != :breakdown && bar % 8 == 7
      events[:stab] << [base + step_p * 4, 0.52]
      events[:stab] << [base + step_p * 12, 0.38] if section == :peak
    end
  end
  events
end

def industrial_schedule(n_bars, beat_p)
  industrial_techno_schedule(n_bars, beat_p)
end

# Industrial techno: arranged 135 BPM groove, rumble sub, sidechain, dub space.
def render_industrial(destination = File.join(ROOT, "renders", "foundry_pulse.mp3"), bars_count = nil)
  require_tools! "ffmpeg"
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  ibpm     = ENV.fetch("IBPM", INDUSTRIAL_TECHNO_BPM.to_s).to_f
  beat_p   = (60.0 / ibpm).round(6)
  n_bars   = bars_count || (ENV["BARS"] ? bars : INDUSTRIAL_TECHNO_BARS)
  duration = (beat_p * 4.0 * n_bars).round(3)
  dotted_8th_ms = (3.0 * beat_p / 4.0 * 1000.0).round(1)
  events   = industrial_techno_schedule(n_bars, beat_p)

  kit = {
    ind_kick: load_mono_sample(drum_sample_path("ind_kick.wav")),
    ind_clap: load_mono_sample(drum_sample_path("ind_clap.wav")),
    ind_hat: load_mono_sample(drum_sample_path("ind_hat.wav")),
    open_hat: load_mono_sample(drum_sample_path("open_hat.wav")),
    ind_bass_e: load_mono_sample(drum_sample_path("ind_bass_e.wav")),
    ind_bass_bb: load_mono_sample(drum_sample_path("ind_bass_bb.wav")),
    ind_stab: load_mono_sample(drum_sample_path("ind_stab.wav"))
  }
  stab_hits = events[:stab].map { |t, v| [t, v, :ind_stab] }
  drum_tmp  = File.join(ROOT, ".ind_drums.wav")
  render_sample_bus_wav(
    drum_tmp,
    events.merge(stab: stab_hits),
    duration,
    kit,
    kick: :ind_kick, clap: :ind_clap, hat: :ind_hat, open: :open_hat, bass: :ind_bass_e, stab: :ind_stab
  )

  sides_path = File.join(STEM_DIR, "sides.mp3")
  command = ["ffmpeg", "-y", "-i", drum_tmp]
  idx = 1
  sides_idx = nil
  if File.exist?(sides_path)
    command += ["-stream_loop", "-1", "-i", sides_path]
    sides_idx = idx
    idx += 1
  end
  command += ["-f", "lavfi", "-i", "aevalsrc='0.55*sin(2*PI*38*t)*exp(-mod(t,#{beat_p})*1.8)':d=#{duration}:s=#{SAMPLE_RATE}"]
  rumble_idx = idx
  idx += 1
  command += ["-f", "lavfi", "-i", "anoisesrc=color=white:amplitude=0.022:d=#{duration}:r=#{SAMPLE_RATE}"]
  noise_idx = idx

  filt = []
  filt << "[0:a]aformat=channel_layouts=stereo,asplit=2[drums][drums_sc]"
  filt << "[#{rumble_idx}:a]aformat=channel_layouts=mono,lowpass=f=95,equalizer=f=48:t=o:w=0.8:g=8,volume=0.42[rumble]"
  if sides_idx
    filt << "[#{sides_idx}:a]aformat=channel_layouts=stereo,atrim=0:#{duration},asetpts=PTS-STARTPTS," \
            "highpass=f=180,lowpass=f=8500,volume=0.18[texture]"
  end
  filt << "[#{noise_idx}:a]highpass=f=400,lowpass=f=5000,volume=0.04[noise]"
  mix_in = ["[drums]", "[rumble]"]
  mix_w  = ["1.0", "0.55"]
  if sides_idx
    mix_in << "[texture]"
    mix_w << "0.28"
  end
  mix_in << "[noise]"
  mix_w << "0.06"
  filt << "#{mix_in.join}amix=inputs=#{mix_in.length}:weights=#{mix_w.join(' ')}:duration=first[bed]"
  filt << "[bed][drums_sc]sidechaincompress=threshold=-24dB:ratio=8:attack=0.5:release=110:level_sc=0.9[pumped]"
  filt << "[pumped]asplit=2[dry][rev_send]"
  filt << "[rev_send]highpass=f=100,lowpass=f=9000,aecho=0.7:0.8:480|960|1920|3200:0.6|0.45|0.3|0.18[verb]"
  filt << "[dry][verb]amix=inputs=2:weights=0.62 0.38[with_verb]"
  filt << "[with_verb]asplit=2[dry2][dly]"
  filt << "[dly]highpass=f=280,aecho=0.55:0.65:#{dotted_8th_ms}|#{(dotted_8th_ms * 2).round(1)}|#{(dotted_8th_ms * 3).round(1)}:0.75|0.55|0.35[echo]"
  filt << "[dry2][echo]amix=inputs=2:weights=0.7 0.3[pre]"
  sat = Math.tanh(3.8).round(6)
  filt << "[pre]extrastereo=m=1.18[wide]"
  filt << "[wide]aeval=exprs='tanh(3.8*val(0))/#{sat}|tanh(3.8*val(1))/#{sat}'[satd]"
  filt << "[satd]acompressor=threshold=-14dB:ratio=10:attack=1:release=45:makeup=3.5[comp]"
  filt << "[comp]equalizer=f=52:t=o:w=0.65:g=6,equalizer=f=120:t=o:w=1:g=2,equalizer=f=9500:t=o:w=2:g=-5[eq]"
  filt << "[eq]acrusher=bits=14:samples=2:mix=0.08[pre_master]"
  filt.concat(master_bus_filters("pre_master"))

  command += ["-filter_complex", filt.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  sh!(*command)
  FileUtils.rm_f(drum_tmp)
  mix_note = sonitex_enabled? ? sonitex_label : "dry"
  puts "wrote #{destination} (#{ibpm.to_i} BPM industrial techno, #{n_bars} bars, #{mix_note})"
end

# =============================================================================
# COMPOSITION — memory, arrangement, performers, evolution, critique
# =============================================================================

def composition_jam(n_bars = 16)
  ENV["COMPOSITION"] = "1"
  reset_composition_session!
  n_bars = (ENV["BARS"] || n_bars).to_i
  sess = composition_session!(n_bars: n_bars, force_new: true)
  puts "jam — #{sess.track} | performer=#{sess.performer} groove=#{sess.groove_dna} | #{n_bars} bars"
  dest = File.join(ROOT, ".jam_tmp.wav")
  render_dilla(dest, n_bars, keep_stems: true)
  play_loop(dest)
end

def composition_evolve(n_bars = 16, generations = 5)
  ENV["COMPOSITION"] = "1"
  n_bars = (ENV["BARS"] || n_bars).to_i
  generations = (ENV["GENERATIONS"] || generations).to_i
  reset_composition_session!
  sess = composition_session!(n_bars: n_bars, force_new: true)
  cfg = dilla_resolve_config
  dest = File.join(ROOT, ".evolve_best.wav")
  render_fn = lambda do |session|
    @composition_session = session
    out = File.join(SCRATCH_DIR, "evolve_gen#{session.generation}.wav")
    render_dilla(out, n_bars, keep_stems: false)
    out
  end
  render_fn.define_singleton_method(:quality) { |path| dilla_quality(path) }
  render_fn.define_singleton_method(:last_events) { @last_drum_events }
  best = DillaComposition::Evolution.run(session: sess, cfg: cfg, n_bars: n_bars,
                                         generations: generations, render_fn: render_fn)
  FileUtils.cp(best[:path], dest) if best[:path] && File.exist?(best[:path])
  DillaComposition::Critique.print_report(best[:critique]) if best[:critique]
  puts "evolve best score=#{best[:score]} → #{dest}"
  dest
end

def composition_critique(path = nil)
  path ||= File.join(ROOT, ".live_tmp.wav")
  path = File.join(ROOT, ".jam_tmp.wav") unless File.file?(path)
  abort "no render to critique — run: ruby dilla.rb jam" unless File.file?(path)
  report = dilla_quality(path)
  sess = composition_session!(n_bars: bars)
  critique = DillaComposition::Critique.analyze(report, session: sess, events: @last_drum_events)
  DillaComposition::Critique.print_report(critique)
  sess.critique_log << { path: path, critique: critique[:scores], overall: critique[:overall] }
  sess.save!
  critique
end

def composition_session_cmd(sub = nil, *rest)
  case sub.to_s.downcase
  when "save"
    sess = composition_session!(n_bars: bars)
    payload = sess.save!
    puts "session saved → #{DillaComposition::SESSION_PATH}"
    puts JSON.pretty_generate(payload.slice("track", "performer", "groove_dna", "generation", "best_score"))
  when "load"
    reset_composition_session!
    ENV["COMPOSITION"] = "1"
    n_bars = (rest[0] || ENV["BARS"] || bars).to_i
    sess = composition_session!(n_bars: n_bars, force_new: true)
    puts "session loaded — #{sess.track} performer=#{sess.performer} groove=#{sess.groove_dna}"
  when "show", nil, ""
    sess = composition_session!(n_bars: bars)
    puts "── Session ──"
    puts "track: #{sess.track}  performer: #{sess.performer}  groove: #{sess.groove_dna}"
    puts "generation: #{sess.generation}  best_score: #{sess.best_score}"
    puts "motifs: #{sess.motifs.map { |m| "#{m.id}(#{m.state})" }.join(', ')}"
    puts "callbacks: #{sess.callbacks.length}  tension anchors: #{sess.tension_curve.length}"
    puts "arrangement: #{sess.arrangement.map { |e| e[:section] }.uniq.join(' → ')}"
  when "new"
    reset_composition_session!
    ENV["COMPOSITION"] = "1"
    track = rest[0] || ENV["TRACK"] || "timeless"
    n_bars = (rest[1] || ENV["BARS"] || bars).to_i
    @composition_session = DillaComposition::Session.new(track: track, n_bars: n_bars)
    @composition_session.save!
    puts "new session — #{track} (#{n_bars} bars)"
  else
    abort "usage: ruby dilla.rb session [save|load|show|new] [args]"
  end
end

def regenerate_stem(stem, bars_count = 16)
  ENV["COMPOSITION"] = "1"
  bars_count = (ENV["BARS"] || bars_count).to_i
  sess = composition_session!(n_bars: bars_count)
  case stem.to_s.downcase
  when "bass"
    sess.motifs.find { |m| m.id == "bass_motif" }&.evolve!
  when "hats"
    keys = DillaComposition::GROOVE_DNA.keys
    sess.groove_dna = keys[(keys.index(sess.groove_dna) || 0) + 1] % keys.length
  when "melody"
    sess.motifs.find { |m| m.id == "hook" }&.evolve!
    sess.record_callback!(bars_count / 2, "hook", :A_prime)
  else
    abort "usage: ruby dilla.rb regenerate-stem bass|hats|melody [bars]"
  end
  sess.save!
  puts "regenerate-stem #{stem} — performer=#{sess.performer} groove=#{sess.groove_dna}"
  regenerate(bars_count)
end

def composition_listen_loop(n_bars = 16)
  ENV["COMPOSITION"] = "1"
  n_bars = (ENV["BARS"] || n_bars).to_i
  max_passes = (ENV["LISTEN_PASSES"] || 3).to_i
  dest = File.join(ROOT, ".listen_loop.wav")
  render_fn = ->(pass) { render_dilla(File.join(SCRATCH_DIR, "listen_pass#{pass}.wav"), n_bars); dest }
  analyze_fn = ->(path) { dilla_quality(path) }
  path = DillaComposition::ListeningLoop.converge(render_fn: render_fn, analyze_fn: analyze_fn, max_passes: max_passes)
  FileUtils.cp(path, dest) if path && File.exist?(path)
  puts "listen_loop → #{dest}"
  play_loop(dest) if File.exist?(dest)
end

# =============================================================================
# HELP
# =============================================================================

def help
  puts <<~HELP
    Dilla Lab — unified audio engine (#{ROOT})

    DEFAULT (no command — continuous Camel stream)
      ruby dilla.rb                    Start non-stop stream (RENDER_MODE=camel, STREAM_SOUL=1)
      ruby dilla.rb stream [bars]      Same as bare default (#{STREAM_BARS_COUNT}/BARS bars)
      ruby dilla.rb out.wav [bars]     One-shot render to path (not stream)
      ruby dilla.rb dilla [out] [bars] One-shot Dilla render → #{DEFAULT_RENDER_OUTPUT}
      DILLA_DEEP=0                     One-shot: standard render (no quality gate / refine)
      DILLA_RAW=1                      Skip all best-default ENV
      PHONE_PREVIEW_GATE=1             Laptop-speaker check in quality gate (on in deep mode)

    STREAM (non-stop rotation — speakers via afplay/ffplay)
      stream [bars]                    Fast render+play per profile (#{STREAM_BARS_COUNT} bars default)
      STREAM_CONTINUOUS=1 (default)    Outer shell auto-restarts; per-track timeout skips hangs
      STREAM_TRACK_TIMEOUT=420         Max seconds per track before skip (0 = no limit)
      STREAM_GAP=0.15                  Pause between tracks (0 = back-to-back)
      STREAM_ITERATE=1 (default)       Auto-refine mix/groove each track; log stream_iterate.log
      STREAM_DEMO=demo.wav (default)   Each stream track overwrites demo.wav (WAV = no mp3 encode)
      RENDER_MODE=long_soul|golden       Lush 32-bar soul (FORM + HARMONY_LEAD + bill_evans pads)
      RENDER_MODE=camel                  FlyLo Camel preset (86 BPM, learned drums, no Dilla kicks)
      camel [out.mp3] [bars]             One-shot Camel render (chromatic_mediant_drift @ 86)
      FORM=soul_16|soul_32|donuts_time|camel_32  Section map for drums/arp density
      CAMEL_DRUM_ENTRY_BAR=4             Bars before FlyLo drums enter (Camel default)
      STREAM_TRACK=chromatic_mediant_drift  Pin Camel progression in stream mode
      CAMEL_KEEP_FLYLO=1                 Keep FlyLo overlay on breakdowns (Camel default)
      HARMONY_LEAD=1                     Chord-tone harmonic arp stem (voiced pads + extensions)
      STREAM_SOUL=1 (stream default)     Locked Donuts turnaround + harmony lead + soul form
      STREAM_HARMONY_EVERY=2           Rotate voicing + soul TRACK family every N tracks
      STREAM_ANALOG_WILD=1             Random wild analog FX mashups (~35% of analog rotates)
      STREAM_LEARN_BIAS=1              Bias stream toward last learn --apply hints
      STREAM_CREATIVE_FREEDOM=1        Rotate lead/scale arp patches + stem weights every track
      STREAM_DEEP=1 stream [bars]      Full deep pipeline + quality gate per track (~1–2 min)
      DILLA_FORCE_TERMINAL=1         macOS: open Terminal.app for speaker playback
      KICKS=1 (default in stream)      Layered 808-style kicks in the drum bus
      KICK_GAIN=0.42 (stream default)  Kick/sub level — lower if still loud
      SPEAK=1 (default in stream)      TTS pickup lines over the beat (dry, no echo)
      SPEAK_VOICE=en-US-AndrewNeural   Funny-clear voice (GuyNeural also works)
      SPEAK_RATE=-48%                  Slower speech (default in stream)
      SPEAK=0                          Beat only — skip speech overlay
      RADIO_BERGEN=1 (stream default)  Bias TRACK from playlist.brgen.no learnings
      radio-bergen-study [--audio-root PATH]  Refresh learnings YAML from manifest
      radio-bergen-analyze [--audio-root PATH]  Per-track dossiers (drums/texture/harmony)
      radio-bergen-librosa            Librosa deep analysis (optional .venv)

    SYNTHESIS
      loose_pocket [out.wav|mp3]         Dirty pocket drums + VLC FX (default on)
      loose_pocket beats [dir]           Batch beat_01..14 wav+mp3 → renders/beats/
      DELICIOUS=1 (default)        0.72x pocket BPM | VLC=1 (default) all audio effects
      dilla | beat [out.mp3]       J Dilla beat — TRACK= preset (default chromatic_minor_descent)
      hiphop [out.mp3]             Slum Village engine (default TRACK=syncopated_slash_ninth)
      slum [dir]                   Batch session_01..14 → renders/ (Sonitex on)
      industrial [out.mp3]         Industrial techno (default renders/foundry_pulse.mp3)
      techno [out.mp3]             Hard distorted techno (#{TECHNO_BPM} BPM)
      analog [out.mp3]             Full analog pad restoration renderer
      analog_liveset [out] [min]   Long-form analog render
      render [out.mp3]             Core pad + drum synthesis
      electronium [out.mid]        MIDI (--electronium-classic=1 | --electronium-render=1)
      electronium-full [out.wav]   Full engine render of electronium_loop (--electronium-classic=1)
      midi [out.mid]               Alias for electronium

    VOCAL MIXES (Sirkel Sag × Voicemails)
      mix | v11                    Latest mix recipe (default v11)
      v7 | v8 | v9 | v10           Earlier mix generations

    SAMPLE PIPELINE
      prepare [path]               Drum kit + FFmpeg stem rack (neosoul.mp3 default)
      sample                       source → demucs → clean harmonic
      source | download [url|path] [out]  yt-dlp / ffmpeg capture audio
      separate [path]              Demucs 4-stem (htdemucs_ft)
      demux <url|path> [deep]      6-stem demucs (htdemucs_6s) + optional EQ sub-bands
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
      RAP_VOCAL=<slug> on render/stream  Auto-fit (atempo+bar phase) + mix (RAP_VOCAL_MIX, RAP_VOCAL_DUCK)
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

    EXTERNAL ASSETS (opt-in only — engine is pure-Ruby/ffmpeg by default)
      fetch-assets                   Cache CC0 drum WAVs + 2 extra soundfonts
      use-external-kit <name>        Install a fetched kit into samples/drums/custom/
                                      (01-hard-trap | 02-bounce | 03-soulful-vintage)
    FLAGS (equivalent to the ENV vars below, usable on any command):
      #{FLAG_ENV.keys.map { |k| "--#{k}=…" }.join(' ')}

    SCRATCH: caches + temp audio in #{SCRATCH_DIR} (DILLA_SCRATCH_DIR overrides).
      progressions_log.txt there is the only record of generated progressions.

    ENV: BPM BARS TRACK PROGRESSION SWING KICKS SONITEX SONITEX_PRESET BEAT LIVESET_MIN
         PERFORMER=yancey GROOVE_DNA=donuts COMPOSITION=1 GENERATIONS=5 LISTEN_PASSES=3
     KICKS=1 (default) enable kicks | KICKS=0 mute kick drum
         KICK_GAIN=0.38 (default) kick/sub level scale — lower if still loud
         SONITEX=donuts_warm (default) | SONITEX=classic | SONITEX=heavy | SONITEX=0 dry
         ANALOG_CHAIN=acetate|sp1200|auto (rotates per session in slum batch)
         FORCE_KIT=1 regenerate synth drums
         samples/drums/custom/ overrides kit
         TRACK = internal preset id (use session_01..14 outputs via slum command)
         IBPM=135 BARS=128 for industrial techno length
  HELP
end

# =============================================================================
# ANALOG RENDERER (dilla_analog.rb)
# =============================================================================

def analog_two_bar_cycle
  (beat_seconds * 4 * 2).round(6)
end

def analog_drum_cycle_events(events)
  cycle = analog_two_bar_cycle
  events.map { |t, *rest| [(t % cycle).round(6), *rest] }
end

def kick_wave(t, v, cycle = analog_two_bar_cycle)
  tc = t.round(6)
  td = "mod(t,#{cycle})"
  "between(#{td},#{tc},#{(t + 0.42).round(6)})*#{v}*0.95*exp(-(#{td}-#{tc})*7.4)*" \
    "sin(2*PI*(45+115*exp(-20*(#{td}-#{tc})))*(#{td}-#{tc}))"
end

def bass_wave(t, v, f, cycle = analog_two_bar_cycle)
  tc = t.round(6)
  td = "mod(t,#{cycle})"
  "between(#{td},#{tc},#{(t + 0.46).round(6)})*#{v}*0.42*exp(-(#{td}-#{tc})*3.2)*sin(2*PI*#{f}*(#{td}-#{tc}))"
end

def analog_section_for_bar(b, total)
  return [:intro, 0.42] if b < 8
  return [:a, 1.00] if b < 24
  return [:a2, 1.00] if b < 40
  return [:break, 0.55] if b < 48
  return [:b, 1.00] if b < 64
  return [:drop, 0.72] if b < 72
  return [:c, 1.00] if b < 88
  [:outro, [0.25, 1.0 - ((b - 88) / [12.0, total - 88.0].max)].max]
end

def analog_rotate_chord(chord, bar_index)
  hz = chord[:hz].rotate((bar_index / 8) % chord[:hz].length)
  extra = case bar_index % 12
          when 0 then hz[0] * 1.067
          when 4 then hz[2] * 1.414
          when 8 then hz[3] * 1.122
          else nil
          end
  extra ? (hz + [extra]) : hz
end

def analog_schedule(bar_count)
  beat = beat_seconds
  bar_len = beat * 4
  step = bar_len / 16
  events = Hash.new { |h, k| h[k] = [] }
  kick_patterns = [[0, 7, 10, 14], [0, 5, 7, 10, 14], [0, 3, 7, 10, 12, 14], [0, 6, 9, 14]]

  bar_count.times do |b|
    sec, den = analog_section_for_bar(b, bar_count)
    base = b * bar_len
    kp = kick_patterns[(b / 8 + b % 3) % kick_patterns.length].dup
    kp = [0, 3, 6, 7, 10, 12, 14, 15] if b % 16 == 15
    kp = [0, 10] if sec == :intro && b > 2
    kp = [] if sec == :intro && b <= 2
    kp = (b.even? ? [0] : [0, 7]) if sec == :break
    kp = (b.even? ? [0, 10] : [0, 7, 14]) if sec == :drop
    kp = [0] if sec == :outro && b > bar_count - 8 && b % 4 == 0

    kp.each_with_index do |s, i|
      t = base + s * step + [0.000, 0.006, 0.011, -0.004, 0.018][(b + i) % 5]
      events[:kick] << [t, den]
      events[:bass] << [t + 0.023, den, ANALOG_ROOTS[(b / 4 + i) % ANALOG_ROOTS.length]] unless sec == :intro
    end

    [4, 12].each do |s|
      events[:snare] << [base + s * step + [-0.010, -0.006, 0.004, 0.010, 0.017][b % 5], den] unless sec == :intro
    end

    (b.even? ? [6, 11] : [3, 6, 11, 15]).each do |s|
      events[:ghost] << [base + s * step + [-0.014, 0.006, 0.018][(b + s) % 3], den * 0.32] unless [:intro, :drop].include?(sec)
    end

    hats = b % 16 == 7 ? [0, 4, 8, 12] : [0, 2, 4, 6, 8, 10, 12, 14]
    hats = b.even? ? [] : [0, 4, 8, 12] if sec == :break
    hats.each_with_index do |s, i|
      jitter = [-0.004, 0.000, 0.003, 0.006][(b + s) % 4]
      events[:hat] << [base + s * step + (i.odd? ? 0.018 : 0.002) + jitter, den * 0.52]
    end

    events[:open] << [base + 6 * step + 0.008, den * 0.30] if ![:intro, :break].include?(sec) && [1, 3].include?(b % 4)

    if b >= 2 && b % 4 == 0
      chord = analog_rotate_chord(PAD_CHORDS[(b / 4) % PAD_CHORDS.length], b)
      sustain = 3.2 + (b % 3) * 0.9
      events[:pad] << [base + 0.03, den, chord, sustain]
    end

    if b >= 2 && b % 2 == 0
      chord = analog_rotate_chord(PAD_CHORDS[(b / 4 + 3) % PAD_CHORDS.length], b)
      events[:chop] << [base + [1, 2, 5, 9, 13][b % 5] * step + [-0.022, 0.0, 0.017][b % 3], den, chord]
    end

    events[:riser] << [base + 2 * beat, 0.13] if [7, 23, 39, 47, 63, 71, 87].include?(b)
    events[:stop] << [base + 3 * beat, 0.18] if [23, 39, 47, 63, 71, 87].include?(b)
  end
  events
end

def analog_pad_expression(t, v, chord, sustain, bar_index)
  hz = chop_hz(chord)
  parts = hz.each_with_index.map do |f, i|
    drift = 1.0 + ((i - 2) * 0.0017) + (Math.sin((bar_index + i) * 1.7) * 0.0009)
    spike = (bar_index % 11 == i ? (ANALOG_CFG[:bad_tune_spike_cents] / 1200.0) : 0.0)
    ff = f * drift * (2.0 ** spike)
    [
      "sin(2*PI*#{ff}*(t-#{t}))",
      "0.55*sin(2*PI*#{ff * 1.004}*(t-#{t}))",
      "0.32*sin(2*PI*#{ff * 2.005}*(t-#{t}))",
      "0.20*sin(2*PI*#{ff * 0.5}*(t-#{t}))",
      "0.11*sin(2*PI*#{ff * 3.0}*(t-#{t}))"
    ].join("+")
  end.join("+")
  "between(t,#{t},#{t + sustain})*#{v}*0.035*exp(-(t-#{t})*0.26)*(0.78+0.22*sin(2*PI*0.23*(t-#{t})))*(#{parts})"
end

def render_analog(destination, bar_count: bars)
  require_tools! "ffmpeg"
  dur = (bar_count * beat_seconds * 4).round(3)
  ev = analog_schedule(bar_count)
  cycle = analog_two_bar_cycle

  kick = analog_drum_cycle_events(ev[:kick]).map { |t, v| kick_wave(t, v, cycle) }
  bass = analog_drum_cycle_events(ev[:bass]).map { |t, v, f| bass_wave(t, v, f, cycle) }
  snare = ev[:snare].map { |t, v| "between(t,#{t},#{t + 0.18})*#{v}*0.60*exp(-(t-#{t})*23)" }
  ghost = ev[:ghost].map { |t, v| "between(t,#{t},#{t + 0.09})*#{v}*exp(-(t-#{t})*35)" }
  hat = ev[:hat].map { |t, v| "between(t,#{t},#{t + 0.06})*#{v}*exp(-(t-#{t})*78)" }
  open_hat = ev[:open].map { |t, v| "between(t,#{t},#{t + 0.25})*#{v}*exp(-(t-#{t})*11)" }
  pad = ev[:pad].each_with_index.map { |(t, v, chord, sustain), i| analog_pad_expression(t, v, chord, sustain, i) }
  chop = ev[:chop].map { |t, v, chord| chop_wave(chord, t, v) }
  risers = ev[:riser].map { |t, v| "between(t,#{t},#{t + 2.0})*#{v}*((t-#{t})/2.0)^2" }
  stops = ev[:stop].map { |t, v| "between(t,#{t},#{t + 1.1})*#{v}*exp(-(t-#{t})*2.2)" }

  inputs = [
    *lavfi("aevalsrc='#{expr_sum(kick)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(bass)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("anoisesrc=color=white:r=#{SAMPLE_RATE}:amplitude=0.5:d=#{dur}"),
    *lavfi("anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.04:d=#{dur}"),
    *lavfi("aevalsrc='#{expr_sum(pad)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(chop)}':d=#{dur}:s=#{SAMPLE_RATE}"),
    *lavfi("aevalsrc='#{expr_sum(risers + stops)}':d=#{dur}:s=#{SAMPLE_RATE}")
  ]

  filter = <<~F
    [0:a]aformat=channel_layouts=stereo[k];
    [1:a]aformat=channel_layouts=stereo,lowpass=f=140[bs];
    [2:a]aformat=channel_layouts=stereo,asplit=3[ns][nh][no];
    [ns]volume='#{safe_volume_env(snare + ghost)}':eval=frame,highpass=f=160,bandpass=f=1600:w=2600[sn];
    [nh]volume='#{safe_volume_env(hat)}':eval=frame,highpass=f=6500[hh];
    [no]volume='#{safe_volume_env(open_hat)}':eval=frame,bandpass=f=5600:w=5200[op];
    [4:a]aformat=channel_layouts=stereo,#{DillaAutomation.pad_character_filter(cutoff_hz: ANALOG_CFG[:lowpass_hz], phaser_speed: 0.1, phaser_decay: 0.35)},adelay=#{ANALOG_CFG[:chorus_delay_l_ms]}|#{ANALOG_CFG[:chorus_delay_r_ms]},aecho=0.18:0.22:120:0.22[pad];
    [5:a]aformat=channel_layouts=stereo,highpass=f=120,lowpass=f=5000,aecho=0.18:0.22:90:0.28[chop];
    [6:a]aformat=channel_layouts=stereo,highpass=f=900,lowpass=f=9000[fx];
    [k][bs][sn][hh][op][pad][chop][fx]amix=inputs=8:weights=1.25 0.9 0.9 0.48 0.42 0.95 0.65 0.35:duration=longest[music];
    [3:a]volume=#{ANALOG_CFG[:vinyl_level]},highpass=f=90,lowpass=f=8000[vinyl];
    [music][vinyl]amix=inputs=2:weights=1 0.32:duration=first,
      acompressor=threshold=-18dB:ratio=3.5:attack=25:release=120:makeup=2,
      acrusher=bits=#{ANALOG_CFG[:sp_bits]}:samples=#{ANALOG_CFG[:sp_ratio].round(3)}:mix=0.22,
      aeval='(tanh((val(0)+#{ANALOG_CFG[:tape_dc]})*1.45)-0.072)/0.87|(tanh((val(1)+#{ANALOG_CFG[:tape_dc]})*1.45)-0.072)/0.87',
      highpass=f=30,lowpass=f=12000,equalizer=f=45:t=o:w=1.2:g=1,
      alimiter=level_out=0.96:limit=0.92[out]
  F

  FileUtils.mkdir_p(File.dirname(destination))
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filter.tr("\n", " "), "-map", "[out]", *codec_for(destination), destination
  puts "wrote #{destination}"
end

def analog_liveset(destination = File.join(OUTPUT_DIR, "analog_liveset.mp3"), minutes = 12)
  bar_count = [(minutes.to_f * 60.0 / (beat_seconds * 4)).ceil, 64].max
  render_analog(destination, bar_count: bar_count)
end

# =============================================================================
# MADLIB DRUMS — pure dirty MPC beats, Dilla-time, no harmony/stems
# =============================================================================

def delicious_pocket_enabled?
  ENV.fetch("DELICIOUS", "1") !~ /\A(?:0|false|off)\z/i
end

def vlc_effects_enabled?
  ENV.fetch("VLC", "1") !~ /\A(?:0|false|off)\z/i
end

def madlib_resolve_config
  cfg = dilla_resolve_config
  base_timing = MICROTIMING_MS.merge(cfg[:timing] || {})
  timing = LOOSE_POCKET_TIMING_MS.merge(base_timing) { |_k, mad, base| base || mad }
  swing = (ENV["SWING"] || [cfg[:swing] + 6, 68].min).to_f
  bpm = cfg[:bpm]
  if delicious_pocket_enabled?
    ratio = (ENV["DELICIOUS_RATIO"] || DELICIOUS_POCKET_RATIO).to_f
    bpm = (bpm * ratio).round(1)
    swing = [swing + 4, 72].min
    timing = timing.merge(snare: -32..-14, hat_up: 26..44, kick_sync: 14..28)
  end
  cfg.merge(feel: :loose_pocket, swing: swing, timing: timing, bpm: bpm, delicious: delicious_pocket_enabled?)
end

def vlc_eq_chain
  VLC_EQ_BANDS.map { |f, g| "equalizer=f=#{f}:t=o:w=1:g=#{g}" }.join(",")
end

# VLC audio effects chain — loudnorm, 10-band EQ, compressor, spatializer, stereo widener.
def vlc_audio_filters(input_tag, out_tag: "out")
  return ["[#{input_tag}]alimiter=limit=0.91:level_out=0.92[#{out_tag}]"] unless vlc_effects_enabled?
  c = VLC_COMPRESSOR
  eq = vlc_eq_chain
  [
    "[#{input_tag}]loudnorm=I=-17:TP=-1.2:LRA=8[vln]",
    "[vln]#{eq}[veq]",
    "[veq]acompressor=threshold=#{c[:threshold]}dB:ratio=#{c[:ratio]}:attack=#{c[:attack]}:release=#{c[:release]}:" \
    "makeup=#{c[:makeup]}:mix=#{c[:mix]}[vcomp]",
    "[vcomp]aphaser=in_gain=0.42:out_gain=0.72:delay=3:decay=0.28:speed=0.35:type=triangular[vph]",
    "[vph]aecho=0.38:0.42:38|76|114:0.22|0.14|0.08[vspat]",
    "[vspat]extrastereo=m=1.30[vwide]",
    "[vwide]stereotools=mode=lr>ms:slev=1.22:mlev=0.90[vms]",
    "[vms]stereotools=mode=ms>lr:base=0.16[vst]",
    "[vst]alimiter=limit=0.94:level_out=0.93[#{out_tag}]"
  ]
end

def madlib_drum_filters(input_tag = "bed", out_tag: "mad_out")
  sat = Math.tanh(2.6).round(6)
  [
    "[#{input_tag}]asplit=2[md][sc]",
    "[md]acrusher=bits=10:samples=1.69:mix=0.55[cr]",
    "[cr]aeval=exprs='tanh(2.6*val(0))/#{sat}|tanh(2.6*val(1))/#{sat}'[sat]",
    "[sat]acompressor=threshold=-17dB:ratio=8:attack=2:release=65:makeup=5.5[comp]",
    "[comp]equalizer=f=55:t=o:w=0.75:g=7,equalizer=f=2400:t=o:w=2:g=-5,equalizer=f=9000:t=o:w=2:g=-3[eq]",
    "[eq]extrastereo=m=1.14[wide]",
    "[wide][sc]sidechaincompress=threshold=-19dB:ratio=7:attack=1:release=75:level_sc=0.85[punched]",
    "[punched]vibrato=f=0.22:d=0.005[wow]",
    "[wow]aeval=exprs='val(0)+0.014*(random(0)-0.5)|val(1)+0.014*(random(1)-0.5)'[#{out_tag}]"
  ]
end

def madlib_master_filters(input_tag = "bed")
  filt = []
  filt.concat(madlib_drum_filters(input_tag, out_tag: "mad_out"))
  filt.concat(vlc_audio_filters("mad_out"))
  filt
end

# Pure drums: MPC one-shots + pocket microtiming + SP-1200 dirt.
def render_madlib_drums(destination = File.join(ROOT, "renders", "beats", "beat.wav"), bars_count = nil)
  require_tools! "ffmpeg"
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  cfg      = madlib_resolve_config
  n_bars   = bars_count || (ENV["BARS"] ? bars : 32)
  beat_p   = 60.0 / cfg[:bpm]
  duration = (beat_p * 4.0 * n_bars).round(3)
  events   = dilla_schedule(
    n_bars, beat_p, [], drums_only: true,
    swing: cfg[:swing], feel: :loose_pocket, timing: cfg[:timing]
  )
  kit = {
    kick: load_mono_sample(drum_sample_path("kick.wav")),
    snare: load_mono_sample(drum_sample_path("snare.wav")),
    ghost: load_mono_sample(drum_sample_path("ghost.wav")),
    hat: load_mono_sample(drum_sample_path("hat.wav")),
    open_hat: load_mono_sample(drum_sample_path("open_hat.wav"))
  }
  drum_tmp = File.join(ROOT, ".madlib_drums.wav")
  render_sample_bus_wav(
    drum_tmp,
    events, duration, kit,
    kick: :kick, snare: :snare, ghost: :ghost, hat: :hat, open: :open_hat
  )

  command = ["ffmpeg", "-y", "-i", drum_tmp,
             "-f", "lavfi", "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=0.028:d=#{duration}"]
  filt = [
    "[0:a]aformat=channel_layouts=stereo[drums]",
    "[1:a]highpass=f=120,lowpass=f=9000,volume=0.22[dust]",
    "[drums][dust]amix=inputs=2:weights=1.0 0.35:duration=first[bed]"
  ]
  filt.concat(madlib_master_filters("bed"))
  ext = File.extname(destination).downcase
  args = ext == ".mp3" ? codec_for(destination) : ["-c:a", "pcm_s16le"]
  command += ["-filter_complex", filt.join(";"), "-map", "[out]", "-t", duration.to_s, *args, destination]
  sh!(*command)
  FileUtils.rm_f(drum_tmp)
  fx = []
  fx << "delicious" if cfg[:delicious]
  fx << "vlc-all" if vlc_effects_enabled?
  puts "wrote #{destination} (#{cfg[:bpm].to_i} BPM, #{n_bars} bars, TRACK=#{cfg[:track]}, #{fx.join('+')})"
end

def render_madlib_album(output_dir = File.join(ROOT, "renders", "beats"))
  FileUtils.mkdir_p(output_dir)
  LOOSE_POCKET_BEAT_CATALOG.each do |entry|
    base = File.join(output_dir, entry[:out])
    prev = %w[TRACK BARS BPM SWING DELICIOUS VLC].each_with_object({}) { |k, h| h[k] = ENV[k] }
    ENV["TRACK"] = entry[:track].to_s
    ENV["BARS"]  = entry[:bars].to_s
    ENV["DELICIOUS"] = "1"
    ENV["VLC"] = "1"
    render_madlib_drums("#{base}.wav", entry[:bars])
    render_madlib_drums("#{base}.mp3", entry[:bars])
  ensure
    prev.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end
  puts "loose_pocket batch: #{LOOSE_POCKET_BEAT_CATALOG.length} beats (wav+mp3) → #{output_dir}"
end

# =============================================================================
# HIP-HOP SYNTH (dilla_hiphop.rb)
# =============================================================================

# Batch-render tape presets — neutral session_XX filenames (no album track names).
def render_slum_album(output_dir = File.join(ROOT, "renders"))
  FileUtils.mkdir_p(output_dir)
  TAPE_RENDER_CATALOG.each_with_index do |entry, i|
    dest = File.join(output_dir, "#{entry[:out]}.mp3")
    prev = %w[TRACK BARS BPM PROGRESSION SWING SONITEX SONITEX_PRESET ANALOG_CHAIN].each_with_object({}) { |k, h| h[k] = ENV[k] }
    ENV["TRACK"]   = entry[:preset].to_s
    ENV["BARS"]    = entry[:bars].to_s
    ENV["SONITEX"] = "heavy"
    ENV["SONITEX_PRESET"] = "heavy"
    ENV["ANALOG_CHAIN"] = ANALOG_CHAIN_ROTATE[i % ANALOG_CHAIN_ROTATE.length].to_s
    render_dilla(dest, entry[:bars])
  ensure
    prev.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end
  puts "tape batch: #{TAPE_RENDER_CATALOG.length} sessions → #{output_dir}"
end

# Full-length MPC hip-hop: Slum Village Vol. 1/2 presets via TRACK= env.
def render_hiphop(destination = File.join(OUTPUT_DIR, "hiphop.mp3"))
  prev = %w[BPM BARS TRACK PROGRESSION SWING].each_with_object({}) { |k, h| h[k] = ENV[k] }
  ENV["TRACK"] ||= "syncopated_slash_ninth"
  ENV["BARS"] ||= "63"
  render_dilla(destination, bars)
ensure
  prev.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
end

# =============================================================================
# TECHNO SYNTH (techno_hate.rb) — acid-industrial hybrid at 142 BPM
# =============================================================================

def render_techno(destination = File.join(OUTPUT_DIR, "techno_hate.mp3"))
  require_tools! "ffmpeg"
  n_bars = [bars, TECHNO_BARS].max
  beat  = 60.0 / TECHNO_BPM
  bar   = beat * 4
  step  = beat / 4
  total = (bar * n_bars).round(3)

  kick_per_bar = Array.new(TECHNO_BARS) { [0, 4, 8, 12] }
  kick_per_bar[7] = [0, 4, 8, 12, 14, 15]
  clap_per_bar = Array.new(TECHNO_BARS) { [4, 12] }
  clap_per_bar[3] = [4, 12, 14]; clap_per_bar[7] = [4, 10, 12, 14]
  hat_per_bar  = Array.new(TECHNO_BARS) { [2, 6, 10, 14] }
  hat_per_bar[3] = []; hat_per_bar[5] = [0, 2, 4, 6, 8, 10, 12, 14]
  open_per_bar = Array.new(TECHNO_BARS) { [] }
  open_per_bar[3] = [14]; open_per_bar[7] = [14]
  acid_steps = [0, 3, 6, 8, 11, 14]
  bass_notes = [65.41, 65.41, 87.31, 65.41, 98.00, 98.00, 87.31, 65.41]

  cycle = (bar * TECHNO_BARS).round(6)
  kicks = TECHNO_BARS.times.flat_map { |b| kick_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  claps = TECHNO_BARS.times.flat_map { |b| clap_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  hats  = TECHNO_BARS.times.flat_map { |b| hat_per_bar[b].map  { |s| (b * bar + s * step).round(6) } }
  opens = TECHNO_BARS.times.flat_map { |b| open_per_bar[b].map { |s| (b * bar + s * step).round(6) } }
  acid_hits = TECHNO_BARS.times.flat_map { |b| bass_notes[b].then { |f| acid_steps.map { |s| [(b * bar + s * step).round(6), f] } } }

  kick_sig = kicks.map { |t|
    tm = (t % cycle).round(6)
    dt = "mod(t,#{cycle})-#{tm}"
    "between(mod(t,#{cycle}),#{tm},#{(tm + 0.18).round(6)})*0.95*exp(-#{dt}*8)*sin(2*PI*(110*#{dt}-250*#{dt}*#{dt}))"
  }
  acid_sig = acid_hits.map { |(t, f)|
    tm = (t % cycle).round(6)
    dt = "mod(t,#{cycle})-#{tm}"
    "between(mod(t,#{cycle}),#{tm},#{(tm + 0.14).round(6)})*0.6*exp(-#{dt}*9)*sin(2*PI*#{f}*#{dt})"
  }
  clap_env = claps.flat_map { |t|
    tm = (t % cycle).round(6)
    t1 = (tm + 0.012).round(6); t2 = (tm + 0.024).round(6)
    dt0 = "mod(t,#{cycle})-#{tm}"; dt1 = "mod(t,#{cycle})-#{t1}"; dt2 = "mod(t,#{cycle})-#{t2}"
    ["between(mod(t,#{cycle}),#{tm},#{(tm + 0.04).round(6)})*exp(-#{dt0}*40)",
     "between(mod(t,#{cycle}),#{t1},#{(t1 + 0.04).round(6)})*exp(-#{dt1}*50)",
     "between(mod(t,#{cycle}),#{t2},#{(t2 + 0.05).round(6)})*exp(-#{dt2}*30)"]
  }
  hat_env = hats.map  { |t| tm = (t % cycle).round(6); dt = "mod(t,#{cycle})-#{tm}"; "between(mod(t,#{cycle}),#{tm},#{(tm + 0.04).round(6)})*exp(-#{dt}*70)" }
  opn_env = opens.map { |t| tm = (t % cycle).round(6); dt = "mod(t,#{cycle})-#{tm}"; "between(mod(t,#{cycle}),#{tm},#{(tm + 0.5).round(6)})*exp(-#{dt}*10)" }

  filt = <<~F
    [0:a]aformat=channel_layouts=stereo,equalizer=f=55:t=o:w=0.7:g=4,
         aeval='tanh(val(0)*2.5)/tanh(2.5)|tanh(val(1)*2.5)/tanh(2.5)',
         acompressor=threshold=-10dB:ratio=6:attack=1:release=40:makeup=3[kick];
    [1:a]aformat=channel_layouts=stereo,
         aeval='tanh(val(0)*3.5)/tanh(3.5)|tanh(val(1)*3.5)/tanh(3.5)',
         equalizer=f=300:t=o:w=2:g=3,equalizer=f=1500:t=o:w=2:g=4,
         lowpass=f=4000[acid];
    [2:a]aformat=channel_layouts=stereo,asplit=3[nc][nh][no];
    [nc]volume='#{safe_volume_env(clap_env)}*0.6':eval=frame,bandpass=f=1500:w=2000,
        aecho=0.5:0.4:30|60:0.2|0.1[clap];
    [nh]volume='#{safe_volume_env(hat_env)}*0.4':eval=frame,highpass=f=8000[hat];
    [no]volume='#{safe_volume_env(opn_env)}*0.3':eval=frame,bandpass=f=7000:w=5000[open];
    [kick][acid][clap][hat][open]amix=inputs=5:weights=1.4 1.0 0.7 0.5 0.4:duration=longest[drums];
    [drums]highpass=f=30,acompressor=threshold=-14dB:ratio=8:attack=1:release=50:makeup=4[drums_comp];
    [drums_comp]aeval='tanh(val(0)*1.8)/tanh(1.8)|tanh(val(1)*1.8)/tanh(1.8)'[drums_sat];
    [drums_sat]equalizer=f=80:t=o:w=0.8:g=2,equalizer=f=8000:t=o:w=2:g=2[master_eq];
    [master_eq]alimiter=level_in=1.0:level_out=0.90:limit=0.85:attack=2:release=20[out]
  F

  FileUtils.mkdir_p(File.dirname(destination))
  sh! "ffmpeg", "-y",
      *lavfi("aevalsrc='#{expr_sum(kick_sig)}':d=#{total}:s=#{SAMPLE_RATE}"),
      *lavfi("aevalsrc='#{expr_sum(acid_sig)}':d=#{total}:s=#{SAMPLE_RATE}"),
      *lavfi("anoisesrc=color=white:r=#{SAMPLE_RATE}:amplitude=0.5:d=#{total}"),
      "-filter_complex", filt.tr("\n", " "), "-map", "[out]", "-b:a", "320k", destination
  puts "wrote #{destination}"
end

# =============================================================================
# VOCAL MIXES v7–v11 (make.rb)
# =============================================================================

def mix_out_path(ver)
  File.join(OUTPUT_DIR, "final_mix_#{ver}.mp3")
end

def mix_tmp(ver, name)
  "/tmp/#{ver}_#{name}.wav"
end

def mix_loop_beat
  ["-stream_loop", "-1", "-i", VOICEMAILS_BEAT, "-t", MIX_DUR.to_s]
end

def mix_beat_ms(bpm)
  (60_000 / bpm).to_i
end

def mix_dotted_8th(bpm)
  (mix_beat_ms(bpm) * 0.75).to_i
end

def mix_half(bpm)
  (mix_beat_ms(bpm) * 2).to_i
end

def mix_render(label, dest, inputs:, filter:, map:, args: ["-ar", "44100"])
  puts ">>> #{label}"
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filter.tr("\n", " "), "-map", map, *args, dest
end

def mix_v7
  ver = "v7"; d8 = mix_dotted_8th(MIX_BPM)
  beat_pre, vocals_pre, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "crackle")
  mix_render "beat: M/S + EQ + crunch + room", beat_pre, inputs: ["-i", VOICEMAILS_BEAT], map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo,volume=1.0[raw];
    [raw]pan=stereo|c0=c0+c1|c1=c0+c1[mid];
    [raw]pan=stereo|c0=c0-c1|c1=c1-c0[side];
    [mid]equalizer=f=60:t=o:w=0.8:g=7,equalizer=f=120:t=o:w=1:g=3,equalizer=f=400:t=o:w=1:g=-2,equalizer=f=2000:t=o:w=2:g=-3,
         acompressor=threshold=-20dB:ratio=6:attack=2:release=80:makeup=3[mid_eq];
    [side]equalizer=f=300:t=o:w=2:g=-4,equalizer=f=6000:t=o:w=3:g=4,acompressor=threshold=-18dB:ratio=3:attack=8:release=120:makeup=2[side_eq];
    [mid_eq][side_eq]amix=inputs=2:weights=1.4 0.6[beat_mix];
    [beat_mix]acrusher=level_in=1.2:level_out=0.9:bits=14:mode=log:aa=1[beat_crush];
    [beat_crush]aecho=0.6:0.4:30|60|90:0.15|0.08|0.04[beat_room];
    [beat_room]acompressor=threshold=-16dB:ratio=4:attack=3:release=60:makeup=2[beat_comp];
    [beat_comp]volume=0.88[beat_out]
  F
  mix_render "vocals: clear + shiny + precise", vocals_pre, inputs: ["-i", VOCALS[:processed]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=180:t=o:w=1:g=-10,equalizer=f=300:t=o:w=1:g=-4,equalizer=f=900:t=o:w=1.5:g=2,
          equalizer=f=2500:t=o:w=2:g=5,equalizer=f=5000:t=o:w=2:g=4,equalizer=f=10000:t=o:w=3:g=5,equalizer=f=16000:t=o:w=3:g=4[voc_eq];
    [voc_eq]acompressor=threshold=-16dB:ratio=2.5:attack=5:release=80:makeup=5[voc_comp];
    [voc_comp]asplit=4[va][vb][vc][vd];
    [va]volume=1.0[voc_dry];
    [vb]aecho=0.7:0.6:350|700:0.3|0.12,equalizer=f=300:t=h:w=1:g=0[voc_plate];
    [vc]adelay=#{d8}|#{d8 * 2},equalizer=f=400:t=h:w=1:g=0[voc_ping];
    [vd]chorus=0.5:0.9:20|25:0.1|0.08:0.15|0.2:1.0|1.0[voc_shimmer];
    [voc_dry][voc_plate][voc_ping][voc_shimmer]amix=inputs=4:weights=1.4 0.4 0.35 0.5[voc_wet];
    [voc_wet]volume=1.35[voc_out]
  F
  mix_render "crackle", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.025:d=300"), map: "[crack_out]", filter: <<~F
    [0:a]equalizer=f=3000:t=o:w=3:g=5,equalizer=f=80:t=o:w=1:g=-15,volume=0.18[crack_out]
  F
  mix_render "master v7", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.82[b];[1:a]volume=1.25[v];[2:a]volume=0.22[c];
    [b][v][c]amix=inputs=3:duration=first:weights=1 1.25 0.22[raw_mix];
    [raw_mix]acompressor=threshold=-22dB:ratio=3:attack=5:release=120:makeup=3[comp_low];
    [comp_low]acompressor=threshold=-12dB:ratio=5:attack=2:release=60:makeup=3[comp_mid];
    [comp_mid]acompressor=threshold=-6dB:ratio=10:attack=1:release=30:makeup=2[comp_hi];
    [comp_hi]equalizer=f=55:t=o:w=0.7:g=5,equalizer=f=160:t=o:w=1:g=2,equalizer=f=500:t=o:w=1.5:g=-2,equalizer=f=3000:t=o:w=2:g=-1,equalizer=f=10000:t=o:w=2:g=3[master_eq];
    [master_eq]aeval='tanh(val(0)*2.5)/tanh(2.5)|tanh(val(1)*2.5)/tanh(2.5)'[tape_sat];
    [tape_sat]aecho=0.3:0.2:18:0.06[air];
    [air]alimiter=level_in=1.0:level_out=0.98:limit=0.92:attack=3:release=25:level=disabled[limited];
    [limited]volume=0.96[out]
  F
end

def mix_v8
  ver = "v8"
  beat_pre, vocals_pre, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "crackle")
  mix_render "beat v8", beat_pre, inputs: mix_loop_beat, map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]equalizer=f=55:t=o:w=0.7:g=9,equalizer=f=120:t=o:w=1:g=4,equalizer=f=350:t=o:w=1.5:g=-6,equalizer=f=1000:t=o:w=2:g=-8,equalizer=f=4000:t=o:w=2:g=-5,equalizer=f=10000:t=o:w=3:g=-4[sub_heavy];
    [sub_heavy]acompressor=threshold=-18dB:ratio=8:attack=1:release=40:makeup=4[beat_comp];
    [beat_comp]tremolo=f=0.4:d=0.04[beat_wobble];
    [beat_wobble]acrusher=level_in=1.1:level_out=0.85:bits=16:mode=log:aa=1[beat_grit];
    [beat_grit]volume=0.75[beat_out]
  F
  mix_render "vocals v8", vocals_pre, inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=200:t=o:w=1:g=-10,equalizer=f=1200:t=o:w=2:g=3,equalizer=f=3000:t=o:w=2:g=6,equalizer=f=6000:t=o:w=2:g=4,equalizer=f=12000:t=o:w=3:g=3[voc_eq];
    [voc_eq]acompressor=threshold=-18dB:ratio=4:attack=3:release=60:makeup=6[voc_comp];
    [voc_comp]asplit=2[vd][vr];[vd]volume=1.0[voc_dry];
    [vr]aecho=0.5:0.3:80|160:0.12|0.05[voc_tiny_room];
    [voc_dry][voc_tiny_room]amix=inputs=2:weights=1.0 0.3[voc_out]
  F
  mix_render "crackle v8", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.05:d=#{MIX_DUR}"), map: "[crack_out]", filter: <<~F
    [0:a]equalizer=f=4000:t=o:w=3:g=8,equalizer=f=80:t=o:w=1:g=-20,volume=0.3[crack_out]
  F
  mix_render "master v8", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.85[b];[1:a]volume=1.4[v];[2:a]volume=0.35[c];
    [b][v][c]amix=inputs=3:duration=first:weights=1 1.4 0.35[mix];
    [mix]equalizer=f=60:t=o:w=0.8:g=3,equalizer=f=5000:t=o:w=2:g=2[master_eq];
    [master_eq]aeval='tanh(val(0)*1.8)/tanh(1.8)|tanh(val(1)*1.8)/tanh(1.8)'[tape];
    [tape]alimiter=level_in=1.0:level_out=0.97:limit=0.94:attack=5:release=80:level=disabled[out]
  F
end

def mix_v9
  ver = "v9"; slow = 0.92; bpm = MIX_BPM * slow; d8 = mix_dotted_8th(bpm); hf = mix_half(bpm)
  beat_pre, vocals_pre, pad, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "pad"), mix_tmp(ver, "crackle")
  mix_render "beat v9", beat_pre, inputs: mix_loop_beat, map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]asetrate=44100*0.7937,aresample=44100,atempo=#{slow}[pitched];
    [pitched]equalizer=f=50:t=o:w=0.7:g=9,equalizer=f=100:t=o:w=1:g=5,equalizer=f=600:t=o:w=2:g=-3,equalizer=f=3000:t=o:w=2:g=-5[beat_eq];
    [beat_eq]aphaser=in_gain=0.6:out_gain=0.8:delay=4:decay=0.5:speed=0.4:type=triangular[beat_phase];
    [beat_phase]aecho=0.7:0.5:200|400:0.3|0.15[beat_echo];
    [beat_echo]acompressor=threshold=-16dB:ratio=5:attack=4:release=80:makeup=3[beat_comp];
    [beat_comp]volume=0.78[beat_out]
  F
  mix_render "vocals v9", vocals_pre, inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=150:t=o:w=1:g=-8,equalizer=f=800:t=o:w=2:g=2,equalizer=f=3000:t=o:w=2:g=3,equalizer=f=8000:t=o:w=3:g=5,equalizer=f=14000:t=o:w=3:g=4[voc_eq];
    [voc_eq]acompressor=threshold=-14dB:ratio=2.5:attack=8:release=200:makeup=5[voc_comp];
    [voc_comp]asplit=4[va][vb][vc][vd];[va]volume=0.9[voc_dry];
    [vb]aecho=0.88:0.92:800|1600|3200|6400:0.6|0.4|0.22|0.10[voc_cathedral];
    [vc]chorus=0.7:0.9:35|45|55:0.4|0.32|0.25:0.3|0.4|0.25:1.8|2.2|1.4[voc_shimmer];
    [vd]adelay=#{d8}|#{hf},acrusher=level_in=1.8:level_out=0.5:bits=6:mode=log:aa=1[voc_bit];
    [voc_dry][voc_cathedral][voc_shimmer][voc_bit]amix=inputs=4:weights=1 0.7 0.5 0.2[voc_wet];
    [voc_wet]aphaser=in_gain=0.5:out_gain=0.7:delay=3:decay=0.4:speed=0.2:type=sinusoidal[voc_phase];
    [voc_phase]flanger=delay=6:depth=5:speed=0.2:shape=sinusoidal[voc_flange];
    [voc_flange]volume=1.3[voc_out]
  F
  mix_render "pad v9", pad, inputs: lavfi("aevalsrc=0.12*sin(2*PI*138.59*t)+0.10*sin(2*PI*277.18*t)+0.08*sin(2*PI*349.23*t)+0.09*sin(2*PI*415.30*t)+0.05*sin(2*PI*554.37*t):s=44100:c=stereo:d=#{MIX_DUR}"), map: "[pad_out]", filter: <<~F
    [0:a]equalizer=f=800:t=o:w=2:g=-6,equalizer=f=3000:t=o:w=2:g=-10,aecho=0.9:0.85:600|1200:0.5|0.3[pad_echo];
    [pad_echo]chorus=0.6:0.8:40|50:0.3|0.25:0.4|0.3:1.5|2.0[pad_chorus];
    [pad_chorus]aphaser=in_gain=0.6:out_gain=0.8:delay=5:decay=0.6:speed=0.15:type=sinusoidal[pad_phase];
    [pad_phase]volume=0.22[pad_out]
  F
  mix_render "crackle v9", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.02:d=#{MIX_DUR}"), map: "[crack_out]", filter: "[0:a]equalizer=f=5000:t=o:w=3:g=6,equalizer=f=80:t=o:w=1:g=-18,volume=0.12[crack_out]"
  mix_render "master v9", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", pad, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.80[b];[1:a]volume=1.20[v];[2:a]volume=0.25[p];[3:a]volume=0.15[c];
    [b][v][p][c]amix=inputs=4:duration=first:weights=1 1.2 0.25 0.15[mix];
    [mix]acompressor=threshold=-22dB:ratio=3:attack=8:release=200:makeup=3[comp1];
    [comp1]acompressor=threshold=-10dB:ratio=6:attack=2:release=60:makeup=2[comp2];
    [comp2]equalizer=f=50:t=o:w=0.7:g=4,equalizer=f=200:t=o:w=1:g=2,equalizer=f=2000:t=o:w=1.5:g=-2,equalizer=f=12000:t=o:w=2:g=3[master_eq];
    [master_eq]aeval='tanh(val(0)*3.0)/tanh(3.0)|tanh(val(1)*3.0)/tanh(3.0)'[tape];
    [tape]aecho=0.25:0.18:25:0.08[master_air];
    [master_air]alimiter=level_in=1.0:level_out=0.98:limit=0.93:attack=2:release=20:level=disabled[out]
  F
end

def mix_v10
  ver = "v10"; d8 = mix_dotted_8th(MIX_BPM)
  beat_pre, vocals_pre, pad, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "pad"), mix_tmp(ver, "crackle")
  mix_render "beat v10", beat_pre, inputs: mix_loop_beat, map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]equalizer=f=50:t=o:w=0.8:g=6,equalizer=f=100:t=o:w=1:g=4,equalizer=f=250:t=o:w=1:g=2,equalizer=f=700:t=o:w=1.5:g=-1,equalizer=f=3000:t=o:w=2:g=1,equalizer=f=8000:t=o:w=2:g=2,equalizer=f=14000:t=o:w=3:g=3[beat_eq];
    [beat_eq]acompressor=threshold=-22dB:ratio=3:attack=15:release=200:makeup=3[tape_comp];
    [tape_comp]aeval='#{HEDD}'[hedd];
    [hedd]aecho=0.5:0.3:25|50:0.1|0.05[spring];
    [spring]volume=0.82[beat_out]
  F
  mix_render "vocals v10", vocals_pre, inputs: ["-i", VOCALS[:precise]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=160:t=o:w=1:g=-10,equalizer=f=350:t=o:w=1:g=-4,equalizer=f=1000:t=o:w=1.5:g=2,equalizer=f=2500:t=o:w=2:g=6,equalizer=f=5000:t=o:w=2:g=5,equalizer=f=10000:t=o:w=3:g=6,equalizer=f=16000:t=o:w=3:g=5[voc_eq];
    [voc_eq]acompressor=threshold=-16dB:ratio=2.5:attack=6:release=100:makeup=5[voc_comp];
    [voc_comp]aeval='#{HEDD}'[voc_hedd];
    [voc_hedd]asplit=3[va][vb][vc];[va]volume=1.0[vdry];
    [vb]adelay=#{d8}|#{d8},aecho=0.65:0.55:400|800:0.35|0.15[vplate];
    [vc]chorus=0.5:0.9:18|22:0.08|0.06:0.2|0.25:1.0|1.0[vdouble];
    [vdry][vplate][vdouble]amix=inputs=3:weights=1.4 0.45 0.35[voc_out]
  F
  mix_render "pad v10", pad, inputs: lavfi("aevalsrc=0.14*sin(2*PI*130.81*t)+0.11*sin(2*PI*261.63*t)+0.09*sin(2*PI*311.13*t)+0.10*sin(2*PI*392.00*t)+0.06*sin(2*PI*523.25*t):s=44100:c=stereo:d=#{MIX_DUR}"), map: "[pad_out]", filter: <<~F
    [0:a]equalizer=f=1000:t=o:w=2:g=-5,equalizer=f=4000:t=o:w=2:g=-10,equalizer=f=100:t=o:w=1:g=3[pad_eq];
    [pad_eq]aecho=0.85:0.8:500|1000:0.4|0.2[pad_echo];
    [pad_echo]chorus=0.5:0.8:35|45:0.25|0.2:0.35|0.25:1.2|1.6[pad_chorus];
    [pad_chorus]volume=0.18[pad_out]
  F
  mix_render "crackle v10", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.015:d=#{MIX_DUR}"), map: "[crack_out]", filter: "[0:a]equalizer=f=4500:t=o:w=3:g=5,equalizer=f=80:t=o:w=1:g=-18,volume=0.10[crack_out]"
  mix_render "master v10", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", pad, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.84[b];[1:a]volume=1.22[v];[2:a]volume=0.20[p];[3:a]volume=0.12[c];
    [b][v][p][c]amix=inputs=4:duration=first:weights=1 1.22 0.20 0.12[mix];
    [mix]acompressor=threshold=-24dB:ratio=2:attack=20:release=300:makeup=2[glue];
    [glue]aeval='#{HEDD}'[bus_hedd];
    [bus_hedd]equalizer=f=45:t=o:w=0.7:g=3,equalizer=f=150:t=o:w=1:g=2,equalizer=f=700:t=o:w=1.5:g=-1,equalizer=f=12000:t=o:w=2:g=2[master_eq];
    [master_eq]aeval='tanh(val(0)*2.2)/tanh(2.2)|tanh(val(1)*2.2)/tanh(2.2)'[tape_sat];
    [tape_sat]aecho=0.2:0.15:15:0.05[air];
    [air]alimiter=level_in=1.0:level_out=0.98:limit=0.93:attack=4:release=40:level=disabled[out]
  F
end

def mix_v11
  ver = "v11"; d8 = mix_dotted_8th(MIX_BPM)
  beat_pre, vocals_pre, crackle = mix_tmp(ver, "beat"), mix_tmp(ver, "vocals"), mix_tmp(ver, "crackle")
  mix_render "beat v11", beat_pre, inputs: mix_loop_beat, map: "[beat_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[raw];
    [raw]pan=stereo|c0=c0+c1|c1=c0+c1[mid];[raw]pan=stereo|c0=c0-c1|c1=c1-c0[side];
    [mid]lowpass=f=280[mid_bass];
    [mid_bass]equalizer=f=60:t=o:w=0.8:g=6,equalizer=f=120:t=o:w=1:g=3,acompressor=threshold=-18dB:ratio=6:attack=2:release=50:makeup=4[mid_punch];
    [side]equalizer=f=2000:t=o:w=0.8:g=-12,equalizer=f=2200:t=o:w=0.5:g=-8,lowpass=f=9000,equalizer=f=300:t=o:w=1:g=-3,equalizer=f=5000:t=o:w=2:g=2[side_clean];
    [side_clean]tremolo=f=0.35:d=0.05[side_wobble];
    [side_wobble]aphaser=in_gain=0.6:out_gain=0.8:delay=3:decay=0.4:speed=0.3:type=triangular[side_phase];
    [mid_punch][side_phase]amix=inputs=2:weights=1.3 0.7[beat_mix];
    [beat_mix]acompressor=threshold=-16dB:ratio=3:attack=5:release=100:makeup=2[beat_comp];
    [beat_comp]volume=0.82[beat_out]
  F
  mix_render "vocals v11", vocals_pre, inputs: ["-i", VOCALS[:original]], map: "[voc_out]", filter: <<~F
    [0:a]aformat=sample_rates=44100:channel_layouts=stereo[vraw];
    [vraw]equalizer=f=180:t=o:w=1:g=-8,equalizer=f=600:t=o:w=1.5:g=2,equalizer=f=2000:t=o:w=0.8:g=-6,equalizer=f=3000:t=o:w=2:g=5,equalizer=f=7000:t=o:w=2:g=4,equalizer=f=12000:t=o:w=3:g=2,lowpass=f=14000[voc_eq];
    [voc_eq]acompressor=threshold=-14dB:ratio=2.5:attack=8:release=150:makeup=5[voc_comp];
    [voc_comp]asplit=3[va][vb][vc];[va]volume=1.0[vdry];
    [vb]aecho=0.75:0.65:350|700:0.35|0.15[vplate];
    [vc]adelay=#{d8}|#{d8 * 2},chorus=0.5:0.8:20|25:0.08|0.06:0.2|0.25:1.0|1.0[vshine];
    [vdry][vplate][vshine]amix=inputs=3:weights=1.3 0.4 0.3[voc_wet];
    [voc_wet]aphaser=in_gain=0.5:out_gain=0.7:delay=2:decay=0.3:speed=0.25:type=sinusoidal[voc_phase];
    [voc_phase]volume=1.3[voc_out]
  F
  mix_render "crackle v11", crackle, inputs: lavfi("anoisesrc=r=44100:color=pink:amplitude=0.012:d=#{MIX_DUR}"), map: "[crack_out]", filter: "[0:a]equalizer=f=5000:t=o:w=3:g=4,equalizer=f=80:t=o:w=1:g=-18,volume=0.10[crack_out]"
  mix_render "master v11", mix_out_path(ver), inputs: ["-i", beat_pre, "-i", vocals_pre, "-i", crackle], map: "[out]", args: ["-b:a", "320k"], filter: <<~F
    [0:a]volume=0.85[b];[1:a]volume=1.25[v];[2:a]volume=0.12[c];
    [b][v][c]amix=inputs=3:duration=first:weights=1 1.25 0.12[mix];
    [mix]acompressor=threshold=-20dB:ratio=2.5:attack=18:release=250:makeup=3[glue];
    [glue]equalizer=f=55:t=o:w=0.8:g=4,equalizer=f=2000:t=o:w=0.6:g=-3,equalizer=f=8000:t=o:w=2:g=1,lowpass=f=16000[master_eq];
    [master_eq]aeval='tanh(val(0)*2.0)/tanh(2.0)|tanh(val(1)*2.0)/tanh(2.0)'[tape];
    [tape]aphaser=in_gain=0.3:out_gain=0.5:delay=2:decay=0.3:speed=0.15:type=sinusoidal[master_phase];
    [master_phase]alimiter=level_in=1.0:level_out=0.97:limit=0.93:attack=5:release=60:level=disabled[out]
  F
end

MIX_RECIPES = { "v7" => method(:mix_v7), "v8" => method(:mix_v8), "v9" => method(:mix_v9),
                "v10" => method(:mix_v10), "v11" => method(:mix_v11) }.freeze

def run_mix(ver = "v11")
  abort "unknown mix: #{ver}  have: #{MIX_RECIPES.keys.join(', ')}" unless MIX_RECIPES[ver]
  MIX_RECIPES[ver].call
  puts "done -> #{mix_out_path(ver)}"
  render_liveset(stems_load_manifest["active"] || "default", minutes: LIVESET_MIN) if File.exist?(STEM_MANIFEST)
end

# FFmpeg band-split from a full mix → stem rack files for render_dilla.
def install_stems_from_audio(src, bpm: 90, label: nil)
  src = File.expand_path(src)
  abort "missing source: #{src}" unless File.exist?(src)
  require_tools! "ffmpeg"
  FileUtils.mkdir_p(STEM_DIR)
  slices = {
    STEM_SUB    => "lowpass=f=85,equalizer=f=48:t=o:w=0.8:g=4",
    STEM_MIDS   => "highpass=f=260,lowpass=f=3400,equalizer=f=800:t=o:w=1:g=2",
    STEM_HIGHS  => "highpass=f=2200,lowpass=f=6800",
    STEM_CENTER => "pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1",
    File.join(STEM_DIR, "sides.mp3") => "pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0",
    File.join(STEM_DIR, "bass.mp3") => "highpass=f=55,lowpass=f=220,equalizer=f=90:t=o:w=1:g=3"
  }
  slices.each do |dest, eq|
    mix_render "stem: #{File.basename(dest)}", dest, inputs: ["-i", src], map: "[out]",
               filter: "[0:a]aformat=channel_layouts=stereo,#{eq},loudnorm=I=-20:TP=-1.5:LRA=9[out]",
               args: ["-ar", SAMPLE_RATE.to_s, *codec_for(dest)]
  end
  name = label || File.basename(src, ".*").gsub(/[^A-Za-z0-9_-]/, "_")[0, 32]
  stems_register(name, STEM_DIR, bpm: bpm, source: File.basename(src))
  puts "stems installed from #{src} → #{STEM_DIR}"
end

# One-shot lab setup: synth drum kit + stem rack from bundled soul/gospel sources.
def prepare(src = nil)
  ensure_drum_kit!
  src ||= %w[neosoul.mp3 gospel.mp3 modal.mp3].map { |f| File.join(ROOT, f) }.find { |p| File.exist?(p) }
  abort "no source audio — ruby dilla.rb prepare <path> or add neosoul.mp3 to #{ROOT}" unless src
  install_stems_from_audio(src)
  custom = Dir.glob(File.join(CUSTOM_DRUM_DIR, "*.wav"))
  puts "prepare: kit=#{drum_kit_ready? ? 'ready' : 'partial'}, stems=#{dilla_stem_paths.keys.join('+')}"
  puts "custom drums: drop MPC one-shots in #{CUSTOM_DRUM_DIR} (#{custom.length} loaded)" unless custom.empty?
  puts "custom drums: drop kick.wav snare.wav hat.wav in #{CUSTOM_DRUM_DIR} to override synth kit" if custom.empty?
end

# =============================================================================
# DEMUX (YouTube/path → demucs 6-stem)
# =============================================================================

def demux_fetch_audio(src, start_sec: nil, duration_sec: 150)
  return File.expand_path(src) unless src.match?(%r{\Ahttps?://})
  FileUtils.mkdir_p(DEMUX_DIR)
  raw = File.join(DEMUX_DIR, "yt_#{Time.now.strftime("%Y%m%d_%H%M%S")}.wav")
  require_tools! "yt-dlp"
  args = ["-x", "--audio-format", "wav", "-o", raw]
  if start_sec
    from = start_sec.to_i
    to = from + duration_sec.to_i
    args += ["--download-sections", "*#{from}-#{to}"]
  end
  args << src
  sh! "yt-dlp", *args
  raw
end

def youtube_watch_url(id, start: nil)
  url = "https://www.youtube.com/watch?v=#{id}"
  start ? "#{url}&t=#{start.to_i}" : url
end

FLYLO_LEARNINGS_DIR = File.join(DillaSourceLearn::LEARNINGS_DIR, "flylo_drums").freeze

def flylo_quantize_onsets(onsets, bpm, window: 0.05)
  bar_frames = ((60.0 / bpm) * 4.0 / window).round
  step_frames = [bar_frames / 16.0, 1.0].max
  tally = Hash.new(0)
  onsets.each { |f| tally[((f % bar_frames) / step_frames).round % 16] += 1 }
  tally
end

def flylo_pick_steps(tally, role:, max_sec: 90, bpm: 86)
  max_steps = { kick: 6, snare: 6, hat: 12, perc: 5 }.fetch(role, 5)
  bars = (max_sec / ((60.0 / bpm) * 4.0)).ceil
  min_hits = case role
             when :kick then [bars / 3, 2].max
             when :snare then [bars / 4, 2].max
             when :hat then [bars / 2, 3].max
             else [bars / 4, 2].max
             end
  picks = tally.sort_by { |_, c| -c }.select { |_, c| c >= min_hits }.first(max_steps).map(&:first).sort
  picks.empty? ? tally.sort_by { |_, c| -c }.first(max_steps).map(&:first).sort : picks
end

def flylo_onsets_adaptive(path, filter, role:, bpm:, max_sec: 90)
  da = RadioBergenStudy::DeepAudio
  rms = da.band_rms(path, filter, window: 0.05, max_sec: max_sec)
  return [] if rms.empty?
  sorted = rms.sort
  median = sorted[sorted.length / 2]
  peak = sorted[(sorted.length * 0.88).to_i]
  span = [peak - median, 8.0].max
  thresh, min_gap = case role
                    when :kick then [median + span * 0.52, 7]
                    when :snare then [median + span * 0.46, 5]
                    when :hat then [median + span * 0.28, 2]
                    else [median + span * 0.38, 4]
                    end
  onsets = []
  rms.each_with_index do |val, i|
    next if val < thresh
    prev = i.positive? ? rms[i - 1] : nil
    nxt = rms[i + 1]
    next if prev && val <= prev
    next if nxt && val <= nxt
    onsets << i if onsets.empty? || (i - onsets.last) >= min_gap
  end
  flylo_pick_steps(flylo_quantize_onsets(onsets, bpm), role: role, max_sec: max_sec, bpm: bpm)
end

def flylo_drum_grid_blend_fallback!(grid)
  base = DillaLofiMachine::DRUM_PRESETS[:flylo_abstract]
  {
    flylo_kicks: :kicks, flylo_snares: :snares, flylo_hats: :hats, flylo_perc: :perc
  }.each do |grid_key, preset_key|
    steps = Array(grid[grid_key] || grid[grid_key.to_s])
    next if steps.length >= 3
    fb = Array(base[preset_key])
    grid[grid_key] = (steps + fb).uniq.sort if fb.any?
  end
  grid
end

def flylo_drum_grid_from_stems(stem_dir, bpm: nil, analyze_sec: 120)
  drums = File.join(stem_dir, "drums.wav")
  return nil unless File.file?(drums)
  da = RadioBergenStudy::DeepAudio
  unless bpm
    kick_rms = da.band_rms(drums, "lowpass=f=220,highpass=f=50", max_sec: [analyze_sec, 90].min)
    bpm = da.estimate_bpm(da.detect_onsets(kick_rms, threshold_db: -12, min_gap: 6)) || 86
    bpm = 86 if bpm < 80 || bpm > 95
  end
  grid = {
    bpm: bpm.round,
    swing: DillaLofiMachine::DRUM_PRESETS[:flylo_abstract][:swing],
    source_stem: drums,
    flylo_kicks: flylo_onsets_adaptive(drums, "lowpass=f=220,highpass=f=50", role: :kick,
                                        bpm: bpm, max_sec: analyze_sec),
    flylo_snares: flylo_onsets_adaptive(drums, "lowpass=f=5000,highpass=f=900", role: :snare,
                                         bpm: bpm, max_sec: analyze_sec),
    flylo_hats: flylo_onsets_adaptive(drums, "lowpass=f=14000,highpass=f=5000", role: :hat,
                                      bpm: bpm, max_sec: analyze_sec),
    flylo_perc: flylo_onsets_adaptive(drums, "lowpass=f=8000,highpass=f=2000", role: :perc,
                                      bpm: bpm, max_sec: analyze_sec)
  }
  flylo_drum_grid_blend_fallback!(grid)
end

def learn_flylo_drums!(src, track: :quartal_west_coast, slug: "flylo_camel", apply: false, deep: true)
  DillaSourceLearn.ensure_dir!
  FileUtils.mkdir_p(FLYLO_LEARNINGS_DIR)
  audio_path = if File.exist?(src.to_s)
                 File.expand_path(src)
               else
                 demux_fetch_audio(src, duration_sec: 180)
               end
  stem_candidate = File.join(DEMUX_DIR, "demux", DEMUX_MODEL, File.basename(audio_path, ".*"))
  stem_dir = if File.file?(File.join(stem_candidate, "drums.wav"))
               puts "flylo learn: reusing stems #{stem_candidate}"
               stem_candidate
             else
               demux_six(audio_path)
             end
  demux_deep_bands!(stem_dir) if deep && !File.directory?(File.join(stem_dir, "bands"))
  grid = flylo_drum_grid_from_stems(stem_dir)
  abort "flylo drum learn: could not extract grid from #{stem_dir}" unless grid.is_a?(Hash) && grid[:flylo_kicks]&.any?

  grid[:learned_at] = Time.now.utc.iso8601
  grid[:source] = src.to_s
  grid[:slug] = slug.to_s
  out_path = File.join(FLYLO_LEARNINGS_DIR, "#{slug}.json")
  File.write(out_path, JSON.pretty_generate(grid.transform_keys(&:to_s)) + "\n")

  eng = load_learned_engine(refresh: true)
  track_s = track.to_s
  eng["drum_grids"][track_s] = grid.transform_keys(&:to_s)
  eng["drum_grids"][slug.to_s] = grid.transform_keys(&:to_s)
  eng["track_aliases"]["flylo_camel"] = track_s unless eng["track_aliases"]["flylo_camel"]
  save_learned_engine!(eng)
  remove_instance_variable(:@learned_engine_cache) if instance_variable_defined?(:@learned_engine_cache)

  if apply
    ENV["TRACK"] = track_s
    ENV["FLYLO_DRUM_OVERLAY"] = "1"
    ENV["BPM"] = grid[:bpm].to_s if grid[:bpm]
    ENV["SWING"] = grid[:swing].to_s if grid[:swing]
    ENV["STREAM_LEARN_BIAS"] = "1"
  end
  puts "flylo drums learned: #{slug} → #{track_s} kicks=#{grid[:flylo_kicks].join(',')} " \
       "snares=#{grid[:flylo_snares].join(',')} hats=#{grid[:flylo_hats].join(',')} bpm=#{grid[:bpm]}"
  puts "saved: #{out_path}"
  grid
end

def drum_step_grid_from_wav(path, bpm: nil, analyze_sec: 90)
  return nil unless path && File.file?(path)
  da = RadioBergenStudy::DeepAudio
  window = 0.05
  duration = da.ffprobe(path).dig("format", "duration").to_f
  analyze_sec = [[duration * 0.6, analyze_sec].min, 30].max
  analyze_sec = duration if duration.positive? && duration < analyze_sec

  kick_rms = da.band_rms(path, "lowpass=f=200,highpass=f=60", window: window, max_sec: analyze_sec)
  snare_rms = da.band_rms(path, "lowpass=f=4000,highpass=f=800", window: window, max_sec: analyze_sec)
  hat_rms = da.band_rms(path, "lowpass=f=12000,highpass=f=4000", window: window, max_sec: analyze_sec)

  kick_on = da.detect_onsets(kick_rms, threshold_db: -14.0, min_gap: 4)
  snare_on = da.detect_onsets(snare_rms, threshold_db: -16.0, min_gap: 4)
  hat_on = da.detect_onsets(hat_rms, threshold_db: -18.0, min_gap: 2)

  bpm ||= da.estimate_bpm(kick_on) || da.estimate_bpm(snare_on) || 90
  bar_frames = ((60.0 / bpm) * 4.0 / window).round
  bar_frames = [bar_frames, 16].max
  step_frames = [bar_frames / 16.0, 1.0].max

  quantize = lambda do |onsets|
    onsets.map { |f| ((f % bar_frames) / step_frames).round % 16 }.uniq.sort
  end

  analysis = da.analyze(path)
  {
    bpm_estimate: bpm,
    swing_hint: analysis&.dig(:dynamics, :swing_hint),
    drum_density: analysis&.dig(:drum_density),
    step_grid: {
      kicks: quantize.call(kick_on),
      snares: quantize.call(snare_on),
      hats: quantize.call(hat_on).first(14),
      bar_steps: 16
    }
  }
rescue StandardError => e
  { error: e.message }
end

def demux_six(src)
  audio = demux_fetch_audio(src)
  out = File.join(DEMUX_DIR, "demux")
  FileUtils.mkdir_p(out)
  cmd = demucs_cmd or abort "demucs required — pip install demucs"
  sh!(*cmd, "-n", DEMUX_MODEL, "-o", out, audio)
  stem_dir = File.join(out, DEMUX_MODEL, File.basename(audio, ".*"))
  puts "stems -> #{stem_dir}"
  if stem_dir.start_with?(STEM_DIR) && Dir.exist?(stem_dir) && !stems_scan_set(stem_dir).empty?
    name = File.basename(audio, ".*").gsub(/[^A-Za-z0-9_-]/, "_")[0, 32]
    stems_register(name, stem_dir, source: src)
  end
  stem_dir
end

def demux_slice_band(src, dest, label, eq:)
  mix_render "band: #{label}", dest, inputs: ["-i", src], map: "[out]", filter: "[0:a]#{eq}[out]"
end

def demux_deep_bands!(stem_dir)
  bands = File.join(stem_dir, "bands")
  FileUtils.mkdir_p(bands)
  bass = File.join(stem_dir, "bass.wav"); drums = File.join(stem_dir, "drums.wav")
  guitar = File.join(stem_dir, "guitar.wav"); piano = File.join(stem_dir, "piano.wav"); other = File.join(stem_dir, "other.wav")
  demux_slice_band bass,  File.join(bands, "sub_bass.wav"),    "sub_bass",    eq: "lowpass=f=60"
  demux_slice_band bass,  File.join(bands, "bass_mid.wav"),    "bass_mid",    eq: "highpass=f=60,lowpass=f=200"
  demux_slice_band drums, File.join(bands, "kick.wav"),        "kick",        eq: "lowpass=f=100"
  demux_slice_band drums, File.join(bands, "snare.wav"),       "snare",       eq: "highpass=f=200,lowpass=f=500"
  demux_slice_band drums, File.join(bands, "hats.wav"),        "hats",        eq: "highpass=f=5000"
  demux_slice_band other, File.join(bands, "mids.wav"),        "mids",        eq: "highpass=f=500,lowpass=f=2000"
  demux_slice_band other, File.join(bands, "highs_pluck.wav"), "highs_pluck", eq: "highpass=f=2000,lowpass=f=5000"
  demux_slice_band other, File.join(bands, "air.wav"),         "air",         eq: "highpass=f=5000"
  inst = File.join(bands, "instrumental.wav")
  mix_render "instrumental sum", inst, inputs: ["-i", bass, "-i", drums, "-i", guitar, "-i", piano, "-i", other],
    map: "[out]", filter: "[0:a][1:a][2:a][3:a][4:a]amix=inputs=5:duration=longest[out]"
  demux_slice_band inst, File.join(bands, "center.wav"), "center", eq: "pan=stereo|c0=c0+c1|c1=c0+c1"
  demux_slice_band inst, File.join(bands, "sides.wav"),  "sides",  eq: "pan=stereo|c0=c0-c1|c1=c1-c0"
  puts "bands -> #{bands}"
  bands
end

def demux_deep(src)
  stem_dir = demux_six(src)
  demux_deep_bands!(stem_dir)
  stem_dir
end

def top_pitch_class_indices(pitch_class_hash, limit: 6)
  PITCH_CLASSES.each_with_index
               .sort_by { |name, _| -pitch_class_hash.fetch(name, 0.0).to_f }
               .first(limit)
               .map { |_, idx| idx }
end

def analyze_stem_for_learn(path, stem_name)
  return nil unless path && File.file?(path)
  result = { path: path, stem: stem_name }
  case stem_name
  when "drums.wav", "bass.wav"
    analysis = RadioBergenStudy::DeepAudio.analyze(path)
    if analysis
      result[:bpm_estimate] = analysis[:bpm_estimate]
      result[:swing_hint] = analysis.dig(:dynamics, :swing_hint)
      result[:texture_hints] = analysis[:texture_hints]
      result[:drum_density] = analysis[:drum_density]
    end
    if stem_name == "drums.wav"
      grid = drum_step_grid_from_wav(path, bpm: result[:bpm_estimate])
      result.merge!(grid) if grid.is_a?(Hash)
    end
  when "piano.wav", "guitar.wav", "other.wav", "vocals.wav"
    profile = pitch_profile(path)
    pcs_hash = profile.fetch(:pitch_classes)
    top_pcs = top_pitch_class_indices(pcs_hash)
    ranking = chord_candidates(pcs_hash).first(8)
    result[:pitch_classes] = top_pcs
    result[:top_chords] = ranking.map { |c| { name: c[:chord], score: c[:score] } }
    if defined?(DillaMusicGems) && DillaMusicGems.coltrane?
      result[:coltrane_candidates] = DillaMusicGems.chord_candidates_from_pitch_classes(top_pcs, limit: 8)
    end
  end
  if %w[other.wav vocals.wav].include?(stem_name)
    rhythm_data = frame_energy(path, highpass: 60, lowpass: 12_000)
    loudness = rhythm_data.fetch(:frames).map(&:last)
    brightness = frame_energy(path, highpass: 2_400, lowpass: 12_000).fetch(:frames).map(&:last)
    density = peak_frames(rhythm_data.fetch(:frames), rhythm_data.fetch(:hop_seconds)).length.to_f /
              [rhythm_data.fetch(:duration_seconds), 1.0].max
    result[:semantics] = semantic_tags(loudness, brightness, density)
  end
  result
rescue StandardError => e
  { path: path, stem: stem_name, error: e.message }
end

RAP_VOCAL_DIR = File.join(DillaSourceLearn::LEARNINGS_DIR, "vocals").freeze
RAP_VOCAL_CATALOG = File.join(RAP_VOCAL_DIR, "catalog.json").freeze

def rap_vocal_slug(artist)
  artist.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
end

def rap_vocal_load_catalog
  return { "vocals" => [], "updated_at" => nil } unless File.file?(RAP_VOCAL_CATALOG)
  JSON.parse(File.read(RAP_VOCAL_CATALOG))
rescue StandardError
  { "vocals" => [], "updated_at" => nil }
end

def rap_vocal_save_catalog!(cat)
  DillaSourceLearn.ensure_dir!
  FileUtils.mkdir_p(RAP_VOCAL_DIR)
  cat["updated_at"] = Time.now.utc.iso8601
  File.write(RAP_VOCAL_CATALOG, JSON.pretty_generate(cat) + "\n")
end

def rap_vocal_phrase_onsets(path)
  rhythm = frame_energy(path, highpass: 300, lowpass: 6000)
  peaks = peak_frames(rhythm[:frames], rhythm[:hop_seconds])
  return [] if peaks.empty?
  phrases = []
  cluster = [peaks.first]
  peaks[1..].each do |pk|
    if pk[:time] - cluster.last[:time] < 0.35
      cluster << pk
    else
      phrases << { "start" => cluster.first[:time].round(3), "end" => cluster.last[:time].round(3),
                   "strength" => cluster.map { |p| p[:strength] }.max.round(4) }
      cluster = [pk]
    end
  end
  phrases << { "start" => cluster.first[:time].round(3), "end" => cluster.last[:time].round(3),
               "strength" => cluster.map { |p| p[:strength] }.max.round(4) }
  phrases
end

def rap_vocal_atempo_chain(ratio)
  r = ratio.to_f.clamp(0.25, 4.0)
  parts = []
  while r > 2.0
    parts << 2.0
    r /= 2.0
  end
  while r < 0.5
    parts << 0.5
    r /= 0.5
  end
  parts << r
  parts.map { |t| "atempo=#{t.round(4)}" }.join(",")
end

# Voice-only chain for demucs "vocals" stems.
# Goal: hear Jonas V (speech/rap), never residual kick/bass/hats from the source beat.
# Demucs always leaves some kit bleed; we kill it hard then denoise the floor.
def rap_vocal_isolation_filter
  [
    "aformat=sample_rates=#{SAMPLE_RATE}:channel_layouts=stereo",
    # Center-bias: voice is mid; kit/pads often wider — collapse residual sides.
    "pan=stereo|c0=0.72*c0+0.28*c1|c1=0.72*c1+0.28*c0",
    # Kill everything below speech fundamentals (kit sub lives here).
    "highpass=f=175:width_type=q:width=0.707",
    "equalizer=f=55:t=h:w=1.0:g=-24",
    "equalizer=f=90:t=h:w=1.2:g=-18",
    "equalizer=f=130:t=o:w=1.4:g=-12",
    "equalizer=f=200:t=o:w=1.3:g=-6",
    # Soft top air for consonants; no crash/hat glare.
    "lowpass=f=7200:width_type=q:width=0.8",
    "equalizer=f=3200:t=o:w=1.5:g=2.2",
    "equalizer=f=5500:t=h:w=1.2:g=-2.5",
    # FFT denoise residual kit hiss / cymbal wash left in demucs vocals.
    "afftdn=nr=14:nf=-28:tn=1",
    # Hard gate: only pass when voice is present (no quiet snare ghosts).
    "agate=threshold=0.028:ratio=8:attack=2:release=55:range=0.0008:makeup=1.5",
    "acompressor=threshold=-24dB:ratio=2.4:attack=4:release=90:makeup=3.5",
    # Second gate after makeup so boosted floor does not reappear.
    "agate=threshold=0.016:ratio=5:attack=1:release=40:range=0.0005:makeup=1"
  ].join(",")
end

# Light polish for already-isolated stems (no heavy makeup that re-lifts bleed).
def rap_vocal_voice_polish_filter
  [
    "aformat=sample_rates=#{SAMPLE_RATE}:channel_layouts=stereo",
    "highpass=f=165:width_type=q:width=0.707",
    "equalizer=f=80:t=h:w=1.0:g=-14",
    "lowpass=f=7400",
    "afftdn=nr=8:nf=-32:tn=1",
    "agate=threshold=0.02:ratio=5:attack=2:release=50:range=0.0006:makeup=1.2",
    "acompressor=threshold=-24dB:ratio=2:attack=5:release=100:makeup=2"
  ].join(",")
end

# First substantial phrase — skip instrumental intro left in the "vocals" stem.
def rap_vocal_phrase_start(phrases, min_strength: 0.22)
  Array(phrases).filter_map do |p|
    s = (p["start"] || p[:start]).to_f
    st = (p["strength"] || p[:strength]).to_f
    next if s < 1.0
    next if st.positive? && st < min_strength
    s
  end.min
end

def rap_vocal_clean_stem!(src, dest = nil, aggressive: true)
  dest ||= src.sub(/\.wav\z/i, ".clean.wav")
  dest = "#{src}.clean.wav" if dest == src
  chain = aggressive ? rap_vocal_isolation_filter : rap_vocal_voice_polish_filter
  sh! "ffmpeg", "-y", "-i", src,
      "-af", "#{chain},loudnorm=I=-17:TP=-2.5:LRA=7,alimiter=limit=0.93:level_out=0.94",
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", dest
  dest
end

def rap_vocal_best_bar_offset(vocal_path, beat_bpm, phrases: nil)
  phrase_times = Array(phrases).filter_map { |p| p["start"] || p[:start] }
  if phrase_times.empty?
    rhythm = frame_energy(vocal_path, highpass: 300, lowpass: 6000)
    phrase_times = peak_frames(rhythm[:frames], rhythm[:hop_seconds]).map { |p| p[:time] }
  end
  return 0.0 if phrase_times.empty?
  bar_sec = (60.0 / beat_bpm.to_f) * 4.0
  best = 0.0
  best_score = -1
  (0..(bar_sec * 40)).each do |i|
    offset = i * 0.025
    score = phrase_times.count do |t|
      rel = (t - offset) % bar_sec
      rel < 0.06 || (bar_sec - rel) < 0.06 || (rel - bar_sec / 2.0).abs < 0.06
    end
    next unless score > best_score
    best_score = score
    best = offset
  end
  best.round(3)
end

def rap_vocal_resolve(slug_or_path)
  raw = slug_or_path.to_s
  return raw if raw.end_with?(".wav", ".mp3", ".m4a") && File.file?(raw)
  cat = rap_vocal_load_catalog
  vocals = Array(cat["vocals"])
  return nil if vocals.empty?
  if raw.empty? || raw == "auto"
    idx = (@stream_iterate_count || 0) % vocals.length
    return vocals[idx]
  end
  vocals.find { |v| v["slug"] == raw || v["artist"].to_s.casecmp(raw).zero? } ||
    vocals.find { |v| v["slug"].to_s.include?(raw) }
end

# Never auto-fallback to random catalog entries (that pulled in sirkel_sag).
RAP_VOCAL_BLOCKLIST = %w[sirkel_sag].freeze

def rap_vocal_stream_slug
  slug = ENV["RAP_VOCAL"].to_s.strip
  return nil if slug.empty? || slug == "0"
  return nil if RAP_VOCAL_BLOCKLIST.include?(slug)
  if slug == "auto"
    cat = rap_vocal_load_catalog
    pick = Array(cat["vocals"]).find do |v|
      s = v["slug"].to_s
      next false if RAP_VOCAL_BLOCKLIST.include?(s)
      next false unless File.file?(v["vocal_path"].to_s)
      peak = band_rms(v["vocal_path"], highpass: 80, lowpass: 8_000) rescue -90.0
      peak >= -45.0
    end
    return pick&.dig("slug")
  end
  cat = rap_vocal_load_catalog
  entry = Array(cat["vocals"]).find { |v| v["slug"] == slug }
  unless entry && entry["vocal_path"] && File.file?(entry["vocal_path"])
    warn "rap-vocal: #{slug} missing from catalog — skipping vocals"
    return nil
  end
  peak = band_rms(entry["vocal_path"], highpass: 80, lowpass: 8_000) rescue -90.0
  if peak < -55.0
    warn "rap-vocal: #{slug} too quiet (≈#{peak.round(1)} dB) — skipping (no fallback)"
    return nil
  end
  slug
end

def rap_vocal_ingest!(artist, src)
  ensure_demucs_ready!
  DillaSourceLearn.ensure_dir!
  slug = rap_vocal_slug(artist)
  out_dir = File.join(RAP_VOCAL_DIR, slug)
  FileUtils.mkdir_p(out_dir)
  stem_dir = demux_six(src)
  vocal_src = File.join(stem_dir, "vocals.wav")
  unless File.file?(vocal_src)
    warn "rap-vocal ingest: demucs produced no vocals.wav in #{stem_dir}"
    return nil
  end
  vocal_dest = File.join(out_dir, "vocals.wav")
  # Demucs "vocals" still carries kit/bass bleed — voice-only isolate before catalog.
  # Never catalog drums/bass/other stems — only this cleaned vocals.wav path is mixed.
  rap_vocal_clean_stem!(vocal_src, vocal_dest, aggressive: true)
  analysis = RadioBergenStudy::DeepAudio.analyze(vocal_dest)
  phrases = rap_vocal_phrase_onsets(vocal_dest)
  entry = {
    "slug" => slug, "artist" => artist.to_s, "source" => src.to_s,
    "vocal_path" => vocal_dest, "stem_dir" => stem_dir,
    "bpm_estimate" => analysis[:bpm_estimate],
    "phrases" => phrases, "ingested_at" => Time.now.utc.iso8601,
    "isolated" => true, "voice_only" => true
  }
  cat = rap_vocal_load_catalog
  cat["vocals"] = Array(cat["vocals"]).reject { |v| v["slug"] == slug } + [entry]
  rap_vocal_save_catalog!(cat)
  File.write(File.join(out_dir, "meta.json"), JSON.pretty_generate(entry) + "\n")
  puts "rap-vocal ingest: #{artist} → #{vocal_dest} bpm=#{analysis[:bpm_estimate]} phrases=#{phrases.length}"
  entry
end

# Fold raw onset BPM into the stream pocket (≈76–100). Avoids the 66.7 trap
# where *2 → 133 and /2 → 66.7 forever (never lands in-range).
def rap_vocal_fold_bpm(raw)
  b = raw.to_f
  return nil unless b.positive?
  pool = [b, b * 2, b / 2.0, b * 1.5, b / 1.5, b * 4 / 3.0, b * 3 / 4.0]
  in_range = pool.select { |x| x.between?(74.0, 100.0) }
  pick = if in_range.any?
           in_range.min_by { |x| (x - 90.0).abs }
         else
           # Closest to 90 even if outside
           pool.min_by { |x| (x - 90.0).abs }
         end
  pick.round(2)
end

# Prefer ENV override, then catalog, then fresh analysis; fold into hip-hop range.
def rap_vocal_source_bpm(entry, vocal_path)
  forced = ENV["RAP_VOCAL_BPM"].to_f
  return forced if forced.positive?
  candidates = []
  if entry.is_a?(Hash)
    candidates << entry["bpm_estimate"].to_f
    candidates << entry.dig("last_fit", "source_bpm").to_f
  end
  if candidates.none?(&:positive?)
    analysis = RadioBergenStudy::DeepAudio.analyze(vocal_path) rescue nil
    candidates << analysis&.dig(:bpm_estimate).to_f
    candidates << analysis&.dig(:bpm_estimate_kick).to_f
    candidates << analysis&.dig(:bpm_estimate_snare).to_f
  end
  raw = candidates.find { |b| b && b.positive? }
  rap_vocal_fold_bpm(raw)
end

def rap_vocal_fit!(slug_or_path, beat_bpm:, n_bars:, bar_offset: nil)
  entry = rap_vocal_resolve(slug_or_path)
  vocal_path = entry.is_a?(Hash) ? entry["vocal_path"] : entry
  unless vocal_path && File.file?(vocal_path)
    warn "rap-vocal fit: unknown or missing slug #{slug_or_path}"
    return nil
  end
  # Always re-isolate uncleaned stems; already-isolated stems get a light polish only.
  isolated = entry.is_a?(Hash) && entry["isolated"] == true
  if entry.is_a?(Hash) && !isolated
    cleaned = File.join(File.dirname(vocal_path), "vocals.clean.wav")
    rap_vocal_clean_stem!(vocal_path, cleaned, aggressive: true)
    FileUtils.mv(cleaned, vocal_path)
    entry["isolated"] = true
    entry["voice_only"] = true
    entry["phrases"] = rap_vocal_phrase_onsets(vocal_path)
    cat = rap_vocal_load_catalog
    cat["vocals"] = Array(cat["vocals"]).map { |v| v["slug"] == entry["slug"] ? entry : v }
    rap_vocal_save_catalog!(cat)
    isolated = true
  end
  beat_bpm = beat_bpm.to_f
  vocal_bpm = rap_vocal_source_bpm(entry, vocal_path)
  vocal_bpm = beat_bpm unless vocal_bpm&.positive?
  # Clamp stretch: extreme atempo starts to chipmunk/garble speech.
  ratio = (beat_bpm / vocal_bpm).clamp(0.5, 2.0)
  duration = (60.0 / beat_bpm) * 4.0 * n_bars
  phrases = entry.is_a?(Hash) ? entry["phrases"] : nil
  phrase_start = rap_vocal_phrase_start(phrases) || 0.0
  offset = bar_offset || rap_vocal_best_bar_offset(vocal_path, beat_bpm, phrases: phrases)
  # Prefer real speech onset over residual intro thump.
  ss = [offset, phrase_start].max
  out_dir = File.dirname(vocal_path)
  fit_path = File.join(out_dir, "fit_#{beat_bpm.round}_#{n_bars}bars.wav")
  # Already-isolated → light polish only (no second heavy makeup that re-lifts bleed).
  # Fresh/unclean → full voice-only isolation.
  voice_chain = isolated ? rap_vocal_voice_polish_filter : rap_vocal_isolation_filter
  # Loop source so short verses cover full N bars (voice-only — never pad with kit).
  # Soft edge fades avoid wrap clicks after atempo.
  fade = [0.012, duration * 0.004].max.round(4)
  sh! "ffmpeg", "-y", "-stream_loop", "-1", "-ss", ss.round(3).to_s, "-i", vocal_path,
      "-t", duration.round(3).to_s,
      "-af", "#{voice_chain},#{rap_vocal_atempo_chain(ratio)}," \
             "asetpts=PTS-STARTPTS," \
             "afade=t=in:st=0:d=#{fade},afade=t=out:st=#{(duration - fade).round(3)}:d=#{fade}," \
             "loudnorm=I=-17:TP=-2.5:LRA=7,alimiter=limit=0.93:level_out=0.94",
      "-ar", SAMPLE_RATE.to_s, "-ac", "2", "-c:a", "pcm_s16le", fit_path
  peak = band_rms(fit_path, highpass: 200, lowpass: 6_000) rescue -90.0
  sub_bleed = band_rms(fit_path, highpass: 30, lowpass: 120) rescue -90.0
  if peak < -50.0
    warn "rap-vocal fit: stem too quiet (rms≈#{peak.round(1)} dB) — #{fit_path}"
  end
  if sub_bleed > -38.0
    warn "rap-vocal fit: sub bleed still high (#{sub_bleed.round(1)} dB <120Hz) — re-clean recommended"
  end
  if entry.is_a?(Hash)
    entry["last_fit"] = { "path" => fit_path, "beat_bpm" => beat_bpm, "n_bars" => n_bars,
                          "offset_sec" => ss, "phrase_start" => phrase_start,
                          "source_bpm" => vocal_bpm, "tempo_ratio" => ratio.round(4),
                          "rms_db" => peak, "sub_bleed_db" => sub_bleed,
                          "voice_only" => true }
    entry["bpm_estimate"] = vocal_bpm if vocal_bpm.positive?
    entry["voice_only"] = true
    cat = rap_vocal_load_catalog
    cat["vocals"] = Array(cat["vocals"]).map { |v| v["slug"] == entry["slug"] ? entry : v }
    rap_vocal_save_catalog!(cat)
  end
  puts "rap-vocal fit: #{fit_path} src=#{vocal_bpm}bpm → #{beat_bpm}bpm " \
       "ratio=#{ratio.round(3)} start=#{ss}s bars=#{n_bars} " \
       "voice≈#{peak.round(1)}dB sub≈#{sub_bleed.round(1)}dB"
  fit_path
end

def rap_vocal_mix_params
  style = ENV.fetch("RAP_VOCAL_STYLE", "rap")
  # Voice-forward: pads/kit stay under speech so Jonas V is obvious on speakers.
  vocal_vol = ENV.fetch("RAP_VOCAL_MIX", style == "chop" ? "1.45" : "1.55").to_f
  duck = ENV.fetch("RAP_VOCAL_DUCK", "0.72").to_f
  top_eq = style == "chop" ? "equalizer=f=2800:t=o:w=2:g=3.5" : "equalizer=f=2900:t=o:w=1.6:g=4.5"
  presence = style == "chop" ? "equalizer=f=3600:t=o:w=1.4:g=2.5," : "equalizer=f=3200:t=o:w=1.2:g=3.5,"
  { vocal_vol: vocal_vol, duck: duck, top_eq: top_eq, presence: presence }
end

def mix_rap_vocal_layer!(beat_path, vocal_path, dest)
  mix = rap_vocal_mix_params
  bed_w = ENV.fetch("RAP_VOCAL_BED_WEIGHT", "0.92").to_f
  voc_w = ENV.fetch("RAP_VOCAL_WEIGHT", "1.35").to_f
  # Voice-only path: HPF kills residual kit; light gate (not so hard it mutes speech);
  # sidechain ducks bed under voice so rap sits on top of pads/drums.
  sc = ENV.fetch("RAP_VOCAL_SIDECHAIN", "1") != "0"
  # Keep filter graph as one line — empty segments from heredoc joins break ffmpeg.
  v_chain = [
    "[1:a]aformat=channel_layouts=stereo",
    "highpass=f=175:width_type=q:width=0.707",
    "equalizer=f=70:t=h:w=1:g=-18",
    "equalizer=f=120:t=h:w=1.2:g=-10",
    "lowpass=f=7200",
    "#{mix[:presence]}#{mix[:top_eq]}".sub(/,\z/, ""),
    "agate=threshold=0.012:ratio=3:attack=3:release=80:range=0.002:makeup=1.5",
    "acompressor=threshold=-22dB:ratio=2:attack=5:release=100:makeup=3",
    "volume=#{mix[:vocal_vol]}[v0]"
  ].join(",")
  if sc
    filter = [
      v_chain,
      "[0:a]volume=#{mix[:duck]}[bed0]",
      # Duck bed when voice present (main=bed0, sidechain=v0).
      "[bed0][v0]sidechaincompress=threshold=0.04:ratio=2.8:attack=6:release=140:makeup=1:mix=0.7[bed]",
      "[bed][v0]amix=inputs=2:weights=#{bed_w} #{voc_w}:duration=first:dropout_transition=0:normalize=0," \
      "alimiter=limit=0.96:level_out=0.97[out]"
    ].join(";")
  else
    filter = [
      v_chain,
      "[0:a]volume=#{mix[:duck]}[bed]",
      "[bed][v0]amix=inputs=2:weights=#{bed_w} #{voc_w}:duration=first:dropout_transition=0:normalize=0," \
      "alimiter=limit=0.96:level_out=0.97[out]"
    ].join(";")
  end
  sh! "ffmpeg", "-y", "-i", beat_path, "-i", vocal_path,
      "-filter_complex", filter,
      "-map", "[out]", *codec_for(dest), dest
end

def learn_source!(src, apply: false, deep: false, start_sec: nil, meta: nil)
  DillaMusicGems.bootstrap! if defined?(DillaMusicGems)
  audio_path = if File.exist?(src.to_s)
                 File.expand_path(src)
               else
                 demux_fetch_audio(src, start_sec: start_sec)
               end
  stem_dir = demux_six(audio_path)
  demux_deep_bands!(stem_dir) if deep
  stem_analysis = {}
  Dir[File.join(stem_dir, "*.wav")].sort.each do |wav|
    name = File.basename(wav)
    stem_analysis[name] = analyze_stem_for_learn(wav, name)
  end
  full_analysis = RadioBergenStudy::DeepAudio.analyze(audio_path)
  report = DillaSourceLearn.compose_report(
    source: src,
    stem_dir: stem_dir,
    stem_analysis: stem_analysis,
    full_analysis: full_analysis
  )
  report = report.merge(meta) if meta.is_a?(Hash)
  if meta.is_a?(Hash) && meta[:id]
    learn_register_texture_stems!(stem_dir, meta[:id], bpm: report[:bpm_estimate])
  end
  paths = DillaSourceLearn.save_report!(report)
  puts JSON.pretty_generate(report.merge(saved: paths))
  if apply
    applied = DillaSourceLearn.apply_hints_to_env!(report[:engine_hints])
    ENV["STREAM_LEARN_BIAS"] = "1"
    puts "applied: #{applied.join(', ')}"
  end
  report
end

def learn_playlist_row!(row, deep: true, force: false)
  key = playlist_row_key(row)
  return nil if key.empty?

  slug = RadioBergenStudy.slug(row[:artist], row[:title])
  state = DillaSourceLearn.load_batch_state
  return :skipped if !force && Array(state["completed_ids"]).include?(key)

  aff = RadioBergenStudy.affinity_for(row[:artist])
  dossier = RadioBergenStudy.dossier_for(slug)
  meta = { id: slug, artist: row[:artist], title: row[:title], source: "playlist.brgen.no",
           affinity: aff, dossier: dossier }

  if row[:source] == "local_mp3"
    path = RadioBergenStudy.resolve_local_path(row)
    unless path && File.file?(path)
      warn "learn-playlist: local missing — #{row[:artist]} — #{row[:title]} (#{row[:src]})"
      return nil
    end
    puts "learn-playlist: [local] #{row[:artist]} — #{row[:title]}"
    report = learn_source!(path, deep: deep, meta: meta.merge(local_src: row[:src], audio_path: path))
  else
    id = row[:youtube_id].to_s
    return nil if id.empty?
    url = youtube_watch_url(id, start: row[:start])
    puts "learn-playlist: [youtube] #{row[:artist]} — #{row[:title]} (#{id})"
    report = learn_source!(url, deep: deep, start_sec: row[:start],
                           meta: meta.merge(youtube_id: id, url: url))
  end

  entry = report.merge(id: slug, artist: row[:artist], title: row[:title],
                       youtube_id: row[:youtube_id], learned_at: Time.now.utc.iso8601)
  DillaSourceLearn.save_playlist_entry!(entry)
  learn_register_texture_stems!(report[:stem_dir], slug, bpm: report[:bpm_estimate])
  state["completed_ids"] = (Array(state["completed_ids"]) + [key]).uniq
  state["failed"] ||= {}
  state["failed"].delete(key)
  state["last_completed"] = { key: key, slug: slug, at: Time.now.utc.iso8601 }
  DillaSourceLearn.save_batch_state!(state)
  entry
rescue StandardError => e
  state = DillaSourceLearn.load_batch_state
  state["failed"] ||= {}
  state["failed"][key] = { error: e.message, at: Time.now.utc.iso8601 }
  DillaSourceLearn.save_batch_state!(state)
  warn "learn-playlist: #{row[:artist]} — #{row[:title]} failed: #{e.message}"
  nil
end

def learn_register_texture_stems!(stem_dir, slug, bpm: nil)
  return unless stem_dir && File.directory?(stem_dir)
  stems_register("learn_#{slug}", stem_dir, bpm: bpm, source: "playlist.brgen.no/#{slug}")
rescue StandardError => e
  warn "stem register: #{e.message}"
end

def learn_playlist_batch!(youtube_only: true, deep: true, resume: true, limit: nil, force: false,
                          promote: true, calibrate: true)
  DillaSourceLearn.ensure_dir!
  rows = RadioBergenStudy.catalog_rows
  if youtube_only
    rows = rows.select { |r| r[:source] == "youtube_reference" && r[:youtube_id] && !r[:youtube_id].empty? }
  else
    rows = rows.select do |r|
      r[:source] == "youtube_reference" && r[:youtube_id] && !r[:youtube_id].empty? ||
        (r[:source] == "local_mp3" && RadioBergenStudy.resolve_local_path(r))
    end
  end
  if resume && !force
    state = DillaSourceLearn.load_batch_state
    done = Array(state["completed_ids"])
    rows = rows.reject { |r| done.include?(playlist_row_key(r)) }
  end
  rows = rows.first(limit.to_i) if limit

  puts "learn-playlist: #{rows.length} track(s) — demucs=#{demucs_available? ? 'yes' : 'NO'} deep=#{deep}"
  results = rows.map { |row| learn_playlist_row!(row, deep: deep, force: force) }
  ok = results.count { |r| r.is_a?(Hash) }
  skipped = results.count { |r| r == :skipped }
  learn_promote! if promote && ok.positive?
  learn_calibrate! if calibrate
  learn_diff_dossiers!
  puts "learn-playlist: done #{ok} ok, #{skipped} skipped, #{rows.length - ok - skipped} failed"
  puts "catalog -> #{DillaSourceLearn::PLAYLIST_CATALOG_PATH}"
  { ok: ok, skipped: skipped, failed: rows.length - ok - skipped, catalog: DillaSourceLearn::PLAYLIST_CATALOG_PATH }
end

def learn_playlist_agent!(foreground: false)
  DillaSourceLearn.ensure_dir!
  log_path = DillaSourceLearn::PLAYLIST_BATCH_LOG
  unless foreground || ENV["DILLA_AGENT_LAUNCHED"] == "1"
    cmd = "cd #{Shellwords.escape(ROOT)} && DILLA_AGENT_LAUNCHED=1 DILLA_RAW=1 #{Shellwords.escape(Gem.ruby)} " \
          "#{Shellwords.escape(__FILE__)} learn-playlist-agent foreground"
    pid = Process.spawn(cmd, out: log_path, err: log_path)
    Process.detach(pid)
    puts "learn-playlist-agent: background pid=#{pid} log=#{log_path}"
    return pid
  end
  ensure_demucs_ready!
  loop do
    rows = RadioBergenStudy.catalog_rows.select do |r|
      r[:source] == "youtube_reference" && r[:youtube_id] && !r[:youtube_id].empty? ||
        (r[:source] == "local_mp3" && RadioBergenStudy.resolve_local_path(r))
    end
    done = Array(DillaSourceLearn.load_batch_state["completed_ids"])
    pending = rows.reject { |r| done.include?(playlist_row_key(r)) }
    break if pending.empty?
    learn_playlist_batch!(youtube_only: false, deep: true, resume: true, promote: true, calibrate: true)
    sleep 120
  end
end

def ensure_demucs_ready!
  return if demucs_available?
  venv = File.join(ROOT, ".venv-demucs")
  unless File.directory?(venv)
    sh! "python3", "-m", "venv", venv
  end
  pip = File.join(venv, "bin", "pip")
  demucs_py = File.join(venv, "bin", "python")
  unless system(demucs_py, "-m", "demucs", "--help", out: File::NULL, err: File::NULL)
    sh! pip, "install", "-q", "numpy", "demucs"
  end
  ENV["PATH"] = "#{File.join(venv, 'bin')}:#{ENV['PATH']}"
  abort "demucs install failed — run: #{pip} install numpy demucs" unless demucs_available?
end

# =============================================================================
# LIVESET (long-form stem rack WAV)
# =============================================================================

def liveset_filter(count, periods: LIVESET_PERIODS)
  per_input = (0...count).map do |i|
    p = periods[i % periods.size]; phase = (i * 1.7).round(3); base = (0.55 + (i % 3) * 0.05).round(2)
    "[#{i}:a]aformat=sample_rates=44100:channel_layouts=stereo," \
      "volume='#{base}*(0.55+0.45*sin(2*PI*(t+#{phase})/#{p}))':eval=frame[s#{i}]"
  end
  taps = (0...count).map { |i| "[s#{i}]" }.join
  master = <<~F.tr("\n", " ").strip
    [mix]acompressor=threshold=-20dB:ratio=4:attack=30:release=300:makeup=2,
    highpass=f=30:width_type=q:width=1.2,equalizer=f=55:t=o:w=0.8:g=2,
    acrusher=bits=12:samples=1.69:level_in=1:level_out=1:mix=0.35,
    equalizer=f=2200:t=o:w=0.6:g=-2,
    aphaser=in_gain=0.4:out_gain=0.7:delay=2:decay=0.3:speed=0.12:type=sinusoidal,
    aeval='(tanh((val(0)+0.05)*1.6)-0.0798)/0.853|(tanh((val(1)+0.05)*1.6)-0.0798)/0.853',
    alimiter=level_in=1.0:level_out=0.95:limit=0.95:attack=5:release=80[out]
  F
  "#{per_input.join(';')};#{taps}amix=inputs=#{count}:weights=#{'1 ' * count}:duration=longest[mix];#{master}"
end

def render_liveset(name = "default", minutes: LIVESET_MIN)
  require_tools! "ffmpeg"
  m = stems_load_manifest
  set = m["sets"][name] || m["sets"][m["active"]] or abort "liveset: no stem set '#{name}'"
  base_dir = File.join(STEM_DIR, set["dir"] || ".")
  files = set["files"]
  abort "liveset: empty set" if files.nil? || files.empty?
  inputs = files.flat_map { |f| ["-stream_loop", "-1", "-i", File.join(base_dir, f)] }
  out = File.join(OUTPUT_DIR, "liveset_#{name}_#{minutes}m.wav")
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", liveset_filter(files.size),
      "-map", "[out]", "-t", (minutes * 60).to_s, "-ar", "44100", "-c:a", "pcm_s16le", out
  puts "liveset -> #{out}"
end

# =============================================================================
# ELECTRONIUM — Raymond Scott × J Dilla (midilib MIDI + full-engine bridge)
# All logic lives here; no sidecar electronium.rb. Lazy-loads midilib at runtime.
# =============================================================================

module DillaElectronium
  PPQN = 480
  F_MINOR_SCALE = [65, 67, 68, 70, 72, 73, 75].freeze # F4–Eb5

  # Lush 9th voicings (merged engine pads + MIDI export).
  CHORDS = {
    fm9: [53, 56, 60, 63, 67], dbmaj9: [49, 53, 56, 60, 63], eb9: [51, 55, 58, 63, 65],
    bbm9: [46, 49, 53, 56, 60], cm7b5: [48, 51, 54, 58], c7alt: [48, 52, 58, 61, 63]
  }.freeze
  PROGRESSION = %i[fm9 dbmaj9 eb9 bbm9 cm7b5 fm9 c7alt fm9].freeze

  # Classic 7th cycle from the Electronium essay / "The Light" family.
  CHORDS_CLASSIC = {
    fm7: [65, 68, 72, 75], dbmaj7: [61, 65, 68, 72], eb7: [63, 67, 70, 75],
    bbm7: [58, 61, 65, 68], cm7b5: [60, 63, 66, 70], c7: [60, 64, 67, 70]
  }.freeze
  PROGRESSION_CLASSIC = %i[fm7 dbmaj7 eb7 bbm7 cm7b5 fm7 c7 fm7].freeze

  CHORD_SYMBOLS = {
    fm9: "Fm9", dbmaj9: "Dbmaj9", eb9: "Eb9", bbm9: "Bbm9", cm7b5: "Cm7b5", c7alt: "C7alt",
    fm7: "Fm7", dbmaj7: "Dbmaj7", eb7: "Eb7", bbm7: "Bbm7", c7: "C7"
  }.freeze

  DRUMS = { kick: 36, snare: 38, closed_hat: 42, open_hat: 46 }.freeze

  module_function

  def classic?
    ENV["ELECTRONIUM_CLASSIC"] == "1"
  end

  def chord_bank
    classic? ? CHORDS_CLASSIC : CHORDS
  end

  def progression
    classic? ? PROGRESSION_CLASSIC : PROGRESSION
  end

  def pads_for_engine(classic: classic?)
    bank = classic ? CHORDS_CLASSIC : CHORDS
    prog = classic ? PROGRESSION_CLASSIC : PROGRESSION
    prog.map do |sym|
      DillaLofiMachine.chord_from_symbol(CHORD_SYMBOLS.fetch(sym))
    rescue StandardError
      hz = bank.fetch(sym).map { |m| midi_to_hz(m.to_f) }
      { name: CHORD_SYMBOLS.fetch(sym), hz: hz }
    end
  end

  def track_profile
    classic? ? :electronium_classic : :electronium_loop
  end

  # Poly-temporal offsets — kick early, snare late, hats lopsided (Dilla Time).
  module Groove
    module_function

    def rng
      @rng ||= Random.new((ENV["SEED"] || ENV["GEN_SEED"] || Process.pid).to_i)
    end

    def offset_ticks(type)
      case type
      when :kick then rng.rand(-3..0)      # rush the downbeat slightly
      when :snare then rng.rand(0..5)      # lazy backbeat
      when :hat then rng.rand(-2..2)
      when :bass, :melody then rng.rand(-4..4)
      else 0
      end
    end

    def beat_to_ticks(beat, type = :melody)
      ((beat * DillaElectronium::PPQN) + offset_ticks(type)).round.clamp(0, 1 << 30)
    end
  end

  class TrackBuilder
    def initialize(sequence, name, channel)
      @sequence = sequence
      @track = MIDI::Track.new(sequence)
      @track.name = name
      @sequence.tracks << @track
      @channel = channel
    end

    def note(note, start_beat, duration_beats, velocity, feel: :melody)
      return if duration_beats <= 0
      start = Groove.beat_to_ticks(start_beat, feel)
      stop = [start + (duration_beats * PPQN).round, start + 1].max
      on = MIDI::NoteOn.new(@channel, note, velocity.clamp(1, 127))
      on.time_from_start = start
      off = MIDI::NoteOff.new(@channel, note, 0)
      off.time_from_start = stop
      @track.events << on
      @track.events << off
    end

    def finish
      @track.events.sort_by! { |e| [e.time_from_start, e.is_a?(MIDI::NoteOff) ? 0 : 1] }
      @track.recalc_times
    end
  end

  class Composer
    def initialize(bpm:, bars:, classic: false, septuplet_hats: false)
      @bpm = bpm
      @bars = bars
      @classic = classic
      @septuplet_hats = septuplet_hats
      @sequence = MIDI::Sequence.new
      @sequence.ppqn = PPQN
      add_tempo_track
    end

    def write(path)
      add_drums
      add_bass
      add_chords
      add_melody
      File.open(path, "wb") { |f| @sequence.write(f) }
      path
    end

    private

    def chord_bank
      @classic ? CHORDS_CLASSIC : CHORDS
    end

    def progression
      @classic ? PROGRESSION_CLASSIC : PROGRESSION
    end

    def add_tempo_track
      track = MIDI::Track.new(@sequence)
      @sequence.tracks << track
      track.events << MIDI::Tempo.new(MIDI::Tempo.bpm_to_mpq(@bpm))
      title = @classic ? "Dilla Electronium (classic 7ths)" : "Dilla Electronium"
      track.events << MIDI::MetaEvent.new(MIDI::META_SEQ_NAME, title)
      track.events << MIDI::MetaEvent.new(MIDI::META_TIME_SIG, [4, 2, 24, 8].pack("cccc"))
    end

    def add_drums
      drums = TrackBuilder.new(@sequence, "drums", 9)
      if @classic
        add_drums_classic(drums)
      else
        add_drums_dilla(drums)
      end
      drums.finish
    end

    def add_drums_dilla(drums)
      @bars.times do |bar|
        base = bar * 4.0
        [0.0, 1.75, 2.5, 3.5].each { |beat| drums.note(DRUMS[:kick], base + beat, 0.18, 105, feel: :kick) }
        [1.0, 3.0].each { |beat| drums.note(DRUMS[:snare], base + beat, 0.12, 92, feel: :snare) }
        drums.note(DRUMS[:snare], base + 2.75, 0.08, 42, feel: :snare) if bar.odd?
        if @septuplet_hats
          (0...4).each do |beat|
            [0.0, 3.0 / 7.0].each do |sub|
              drums.note(DRUMS[:closed_hat], base + beat + sub, 0.08, Groove.rng.rand(50..70), feel: :hat)
            end
          end
        else
          8.times do |step|
            drums.note(DRUMS[:closed_hat], base + step * 0.5 + (step.odd? ? 0.055 : 0.0), 0.08,
                        step.odd? ? 48 : 68, feel: :hat)
          end
        end
        drums.note(DRUMS[:open_hat], base + 3.5, 0.18, 58, feel: :hat) if (bar % 4).zero?
      end
    end

    def add_drums_classic(drums)
      groups = (@bars / 2.0).ceil
      groups.times do |g|
        base = g * 8.0
        [0.0, 2.0, 4.0, 6.0].each { |beat| drums.note(DRUMS[:kick], base + beat, 0.12, 100, feel: :kick) }
        [1.0, 3.0, 5.0, 7.0].each { |beat| drums.note(DRUMS[:snare], base + beat, 0.12, 90, feel: :snare) }
        (0...8).each do |beat|
          [0.0, 3.0 / 7.0].each do |sub|
            drums.note(DRUMS[:closed_hat], base + beat + sub, 0.08, Groove.rng.rand(50..70), feel: :hat)
          end
        end
      end
    end

    def add_bass
      bass = TrackBuilder.new(@sequence, "bass", 0)
      chord_cycle.each_with_index do |chord_name, index|
        root = chord_bank.fetch(chord_name).first - (@classic ? 24 : 12)
        start = index * 2.0
        [0.0, 0.75, 1.5].each_with_index do |off, i|
          vel = [98, 72, 86][i]
          dur = [0.62, 0.25, 0.38][i]
          note = i == 1 ? root + 12 : root
          bass.note(note, start + off, dur, vel, feel: :bass)
        end
      end
      bass.finish
    end

    def add_chords
      pads = TrackBuilder.new(@sequence, "electric-piano", 1)
      chord_cycle.each_with_index do |chord_name, index|
        transpose = @classic ? 0 : 12
        chord_bank.fetch(chord_name).each_with_index do |note, voice|
          pads.note(note + transpose, index * 2.0, 1.82, Groove.rng.rand(42..58) + voice * 4, feel: :melody)
        end
      end
      pads.finish
    end

    def add_melody
      lead = TrackBuilder.new(@sequence, "lead-chops", 2)
      note_index = 2
      direction = 1
      steps = @bars * (@classic ? 8 : 4)
      steps.times do |step|
        if Groove.rng.rand < 0.78
          note = F_MINOR_SCALE[note_index] + (Groove.rng.rand < 0.25 ? 12 : 0)
          dur = [0.25, 0.5, 0.75, 1.0].sample(random: Groove.rng)
          lead.note(note, step * (@classic ? 0.5 : 1.0), dur, Groove.rng.rand(62..88), feel: :melody) if dur.positive?
        end
        note_index += direction * (Groove.rng.rand < 0.2 ? 2 : 1)
        if note_index >= F_MINOR_SCALE.length - 1
          note_index = F_MINOR_SCALE.length - 2
          direction = -1
        elsif note_index <= 0
          note_index = 1
          direction = 1
        end
        direction *= -1 if Groove.rng.rand < 0.18
      end
      lead.finish
    end

    def chord_cycle
      repeats = ((@bars * 4.0) / (progression.length * 2.0)).ceil
      progression.cycle.take(progression.length * repeats)
    end
  end
end

def electronium_ensure_loaded!
  DillaMusicGems.midi_ensure!
rescue LoadError
  abort "midilib required — cd MASTER && bundle install"
end

def electronium_render_audio(midi_path, audio_path = nil)
  require_playback_tool!
  audio_path ||= midi_path.sub(/\.mid\z/i, ".wav")
  sf2 = pad_soundfont_path
  abort "no soundfont — install GeneralUser-GS or set DILLA_SOUNDFONT" unless sf2 && File.exist?(sf2)
  wav_tmp = audio_path.end_with?(".mp3") ? audio_path.sub(/\.mp3\z/i, ".wav") : audio_path
  sh! "fluidsynth", "-ni", "-g", "1.4", "-F", wav_tmp, "-r", SAMPLE_RATE.to_s, sf2, midi_path
  if audio_path.end_with?(".mp3")
    sh! "ffmpeg", "-y", "-i", wav_tmp, "-acodec", "libmp3lame", "-ab", "192k", audio_path
    FileUtils.rm_f(wav_tmp)
  end
  puts "rendered #{audio_path}"
  audio_path
end

def electronium_full_render(destination = File.join(OUTPUT_DIR, "electronium.wav"), classic: false)
  track = classic ? "electronium_classic" : "electronium_loop"
  ENV["TRACK"] = track
  apply_track_soul_profile!(track, force: false)
  apply_best_defaults!
  n = (ENV["BARS"] || 32).to_i
  render_dilla(destination, n)
  puts "electronium full render → #{destination} (TRACK=#{track} #{n} bars)"
  destination
end

def electronium_generate(destination = File.join(OUTPUT_DIR, "electronium.mid"), classic: false,
                         render_audio: false, full_render: false)
  if full_render
    out = destination.sub(/\.mid\z/i, ".wav")
    return electronium_full_render(out, classic: classic)
  end
  electronium_ensure_loaded!
  FileUtils.rm_f(destination)
  n_bars = [(ENV["BARS"] || 32).to_i, 8].max
  sept = ENV.fetch("ELECTRONIUM_SEPTUPLET", classic ? "1" : "0") != "0"
  path = DillaElectronium::Composer.new(
    bpm: bpm.to_i, bars: n_bars, classic: classic, septuplet_hats: sept
  ).write(destination)
  puts "wrote #{path} (#{classic ? 'classic 7ths' : 'lush 9ths'}, #{n_bars} bars @ #{bpm.to_i} BPM)"
  if render_audio
    audio = destination.sub(/\.mid\z/i, ".mp3")
    electronium_render_audio(path, audio)
    play(audio) if tool_available?("ffplay")
  end
  path
end

def electronium_dispatch!
  classic = ENV["ELECTRONIUM_CLASSIC"] == "1"
  render_audio = ENV["ELECTRONIUM_RENDER"] == "1"
  dest = ARGV.find { |a| a =~ /\.(mid|mp3|wav)\z/i } || File.join(OUTPUT_DIR, "electronium.mid")
  electronium_generate(dest, classic: classic, render_audio: render_audio)
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
  "industrial-dark" => "INDUSTRIAL_DARK", "reharm-loop" => "REHARM_LOOP", "prime-grid" => "PRIME_GRID",
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
  "stream-crossfade" => "STREAM_CROSSFADE", "stream-gap" => "STREAM_GAP",
  "stream-creative-freedom" => "STREAM_CREATIVE_FREEDOM", "stream-evolve-performer" => "STREAM_EVOLVE_PERFORMER",
  "form" => "FORM", "section-map" => "SECTION_MAP", "render-mode" => "RENDER_MODE",
  "harmony-lead" => "HARMONY_LEAD", "harmony-lep-mode" => "HARMONY_LEP_MODE",
  "harmony-arp-style" => "HARMONY_ARP_STYLE", "stream-soul" => "STREAM_SOUL",
  "electronium-classic" => "ELECTRONIUM_CLASSIC", "electronium-render" => "ELECTRONIUM_RENDER",
  "electronium-septuplet" => "ELECTRONIUM_SEPTUPLET",
  "stream-track" => "STREAM_TRACK", "stream-lock" => "STREAM_LOCK",
  "stem-export" => "STEM_EXPORT", "keep-stems" => "KEEP_STEMS",
  "ghost-tier" => "GHOST_TIER", "motif-recall" => "MOTIF_RECALL", "slash-bass" => "SLASH_BASS",
  "profile-mash" => "PROFILE_MASH", "groove-score-min" => "GROOVE_SCORE_MIN",
  "promotion-beauty-min" => "PROMOTION_BEAUTY_MIN"
}.freeze

def apply_flags!(argv)
  argv.reject! do |arg|
    next false unless arg.start_with?("--")
    key, _, value = arg.delete_prefix("--").partition("=")
    env_name = FLAG_ENV[key] or abort "unknown flag --#{key} — known: #{FLAG_ENV.keys.map { |k| "--#{k}" }.join(' ')}"
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
    path = RadioBergenStudy.write!(audio_root: audio_root)
    data = RadioBergenStudy.study!(audio_root: audio_root)
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
    path = RadioBergenStudy.write_dossiers!(audio_root: audio_root)
    data = RadioBergenStudy.dossiers!(audio_root: audio_root)
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
    py = File.expand_path("../audio/.venv/bin/python3", ROOT)
    script = File.expand_path("../audio/radio_bergen_librosa_analyze.py", ROOT)
    unless File.executable?(py) && File.file?(script)
      abort "librosa venv missing — run: cd MASTER/tools/audio && python3 -m venv .venv && .venv/bin/pip install librosa pyyaml"
    end
    sh! py, script
  },
  "rhythm" => -> { rhythm(ARGV.shift) },
  "melody" => -> { melody(ARGV.shift) },
  "harmony" => -> { harmony(ARGV.shift) },
  "beauty" => -> { beauty_report(ARGV.shift) },
  "crit" => -> { crit_session_cli!(ARGV.shift) },
  "phone-preview" => -> { phone_preview(ARGV.shift) },
  "semantics" => -> { semantics(ARGV.shift) },
  "ears" => -> { ears(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3")) },
  "play" => -> { play(ARGV.shift, (ARGV.shift || 8).to_i) },
  "live" => -> { live((ARGV.shift || 32).to_i) },
  "stream" => -> { stream((ARGV.shift || stream_bars_default).to_i) },
  "live_now" => -> { live_now },
  "harmony_now" => -> { harmony_now },
  "regenerate" => -> { regenerate((ARGV.shift || 16).to_i) },
  "regenerate-stem" => lambda do
    stem = ARGV.shift or abort "usage: ruby dilla.rb regenerate-stem bass|hats|melody [bars]"
    regenerate_stem(stem, (ARGV.shift || 16).to_i)
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
  "dilla" => lambda do
    dest = ARGV.shift || File.join(OUTPUT_DIR, "beat.mp3")
    n_bars = ARGV[0]&.match?(/\A\d+\z/) ? ARGV.shift.to_i : nil
    # Soft-apply kit-forward style so one-shots match stream (empty ENV only).
    apply_dilla_style!(force: false) unless ENV["DILLA_RAW"] == "1"
    render_dilla(dest, n_bars)
  end,
  "camel" => lambda do
    dest = ARGV.shift || File.join(OUTPUT_DIR, "camel.mp3")
    n_bars = ARGV[0]&.match?(/\A\d+\z/) ? ARGV.shift.to_i : nil
    apply_camel_profile!(force: false)
    render_dilla(dest, n_bars)
  end,
  "hiphop" => -> { render_hiphop(ARGV.shift || File.join(OUTPUT_DIR, "hiphop.mp3")) },
  "slum" => -> { render_slum_album(ARGV.shift || File.join(ROOT, "renders")) },
  "industrial" => -> { render_industrial(ARGV.shift || File.join(ROOT, "renders", "foundry_pulse.mp3")) },
  "techno" => -> { render_techno(ARGV.shift || File.join(OUTPUT_DIR, "techno_hate.mp3")) },
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
    learn_flylo_drums!(src, track: track, slug: slug, apply: apply, deep: deep)
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
    learn_playlist_batch!(youtube_only: youtube_only, deep: deep, resume: resume, limit: limit, force: force,
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
    learn_calibrate!(audio_root: audio_root)
  end,
  "learn-diff" => lambda do
    audio_root = nil
    if (idx = ARGV.index("--audio-root"))
      audio_root = ARGV[idx + 1]
    end
    learn_diff_dossiers!(audio_root: audio_root)
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
      rap_vocal_fit!(slug, beat_bpm: cfg[:bpm], n_bars: n_bars)
    when "list"
      puts JSON.pretty_generate(rap_vocal_load_catalog)
    else
      abort "usage: ruby dilla.rb rap-vocal ingest|fit|list"
    end
  end,
  "liveset" => lambda do
    set = ARGV.shift || stems_load_manifest["active"] || "default"
    mins = (ARGV.shift || LIVESET_MIN).to_i
    render_liveset(set, minutes: mins)
  end
}.freeze

COMMAND_ALIASES = {
  "midi" => "electronium",
  "beat" => "dilla",
  "ingest" => "learn",
  "download" => "source",
  "flylo-learn" => "learn-flylo"
}.freeze
COMMANDS = (DISPATCH.keys + COMMAND_ALIASES.keys).sort.freeze

def render_output_path?(token)
  token =~ /\.(wav|mp3|flac|ogg|m4a|aiff?)\z/i
end

if __FILE__ == $PROGRAM_NAME
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
    # Bare invoke: continuous dilla-style stream.
    ENV["RENDER_MODE"] = "dilla" if ENV["RENDER_MODE"].to_s.empty? ||
                                    ENV["RENDER_MODE"].to_s.downcase == "camel"
    ENV["STREAM_SOUL"] = "1" if ENV["STREAM_SOUL"].to_s.empty?
    ENV["SPEAK"] = "0" if ENV["SPEAK"].to_s.empty?
    ENV["STREAM_CONTINUOUS"] = "1" if ENV["STREAM_CONTINUOUS"].to_s.empty?
    apply_dilla_style!(force: false)
    stream((ENV["BARS"] || "32").to_i)
  elsif render_output_path?(cmd) && !DISPATCH.key?(cmd) && !COMMAND_ALIASES.key?(cmd)
    ARGV.unshift(cmd)
    default_render!
  else
    handler = DISPATCH[COMMAND_ALIASES.fetch(cmd, cmd)]
    handler ? handler.call : help
  end
end
