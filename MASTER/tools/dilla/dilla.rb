#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Dilla Lab — unified audio engine
# Synthesis, analog pads, vocal mixes (v7–v11), stem rack, demux, MIDI electronium.
#
# Usage: ruby dilla.rb help

require "fileutils"
require "json"
require_relative "../../lib/reach/analog_capabilities"
require "open3"

ROOT = File.expand_path(__dir__)
# Finished renders default to the user's home directory, not the repo — ROOT
# stays the base for samples/stems/scratch temp files, which aren't user output.
OUTPUT_DIR = ENV.fetch("DILLA_OUTPUT_DIR", Dir.pwd)
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
      "engine_progression" => "timeless_authentic",
      "engine_chords" => %w[Fm9 Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9],
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
      "engine_chords" => %w[Gmaj7 Bmin7 Cmaj9 Gmaj7]
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
  }
}.freeze

TRACK_SONIC_MAP = {
  timeless: :dilla_timeless,
  chromatic_minor_descent: :dilla_timeless,
  neo_soul: :slum_players,
  chromatic_mediant: :flylo_camel,
  chromatic_mediant_drift: :flylo_camel,
  sus_add9_ballad: :madlib_eye,
  generated_mediant: :flylo_camel,
  generated_planing: :dilla_timeless,
  generated: :dilla_timeless,
  players: :slum_players,
  fourth_third_sixth_second_turn: :dilla_timeless
}.freeze

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
  flylo_wobble: ->(n) { (0...n).flat_map { |i| [i, i, (i + 1) % n] }.first(n * 3) }
}.freeze

# Rich synth patch catalog — GM programs, optional external sf2, native fallback timbres,
# and per-patch post-FX chains (tremolo/LFO/filter/delay) applied at render time.
def synth_patch(id, role:, program:, bank: 0, sf2: :default, weight: 1.0, native: nil, mix: 1.0, fx: nil,
                arp_styles: nil, octave: 2, gate: 0.82, color: nil, fs_gain: 1.5)
  { id: id, role: role, program: program, bank: bank, sf2: sf2, weight: weight, native: native,
    mix: mix, fx: fx, arp_styles: arp_styles || [:up, :updown], octave: octave, gate: gate, color: color,
    fs_gain: fs_gain }
end

SYNTH_PATCH_CATALOG = [
  # --- Electric keys (EP / Rhodes family) ---
  synth_patch(:rhodes_mark1, role: :ep, program: 4, weight: 3.2, mix: 1.15, fs_gain: 1.65,
              color: "Mark I warm tine",
              fx: "tremolo=f=0.42:d=0.06,aecho=0.38:0.48:55|95:0.22|0.12,lowpass=f=4200,equalizer=f=280:t=o:w=1:g=2.5"),
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
  synth_patch(:organ_drawbar, role: :ep, program: 16, color: "drawbar soul"),
  synth_patch(:organ_perc, role: :ep, program: 17, color: "perc organ"),
  # --- Warm analog pads (Moog / Prophet / Juno) ---
  synth_patch(:moog_model_d, role: :warm, program: 91, weight: 3.0, mix: 0.82, fs_gain: 1.45,
              color: "Minimoog ladder pad",
              fx: "lowpass=f=2400:width_type=q:width=0.85,tremolo=f=0.28:d=0.1,chorus=0.38:0.58:32|42:0.16|0.12:0.2|0.18:0.9|1.2,equalizer=f=180:t=o:w=1:g=2.2"),
  synth_patch(:moog_sub37_pad, role: :warm, program: 38, weight: 2.4, mix: 0.78, fs_gain: 1.4,
              color: "Moog sub harmonic pad",
              fx: "lowpass=f=2200,equalizer=f=95:t=o:w=0.8:g=3.5,aphaser=speed=0.1:decay=0.55"),
  synth_patch(:moog_bleeding_edge, role: :warm, program: 91, weight: 1.8, mix: 0.85, fs_gain: 1.5,
              color: "Moog + tape drift",
              fx: "vibrato=f=0.18:d=0.014,tremolo=f=0.55:d=0.12,aecho=0.42:0.52:100|190:0.28|0.14,lowpass=f=3000"),
  synth_patch(:prophet_5_pad, role: :warm, program: 89, weight: 3.2, mix: 0.8, fs_gain: 1.5,
              color: "Prophet-5 poly",
              fx: "chorus=0.48:0.68:34|44:0.22|0.18:0.26|0.22:1.05|1.35,vibrato=f=0.3:d=0.016,lowpass=f=3600"),
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
              fx: "chorus=0.42:0.62:32|42:0.18|0.14:0.22|0.18:0.95|1.2,aecho=0.5:0.4:150|280:0.3|0.18,lowpass=f=4800"),
  synth_patch(:big_lead_prophet5, role: :lead, program: 87, weight: 2.8, fs_gain: 1.4, arp_styles: %i[pingpong quint_spread], octave: 2,
              fx: "chorus=0.52:0.72:36|46:0.24|0.2:0.28|0.22:1.15|1.45,aecho=0.45:0.38:140|260:0.28|0.16,lowpass=f=5400"),
  synth_patch(:prophet_bleeding_lead, role: :lead, program: 87, sf2: :supersaw, weight: 1.6, fs_gain: 1.38,
              arp_styles: %i[spiral coltrane], octave: 2,
              fx: "chorus=0.58:0.78:44|54:0.3|0.25:0.32|0.28:1.25|1.6,aphaser=speed=0.16:decay=0.5,vibrato=f=0.38:d=0.015"),
  synth_patch(:charang_bite, role: :lead, program: 84, arp_styles: %i[up fibonacci], octave: 2,
              fx: "tremolo=f=5.5:d=0.18,aecho=0.5:0.38:140|260:0.28|0.16"),
  synth_patch(:fifths_lead, role: :lead, program: 86, arp_styles: %i[updown coltrane], octave: 2,
              fx: "vibrato=f=0.55:d=0.02,lowpass=f=4800"),
  synth_patch(:saw_lead, role: :lead, program: 81, arp_styles: %i[random_walk flylo_wobble], octave: 2,
              fx: "tremolo=f=3.2:d=0.2,aphaser=speed=0.22:decay=0.45"),
  synth_patch(:square_lead, role: :lead, program: 80, arp_styles: %i[euclidean donda_stab], octave: 2,
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
              fx: "lowpass=f=2200:width_type=q:width=0.8,tremolo=f=2.5:d=0.12,equalizer=f=140:t=o:w=0.9:g=2.5,aecho=0.42:0.35:110|200:0.22|0.1"),
  synth_patch(:moog_ladder_lead, role: :lead, program: 38, weight: 2.0, fs_gain: 1.32, arp_styles: %i[updown fibonacci], octave: 1,
              fx: "lowpass=f=2800,tremolo=f=3.5:d=0.14,chorus=0.35:0.55:28|36:0.14|0.1:0.18|0.14:0.85|1.1"),
  synth_patch(:cs_lead, role: :lead, program: 82, arp_styles: %i[downup quint_spread], octave: 2,
              fx: "chorus=0.4:0.6:35|45:0.2|0.15:0.2|0.2:0.9|1.2"),
  # --- Native additive fallbacks (no soundfont) ---
  synth_patch(:native_rhodes, role: :native, program: 0, weight: 2.5, native: { wave: :rhodes, detune: 0.005, bloom: 0.34 }),
  synth_patch(:native_rhodes_bleeding, role: :native, program: 0, weight: 1.8, native: { wave: :rhodes, detune: 0.008, bloom: 0.42 }),
  synth_patch(:native_juno, role: :native, program: 0, native: { wave: :juno, detune: 0.006, bloom: 0.18 }),
  synth_patch(:native_prophet, role: :native, program: 0, weight: 2.2, native: { wave: :prophet, detune: 0.007, bloom: 0.26 }),
  synth_patch(:native_moog, role: :native, program: 0, weight: 2.2, native: { wave: :moog, detune: 0.005, bloom: 0.24 }),
  synth_patch(:native_fm_glass, role: :native, program: 0, native: { wave: :fm, detune: 0.002, bloom: 0.35 }),
  synth_patch(:native_organ, role: :native, program: 0, native: { wave: :organ, detune: 0.003, bloom: 0.12 }),
  synth_patch(:native_warm_pad, role: :native, program: 0, native: { wave: :triangle, detune: 0.007, bloom: 0.15 }),
  synth_patch(:native_string, role: :native, program: 0, native: { wave: :bowed, detune: 0.004, bloom: 0.2 }),
  synth_patch(:native_pwm, role: :native, program: 0, native: { wave: :pwm, detune: 0.008, bloom: 0.25 })
].freeze

SYNTH_PATCH_BY_ROLE = SYNTH_PATCH_CATALOG.group_by { |p| p[:role] }.freeze

def weighted_patch_pick(role, seed: nil)
  pool = SYNTH_PATCH_BY_ROLE.fetch(role, [])
  return nil if pool.empty?
  rng = Random.new(seed || @render_seed || rand(1_000_000))
  total = pool.sum { |p| p[:weight] }
  roll = rng.rand * total
  pool.each do |patch|
    roll -= patch[:weight]
    return patch if roll <= 0
  end
  pool.last
end

def pick_synth_patches!(cfg)
  seed = (cfg[:track].to_s.hash.abs % 100_000) + (@render_seed || 0)
  @render_ep_patch = weighted_patch_pick(:ep, seed: seed)
  @render_warm_patch = weighted_patch_pick(:warm, seed: seed + 17)
  @render_texture_patch = weighted_patch_pick(:texture, seed: seed + 29)
  @render_lead_patch = weighted_patch_pick(:lead, seed: seed + 41)
  @render_native_patch = weighted_patch_pick(:native, seed: seed + 53)
  @render_arp_style = (@render_lead_patch&.dig(:arp_styles) || [:updown]).sample(random: Random.new(seed + 67))
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

def load_sonic_profiles
  return @sonic_profiles if defined?(@sonic_profiles) && @sonic_profiles
  @sonic_profiles = INLINE_SONIC_PROFILES
end

def sonic_profile_for(track)
  key = TRACK_SONIC_MAP.fetch(track.to_sym, nil)
  return nil unless key
  load_sonic_profiles[key]
end

def style_family(track, feel: nil)
  return :flylo if FLYLO_TRACKS.include?(track.to_sym) || feel == :loose_pocket
  return :dilla if DILLA_TRACKS.include?(track.to_sym) ||
                   %i[timeless organic chromatic_planing syncopated_slash_ninth].include?(feel)
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
  base = if sonic_swing && sonic_swing < 1.0
           (sonic_swing * 100.0) + time_offset
         else
           preset.fetch(:swing, 58).to_f + time_offset
         end
  base.clamp(0.0, 72.0)
end

def enhanced_resolve_config
  track = (ENV["TRACK"] || "timeless").to_s.downcase.tr("-", "_").to_sym
  preset = TRACK_PRESETS.fetch(track, TRACK_PRESETS[:timeless])
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
    mood_darken_strength: family == :dilla ? 0.55 : 1.0
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
  return [pads, phases] if pads.empty?
  rng = Random.new((cfg[:track].to_s.hash.abs % 100_000) + pads.length)
  voicing = cfg[:voicing]
  recap_voicing = CONTRAST_VOICINGS.fetch(voicing, :drop2)
  out = []
  phases_out = []
  pads.each_with_index do |chord, i|
    phase = phases[i]
    chord_voicing = case phase
                    when :recapitulation then recap_voicing
                    when :development then (voicing == :spread ? :drop2 : voicing)
                    else voicing
                    end
    out << decorate_chord(chord, voicing: chord_voicing)
    phases_out << phase
    next_chord = pads[(i + 1) % pads.length]
    motion = root_motion_semitones(chord, next_chord)
    if phase == :development && i < pads.length - 1 && motion <= 4 && rng.rand < 0.06
      out << passing_cluster_between(chord, next_chord, rng)
      phases_out << :development
    end
  end
  enriched = out.map.with_index do |c, i|
    phase = phases_out[i]
    shift = phase == :development && (i % 8) == 7 ? 1 : 0
    next c if shift.zero? || c[:name].to_s.start_with?("pass_")
    { name: "#{c[:name]}_t#{shift}", hz: c[:hz].map { |h| (h * (2**(shift / 12.0))).round(2) } }
  end
  [enriched, phases_out.first(enriched.length)]
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
  sec = dilla_section(bar, n_bars)
  base = case sec
         when :intro then 0.55
         when :breakdown then 0.45
         when :build
           build_start = (n_bars * 0.82).to_i
           0.72 + 0.28 * ((bar - build_start).to_f / [n_bars * 0.18, 1].max).clamp(0.0, 1.0)
         when :outro then 0.5
         else 1.0
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

  # Clap layer 2&4
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

def kicks_enabled?
  ENV.fetch("KICKS", "1") != "0"
end

def kick_velocity_scale
  ENV.fetch("KICK_GAIN", "0.38").to_f.clamp(0.08, 1.0)
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
  sonic&.dig("synth", "vinyl_noise")&.to_f || 0.08
end

def sonic_bass_shelf(sonic)
  sonic&.dig("synth", "bass_shelf_db")&.to_f || 6.0
end

def build_harm_bus_filter(idx, duration, _cfg, sonic, harm_fade_start, harm_fade_dur, beat_p, _n_bars)
  lp = sonic_pad_lowpass(sonic)
  build_start = (duration * 0.82).round(2)
  outro_fade = (beat_p * 4.0 * 4).round(2)
  harm_vol = ENV["DEBUG_HARM_WEIGHT"] || "1.68"
  "[#{idx}:a]aformat=channel_layouts=stereo,volume=#{harm_vol}," \
    "highpass=f=110,equalizer=f=95:t=h:w=120:g=-2.2," \
    "equalizer=f=420:t=o:w=1.1:g=2.8,equalizer=f=680:t=h:w=900:g=2.6,equalizer=f=1400:t=h:w=1200:g=2.4," \
    "equalizer=f=2800:t=h:w=1800:g=1.2,equalizer=f=#{lp}:t=o:w=1.0:g=0.8," \
    "afade=t=in:st=#{harm_fade_start}:d=#{harm_fade_dur}," \
    "afade=t=out:st=#{(duration - outro_fade).round(2)}:d=#{outro_fade}," \
    "equalizer=f=800:t=h:w=600:g=-3:enable='between(t,#{build_start},#{duration})'[harm]"
end

def flylo_sidechain_filters(drum_label: "[drums]", harm_label: "[harm]")
  [
    "#{drum_label}asplit=2[dr_dry][dr_sc]",
    "#{harm_label}[dr_sc]sidechaincompress=threshold=-22dB:ratio=6:attack=0.75:release=14:level_sc=0.9[harm_sc]",
    "[dr_dry][harm_sc]amix=inputs=2:weights=1.0 1.6:duration=first:normalize=0[sc_mix]"
  ]
end

def build_drum_bus_filter(cfg, sonic, duration: nil)
  base = cfg[:style_family] == :dilla ? { bits: 11, samples: 1.5, mix: 0.22 } : { bits: 8, samples: 1.2, mix: 0.12 }
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
  kick_boost = cfg[:style_family] == :dilla ? 0.15 : 0.5
  drum_vol = (ENV["DEBUG_DRUM_WEIGHT"] || (0.22 * kick_velocity_scale + 0.08).round(2)).to_s
  "[0:a]aformat=channel_layouts=stereo,volume=#{drum_vol}," \
    "equalizer=f=480:t=h:w=420:g=-4.5,#{crush}" \
    "equalizer=f=58:t=o:w=0.8:g=#{kick_boost},highpass=f=28#{haas}[drums]"
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
    if duration
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
  filt << analog_drift_filter("monobassed", out_tag: "drifted")
  darken = cfg.fetch(:mood_darken_strength, 1.0)
  filt << mood_darken_filter("drifted", out_tag: "darkened", strength: darken)
  reverb_out = "darkened"
  if ir_input_idx
    filt << convolution_reverb_filter("darkened", ir_input_idx, mix: 0.18, out_tag: "reverbed")
    reverb_out = "reverbed"
  end
  if duration
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

def arp_degrees_for(style, tone_count, rng)
  builder = ARP_PATTERN_BUILDERS[style] || ARP_PATTERN_BUILDERS[:updown]
  raw = builder.arity >= 2 ? builder.call(tone_count, rng) : builder.call(tone_count)
  raw.map { |d| d % tone_count }
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
  gate_mul = lead_patch&.fetch(:gate, 0.82) || 0.82
  octave_mul = 2.0 ** ((lead_patch&.fetch(:octave, 2) || 2) - 2)
  events = []
  burst_remaining = 0
  pad_events.each_with_index do |(time, velocity, chord, sustain), i|
    next unless chord && chord[:hz]&.any?
    bar_approx = (time / bar_p).floor.clamp(0, n_bars - 1)
    section = dilla_section(bar_approx, n_bars)
    progress = i.to_f / [pad_events.length - 1, 1].max
    if burst_remaining.positive?
      burst_remaining -= 1
    else
      chance = lead_section_chance(section, progress)
      chance += 0.15 if i % 11 == 5
      next unless rng.rand < chance
      burst_remaining = rng.rand(1..3)
    end
    tones = chord[:hz].sort.map { |hz| hz * octave_mul }
    pattern = case i % 5
              when 0 then leitmotif
              when 1 then invert_motif(leitmotif)
              when 2 then leitmotif.reverse
              when 3 then arp_degrees_for(arp_style, tones.length, rng)
              else leitmotif + invert_motif(leitmotif)
              end
    pattern = arp_degrees_for(arp_style, tones.length, rng) if rng.rand < 0.35
    subdiv = case arp_style
             when :flylo_wobble, :euclidean then 3
             when :random_walk, :spiral then 4
             else 2
             end
    step_dur = [(sustain || 1.0) / (pattern.length * subdiv.to_f), 0.045].max
    step_dur *= 1.35 if section == :build
    step_dur *= 0.72 if gate_mul < 0.6
    swing_push = cfg[:quintuplet] ? step_dur * 0.04 : 0.0
    pattern.each_with_index do |degree, step|
      hz = tones[degree % tones.length]
      approach = step.zero? && i.positive? ? hz * (2**(1.0 / 12.0)) : hz
      t = time + 0.04 + step * step_dur + (step.odd? ? swing_push : 0.0)
      vel = (velocity * (0.88 - step * 0.04)).clamp(0.18, 0.95)
      vel *= 1.12 if section == :build
      pan = cfg[:stereo_pan] ? (step.even? ? -0.45 : 0.45) : (step.even? ? -0.12 : 0.12)
      events << [t, vel, { name: "lead", hz: [approach] }, step_dur * gate_mul, pan]
    end
    next unless rng.rand < 0.55 && i.positive?
    answer_style = ARP_PATTERN_BUILDERS.keys.sample(random: rng)
    answer_pat = arp_degrees_for(answer_style, tones.length, rng)
    answer_offset = pattern.length * step_dur * 0.45
    answer_oct = octave_mul * 0.5
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
  patch_fx = @render_warm_patch&.dig(:fx) || @render_ep_patch&.dig(:fx)
  filt = [
    "aformat=channel_layouts=stereo",
    "lowpass=f=#{lp}:width_type=q:width=0.88",
    "equalizer=f=260:t=o:w=1.0:g=2.6",
    "equalizer=f=520:t=h:w=700:g=2.4",
    "equalizer=f=1100:t=o:w=0.9:g=-0.8",
    "equalizer=f=3200:t=h:w=1600:g=1.4",
    "equalizer=f=4800:t=o:w=1.4:g=-1.8",
    ("tremolo=f=4.5:d=0.08" if cfg[:style_family] == :dilla),
    "aecho=0.38:0.48:120|200:0.26|0.12",
    "chorus=0.42:0.62:32|42:0.2|0.16:0.24|0.2:1.05|1.35",
    "vibrato=f=0.22:d=0.011",
    patch_fx,
    "acompressor=threshold=-24dB:ratio=1.7:attack=55:release=240:makeup=1.9",
    "volume=1.18",
    "alimiter=limit=0.96:level_out=0.98"
  ].compact.join(",")
  sh! "ffmpeg", "-y", "-i", path, "-af", filt, "-c:a", "pcm_s16le", tmp
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
  { name: "Db/E", hz: [82.41, 277.18, 311.13, 349.23, 415.30] },
  { name: "C/E", hz: [82.41, 261.63, 329.63, 392.00, 493.88] },
  { name: "Bm/E", hz: [82.41, 246.94, 293.66, 369.99, 440.00] },
  { name: "Bbm/E", hz: [82.41, 233.08, 277.18, 349.23, 415.30] },
  { name: "Am/E", hz: [82.41, 220.00, 261.63, 329.63, 392.00] },
  { name: "E9sus4", hz: [82.41, 220.00, 246.94, 293.66, 369.99] }
].freeze
COMMANDS = %w[
  help scan sweep council debug sample source livestream separate render verify
  chords clean stems study rhythm melody harmony semantics ears play live live_now harmony_now regenerate bass
  grade grade_list sonitex_list analog_list prepare loose_pocket dilla hiphop slum industrial techno analog analog_liveset
  electronium midi mix v7 v8 v9 v10 v11 demux liveset quality
  capabilities fetch-assets use-external-kit
].freeze
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
  dub_chamber: { stock: :tape_500, fx: %w[spectral_warmth tape_saturation dub_delay chamber_reverb haas_jitter analog_noise] }
}.freeze
ANALOG_CHAIN_ROTATE = %i[acetate sp1200 cassette broadcast lo_fi vinyl_hot sonitex vinyl_lab dub_chamber].freeze
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
MICROTIMING_MS = {
  kick_anchor: 0..5,
  kick_sync: 4..16,
  snare: -24..-8,
  ghost: -14..12,
  hat_down: -4..6,
  hat_up: 10..28,
  bass: 20..36,
  pad: 4..16
}.freeze
SYNCOPATED_KICK_PATTERNS = [
  [0, 7, 10, 14],
  [0, 5, 7, 10, 14],
  [0, 3, 7, 10, 12, 14],
  [0, 1, 7, 10, 14],
  [0, 6, 9, 14],
  [0, 4, 8, 11, 14],
  [0, 2, 7, 9, 13, 15],
  [0, 5, 8, 10, 14],
  [0, 3, 6, 10, 12, 14, 15]
].freeze
GHOST_NOTE_PATTERNS = [
  [3, 6, 11],
  [2, 5, 10, 14],
  [1, 7, 9, 13],
  [4, 8, 11, 15],
  [3, 5, 9, 12],
  [2, 6, 10, 13]
].freeze
MELODY_CHOP_HZ = [392.00, 349.23, 311.13, 277.18, 261.63, 233.08].freeze
# Madlib / Jaylib — loose MPC pockets, heavy ghosts, Dilla-time snare-early feel.
LOOSE_POCKET_KICK_PATTERNS = [
  [0, 6, 10, 14],
  [0, 3, 7, 11, 14],
  [0, 5, 8, 12, 15],
  [0, 1, 7, 10, 13],
  [0, 4, 9, 11, 14],
  [0, 2, 6, 10, 14]
].freeze
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
# Album / track progressions — Fantastic Vol. 1 & 2 + Donuts.
CHORD_PROGRESSIONS = {
  soul: %w[Fm9 Dbmaj9 Ebmaj9 Abmaj9],
  chromatic_minor_descent: %w[Fm9 Dbmaj9 Bbm9 Eb7 Abmaj9low C7b9 Fm/C Bb7sus],
  borrowed_dominant_turn: %w[Dbmaj9 Cm9 Fm9 Bbm9 Ebmaj9],
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
  # Chromatic-mediant and tritone movement for a denser LA beat-scene field.
  chromatic_mediant: ["Cm9", "E altered", "Bbm9", "Gbmaj9", "Dm9", "G7", "Cmaj9", "E altered"],
  neo_soul: %w[Fm9 Bbm9 Ebmaj9 Abmaj9low Dbmaj9 Cm9 C7b9 Fm9],
  tritone: %w[Cm9 Gbmaj9 Bbm9 E\ altered],
  syncopated_slash_ninth: %w[E9sus4/D Db/E C/E Bm/E Bbm/E Am/E E9sus4],
  chromatic_planing: %w[Fm9 Bbm9 Fm9 Bbm9],
  ascending_minor_stack: %w[Am9 Dm9 Gm9 Cm9],
  minor_soul_loop: %w[Bbm9 Ebmaj9 Abmaj9 Fm9],
  suspended_minor_turn: %w[Dm9 Gm9 Cm9 Fmaj9],
  major_relative_minor_cycle: %w[Fmaj9 Em9 Am9 Dm9],
  dominant_minor_resolve: %w[Em9 Am9 Dm9 G7],
  syncopated_slash_alt: %w[E9sus4/D C/E Bbm/E Am/E Db/E Bm/E E9sus4],
  minor_cycle_descent: %w[Gm9 Cm9 Fm9 Bbm9],
  minor_stepwise_cycle: %w[Am9 Dm9 Gm9 Cm9],
  # Real Climax changes (ChordU) — was a fabricated Fm9/Dbmaj9/Ebmaj9/Bbm9
  # loop in a completely different key from the actual track.
  major7_relative_minor_turn: %w[Emaj7 G#m7 C#m7 E7climax],
  minor_major_ninth_pair: %w[Fm9 Bbm9 Ebmaj9 Abmaj9],
  minor_stepwise_ascent: %w[Dm9 Gm9 Cm9 Fmaj9],
  suspended_minor_close: %w[Cm9 Fm9 Bbm9 Ebmaj9],
  alternating_minor7_pair: %w[Ebm7fil Bbm7fil Ebm7fil Bbm7fil],
  # D'Angelo — Untitled (How Does It Feel), Voodoo. Verse then bridge.
  sus_add9_ballad: %w[Dadd9 A7sus4 G6 C9 F#m9 B9 Em9 Asus9],
  # Flying Lotus — Never Catch Me. Main loop then the tritone-sub modulation.
  chromatic_mediant_drift: %w[Dm9 Cm11nc AbMaj13s11 Gm7 Eb7 A7nc Dmaj9nc DMaj7overG]
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
  chromatic_mediant_drift: { bpm: 78, progression: :chromatic_mediant_drift, chord_bars: 2, phrase_bars: 16, swing: 60,
                     feel: :loose_pocket, stereo_pan: true, sidechain: true, voicing: :quartal, intro_bars: 8,
                     half_time_bars: (32..47),
                     timing: { snare: -28..-12, hat_up: 18..36, bass: 24..44, kick_anchor: 0..6, pad: 6..20 } },
  suspended_minor_close: { bpm: 91, progression: :suspended_minor_close, chord_bars: 2, swing: 56 },
  borrowed_dominant_turn: { bpm: 95, progression: :borrowed_dominant_turn, chord_bars: 2, swing: 52 },
  timeless: {
    bpm: 86, progression: :timeless_authentic, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -24..-8, hat_up: 14..28, bass: 22..40, kick_anchor: 0..5, pad: 2..14, kick_sync: 6..18 }
  },
  chromatic_minor_descent: {
    bpm: 86, progression: :chromatic_minor_descent, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread,
    timing: { snare: -22..-10, hat_up: 14..28, bass: 22..38, kick_anchor: 0..4 }
  },
  soul: { bpm: 86, progression: :soul, chord_bars: 4, swing: 58 },
  jazz: { bpm: 88, progression: :jazz, chord_bars: 4, swing: 60 },
  fourth_third_sixth_second_turn: {
    bpm: 86, progression: :fourth_third_sixth_second_turn, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread
  },
  voice_led_minor_arc: {
    bpm: 86, progression: :voice_led_minor_arc, chord_bars: 2, phrase_bars: 16, swing: 56,
    feel: :timeless, quintuplet: true, voicing: :spread
  },
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
  players: {
    bpm: 93, progression: :measured_dominant_field, chord_bars: 2, phrase_bars: 16, swing: 58,
    feel: :timeless, voicing: :spread
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

# Flying Lotus's language (per "Never Catch Me" chord analysis): root
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
  display = command.flatten.join(" ")
  display = "#{display.byteslice(0, 420)}… (#{display.bytesize} bytes)" if display.bytesize > 460
  puts ">>> #{display}"
  abort "failed: #{command.flatten.first}" unless system(*command.flatten.map(&:to_s))
end

def capture(*command)
  Open3.capture3(*command.flatten.map(&:to_s))
end

def tool_available?(name)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |directory| File.executable?(File.join(directory, name)) }
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

def chop_hz(chord)
  case chord
  when Hash  then chord[:hz] || chord["hz"] || []
  when Array then chord
  else []
  end
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
  abort "yt-dlp required" unless tool_available?("yt-dlp")
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
  abort "demucs required" unless tool_available?("demucs")
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
  abort "yt-dlp required" unless tool_available?("yt-dlp")
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  sh! "ffmpeg", "-y", "-i", input, "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", output
  puts "wrote #{output}"
  output
end

def render(destination = File.join(OUTPUT_DIR, "full_track.mp3"))
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
  report = media_metadata(path).merge(
    schema: "dilla.master.v1", path: File.expand_path(path), delivery: File.extname(path).delete_prefix(".").downcase,
    integrated_lufs: loudness["input_i"]&.to_f, true_peak_dbtp: loudness["input_tp"]&.to_f,
    loudness_range_lu: loudness["input_lra"]&.to_f, mono_rms_db: mono, spectral_rms_db: spectrum,
    target: { integrated_lufs: -14.0..-11.0, true_peak_max_dbtp: -1.0 }, warnings: [],
    capabilities: Master::Reach::AnalogCapabilities.for(:dilla).last(5).map { |entry| entry[:id] }
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
  ranking = chord_candidates(profile.fetch(:pitch_classes)).first(16)
  puts JSON.pretty_generate(type: "harmony", path: input, duration_seconds: profile.fetch(:duration_seconds), pitch_classes: profile.fetch(:pitch_classes), chords: ranking)
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
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
    return :donuts_warm
  end
  return nil if raw =~ /\A(?:0|false|off)\z/
  return :heavy if %w[1 true on heavy].include?(raw)
  return :classic if %w[classic st1260 1260].include?(raw)
  return :extreme if %w[extreme st1269 1269].include?(raw)
  key = raw.to_sym
  SONITEX_PRESETS.key?(key) ? key : :heavy
end

def analog_resolve_variant(track: nil, rotate_index: nil)
  explicit = ENV["ANALOG_CHAIN"]&.strip
  if explicit && !explicit.empty? && explicit != "auto"
    key = explicit.to_sym
    return key if ANALOG_CHAIN_VARIANTS.key?(key)
  end
  idx = rotate_index
  unless idx
    t = track || ENV["TRACK"]
    idx = TAPE_RENDER_CATALOG.index { |e| e[:preset].to_s == t.to_s } if t
    idx ||= 0
  end
  ANALOG_CHAIN_ROTATE[idx % ANALOG_CHAIN_ROTATE.length]
end

def analog_emulation_filters(input_tag, variant, out_tag: "ana_out")
  cfg = ANALOG_CHAIN_VARIANTS.fetch(variant)
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
  # Sonitex's saturation stages (tape_saturation/harmonic_bloom-style tanh
  # waveshaping) generate real harmonic energy from whatever's loudest —
  # the bass — so a hotter bass signal comes out of Sonitex measurably
  # bassier than it went in, on top of Sonitex's own warmth/head-bump EQ.
  # A dry mix needed -7/+6dB here; Sonitex needs noticeably more.
  cut = sonitex_enabled? ? -11.0 : -7.0
  boost = sonitex_enabled? ? 8.0 : 6.0
  "[#{input_tag}]bass=g=#{cut}:f=95:width_type=h:w=170,equalizer=f=300:t=h:w=360:g=#{boost}[#{out_tag}]"
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

CONVOLUTION_IR_CACHE = File.join(ROOT, ".dilla_ir_%s.wav")

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
  master_bus_filters_enhanced(input_tag, cfg:, duration:, ir_input_idx:)
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
SPEECH_VOICES = %w[en-US-GuyNeural en-US-AndrewNeural en-US-EricNeural en-GB-RyanNeural en-AU-WilliamNeural].freeze
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

# No faker gem installed and this tool stays dependency-free by design —
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
    s = quirkify(s, rng) if rng.rand < 0.4
    sentences << s
    word_count += s.split.length
  end
  sentences.join(" ")
end

# Real structure, not a smooth gate: ~20-30s of talking, then ~20-30s of
# real silence, repeating — actual separately-synthesized segments placed
# at their own start times, not a tremolo faking it (tremolo's 0.1Hz floor
# can't reach a cycle this slow anyway).
SPEECH_TALK_SEC = 25.0
SPEECH_CYCLE_SEC = 50.0

def speak_over_track!(mp3_path, duration, _bpm = 90.0)
  return mp3_path unless File.executable?(TTS_WORKER) && tool_available?("ffmpeg")
  voice = SPEECH_VOICES.sample
  segments = []
  # Never talk right at t=0 — that reads as a scripted "intro" every time a
  # track starts/loops. Let the track establish itself first.
  t = 10.0 + rand * 14.0
  idx = 0
  while t < duration
    talk_len = SPEECH_TALK_SEC + (rand - 0.5) * 6.0
    text = continuous_speech_text(talk_len, seed: idx + rand(100_000))
    seg_path = "#{mp3_path}.voice#{idx}.mp3"
    Open3.popen2(Gem.ruby, TTS_WORKER, voice, "-35%", "-90Hz", seg_path) { |stdin, _stdout, wait|
      stdin.write(text)
      stdin.close
      wait.value
    }
    segments << { path: seg_path, start: t } if File.exist?(seg_path) && File.size(seg_path) > 500
    t += SPEECH_CYCLE_SEC + (rand - 0.5) * 8.0
    idx += 1
  end
  return mp3_path if segments.empty?

  # "Otherworldly / powerful AI" character: a heavy pitch drop, a fast
  # tremolo for a ring-modulator-ish metallic edge, and a big echo+chorus
  # for scale — not a person talking, something announcing itself.
  inputs = []
  filter_parts = []
  labels = []
  segments.each_with_index do |seg, i|
    inputs += ["-i", seg[:path]]
    delay_ms = (seg[:start] * 1000).round
    filter_parts << "[#{i + 1}:a]asetrate=44100*0.75,aresample=44100," \
                     "tremolo=f=32:d=0.15,aecho=0.7:0.6:250|450:0.4|0.28," \
                     "chorus=0.6:0.8:40|55:0.3|0.25:0.35|0.3:1.4|1.8," \
                     "adelay=#{delay_ms}|#{delay_ms},volume=1.35[voice#{i}]"
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

def play(preset_name = nil, bars_count = 8)
  abort "ffplay required" unless tool_available?("ffplay")
  preset_name ||= "dilla"
  tmp = File.join(ROOT, ".play_tmp.mp3")
  prev = ENV["BARS"]
  ENV["BARS"] = bars_count.to_s
  if preset_name == "dilla"
    render_dilla(tmp)
  else
    render(tmp)
  end
  sh! "ffplay", "-nodisp", "-autoexit", tmp
ensure
  prev ? ENV["BARS"] = prev : ENV.delete("BARS")
  FileUtils.rm_f(tmp)
end

# Loop a WAV via ffplay (rb-only playback).
def play_loop(path)
  abort "ffplay required" unless tool_available?("ffplay")
  abort "missing #{path}" unless File.exist?(path)
  cfg = dilla_resolve_config
  prog = CHORD_PROGRESSIONS[cfg[:progression]]
  prog_names = prog.is_a?(Array) ? prog.join(" → ") : cfg[:progression].to_s
  puts "looping #{path} (#{File.size(path)} bytes, #{cfg[:bpm].to_i} BPM)"
  puts "progression: #{prog_names}"
  puts "Ctrl-C to stop"
  exec "ffplay", "-nodisp", "-loop", "0", "-volume", "100", path
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
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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

STREAM_TRACKS = %w[
  timeless fourth_third_sixth_second_turn chromatic_mediant_drift chromatic_mediant
  alternating_minor7_pair syncopated_slash_ninth sus_add9_ballad neo_soul
  generated generated_planing generated_mediant generated_polytonal generated_negative generated_neapolitan generated_techno
  voice_led_minor_arc chromatic_minor_descent minor_soul_loop
].freeze

# Tempo dropped a lot over this session (92->68 BPM) without this changing,
# so the same bar count now takes much longer in real time — re-read fresh
# on every hotswap exec below rather than baked into the original CLI arg,
# so tuning this constant alone is enough going forward.
STREAM_BARS_COUNT = 16

# Non-stop chord/pad showcase: renders and plays each track once (full
# playback through real speakers, ffplay -autoexit), then moves on, forever.
# Ctrl-C to stop. No LLM/agent involved — plain local playback.
def stream(bars_count = STREAM_BARS_COUNT)
  abort "ffplay required" unless tool_available?("ffplay")
  prev_track = ENV["TRACK"]
  # Every restart (and there have been many, iterating on this live) reset
  # the rotation to index 0 — meaning repeated restarts kept replaying the
  # same first track/pattern over and over regardless of what else was in
  # rotation. Start from a random position instead.
  start_at = rand(STREAM_TRACKS.length)
  order = STREAM_TRACKS.rotate(start_at)
  # Ruby can't safely reload this file in-process (the CLI dispatch at the
  # bottom runs unconditionally, so a mid-run `load` would re-trigger it —
  # risk of recursion). exec-ing a fresh process instead is safe: it fully
  # replaces this process with a new one that reads the file from disk
  # again, so edits since the last track take effect automatically between
  # tracks without needing a manual kill+relaunch.
  self_mtime = File.mtime(__FILE__)
  puts "streaming — cycling #{order.join(', ')} (Ctrl-C to stop)"
  loop do
    order.each do |t|
      if File.mtime(__FILE__) > self_mtime
        puts "=== dilla.rb changed — restarting to pick it up ==="
        exec(Gem.ruby, __FILE__, "stream", STREAM_BARS_COUNT.to_s)
      end
      ENV["TRACK"] = t
      puts "=== #{t} ==="
      play("dilla", bars_count)
    end
  end
ensure
  prev_track ? ENV["TRACK"] = prev_track : ENV.delete("TRACK")
end

# Instantly play a modulating bass tone — good for local audio system check.
def bass(root_hz = 55.0)
  abort "ffplay required" unless tool_available?("ffplay")
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

def dilla_timing_ms(role, bar_index, step_index, timing = nil, beat_p = nil)
  cyclic_timing_offset(role, bar_index, step_index, timing, beat_p, cycle: 4)
end

def time_of_day_swing_offset
  hour = Time.now.hour
  # Peaks around 2-4am (loosest/latest feel), tightest around 2pm.
  distance_from_3am = [((hour - 3) % 24), (24 - ((hour - 3) % 24))].min
  (4.0 - distance_from_3am * (4.0 / 12.0)).round(1)
end

def dilla_resolve_config
  cfg = enhanced_resolve_config
  prog_override = ENV["PROGRESSION"]
  if prog_override
    cfg = cfg.merge(progression: prog_override.to_s.downcase.tr("-", "_").to_sym)
  end
  cfg
end

def dilla_chord_index(bar, pad_chords, chord_bars:, phrase_bars: nil)
  slot = bar / [chord_bars, 1].max
  if phrase_bars
    slots_per_phrase = phrase_bars / [chord_bars, 1].max
    slot % [slots_per_phrase, pad_chords.length].min
  else
    slot % pad_chords.length
  end
end

def dilla_swing_offset(step_index, step_p, swing, quintuplet: false)
  return 0.0 if swing.to_f <= 0.0 || step_index.even?
  amount = swing.clamp(0.0, 100.0) / 100.0
  unless quintuplet
    return (step_p * amount * 0.5).round(6)
  end
  # Real Dilla technique (Charnas/Hein analysis): the beat divides into 5
  # equal parts, not the standard 4 (16ths) or 6 (triplets) — the "and"
  # lands at the 3rd of 5 divisions, a 3:2 ratio rather than 2:1. That's a
  # different rhythmic subdivision, not just a different swing percentage.
  beat_p = step_p * 4.0
  quintuplet_pos = beat_p * 3.0 / 5.0
  straight_pos = step_p * 2.0
  ((quintuplet_pos - straight_pos) * amount).round(6)
end

def dilla_velocity(base, bar_index, step_index, spread: 0.10)
  seed = (bar_index * 1_009) + (step_index * 313) + (base * 10_000).to_i
  rng  = Random.new(seed)
  gaussian = Math.sqrt(-2.0 * Math.log([rng.rand, 1e-9].max)) * Math.cos(2.0 * Math::PI * rng.rand)
  [[base * (1.0 + gaussian * spread), 0.03].max, 1.0].min.round(3)
end

GENERATED_STYLES = %i[
  functional planing chromatic_mediant polytonal negative_harmony neapolitan
  coltrane backdoor slash modal_interchange
].freeze

def dilla_progression(mode = :chromatic_minor_descent)
  track = (ENV["TRACK"] || "timeless").to_s.downcase.tr("-", "_").to_sym
  sonic = sonic_profile_for(track)
  engine_pads = progression_from_engine(sonic, mode)
  return engine_pads if engine_pads&.any?

  if GENERATED_STYLES.include?(mode.to_sym) || mode.to_sym == :generated
    root_hz = (ENV["GEN_ROOT"] || 130.81).to_f
    gen_mode = (ENV["GEN_MODE"] || "minor").to_sym
    length = (ENV["GEN_LENGTH"] || 8).to_i
    seed = ENV["GEN_SEED"]&.to_i
    style = mode.to_sym == :generated ? (ENV["GEN_STYLE"] || "functional").to_sym : mode.to_sym
    routed = route_generated_style(style, root_hz:, mode: gen_mode, length:, seed:)
    return routed if routed
    case style
    when :planing then return generate_planing_progression(root_hz:, mode: gen_mode, length:, seed:)
    when :chromatic_mediant then return generate_chromatic_mediant_progression(root_hz:, length:, seed:)
    when :polytonal then return generate_polytonal_progression(root_hz:, mode: gen_mode, length:, seed:)
    when :negative_harmony then return generate_negative_harmony_progression(root_hz:, mode: gen_mode, length:, seed:)
    when :neapolitan then return generate_neapolitan_progression(root_hz:, length:, seed:)
    else return generate_progression(root_hz:, mode: gen_mode, length:, seed:)
    end
  end
  names = CHORD_PROGRESSIONS.fetch(mode.to_sym, CHORD_PROGRESSIONS.fetch(:fourth_third_sixth_second_turn))
  names.map { |n| PAD_CHORD_LOOKUP[n] || MODAL_MINOR_CHORDS.find { |c| c[:name] == n } }.compact
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
  return chords if chords.length <= 1
  led = [chords.first]
  prev_midis = chords.first[:hz].map { |h| hz_to_midi(h) }.sort
  chords.drop(1).each do |nxt|
    targets = nxt[:hz].map { |h| hz_to_midi(h) }.sort
    # Greedy nearest-pitch-class assignment, not fixed sorted-index matching
    # — index matching (voice i always follows voice i) breaks down whenever
    # chord sizes differ, e.g. a 6-note polytonal stack following a 4-note
    # chord: it was forcing a voice toward whatever pitch happened to sit at
    # the same numeric position rather than its actual closest neighbor,
    # which is what produced transitions that sounded unrelated to the
    # chord before them.
    available_anchors = prev_midis.dup
    voiced = targets.map do |target|
      anchor = if available_anchors.empty?
                 target
               else
                 available_anchors.min_by { |a| pitch_class_distance(a, target) }
               end
      available_anchors.delete(anchor) if available_anchors.length > 1
      shift = ((anchor - target) / 12.0).round
      midi = target + shift * 12.0
      # Nearest-octave voice leading has no floor/ceiling on its own — over a
      # long progression it can drag deliberately bright voicings down into
      # the bass's own register, so the pad reads as more bass instead of an
      # audible chord sitting above it. Keep every voice in a register
      # clearly above the kick/bass fundamental.
      midi += 12.0 while midi < 48.0
      midi -= 12.0 while midi > 81.0
      midi
    end.sort
    prev_midis = voiced
    led << { name: nxt[:name], hz: voiced.map { |m| midi_to_hz(m) }.uniq.first(5) }
  end
  led
end

def pitch_class_distance(a, b)
  diff = (a - b) % 12.0
  [diff, 12.0 - diff].min
end

# Position weights derived from the empirical frequency of each 16th-note
# slot across every curated pattern in the file — not invented from
# scratch. Used to *generate* a fresh, never-exactly-repeating pattern
# each bar instead of only rotating a small fixed set: the "organic
# exploratory impromptu" feel of a drummer varying a groove live rather
# than a sequencer replaying the same loop.
KICK_POSITION_WEIGHTS = begin
  counts = Array.new(16, 0)
  (SYNCOPATED_KICK_PATTERNS + LOOSE_POCKET_KICK_PATTERNS +
   [[7, 10, 14], [3, 7, 10, 12, 14], [6, 9, 13, 15], [2, 7, 10, 14],
    [14, 3, 7, 10], [14, 3, 8, 11], [13, 2, 6, 10], [15, 3, 7, 11]]).each do |pat|
    pat.each { |step| counts[step] += 1 }
  end
  counts.freeze
end

# Real drum patterns aren't independent per-step coin flips — a hit makes
# the next step less likely (players don't usually double straight after a
# hit) and a rest makes a hit somewhat more likely (tension resolving).
# Blended with the measured position weights rather than replacing them.
KICK_MARKOV = { after_hit: 0.55, after_rest: 1.15 }.freeze

def generate_organic_kick_pattern(bar, seed_base = 5081)
  rng = Random.new(seed_base + bar * 733)
  total = KICK_POSITION_WEIGHTS.sum.to_f
  # Convention on regular bars, wild randomization on fill bars — a fixed
  # "every 8th bar" period reads as scheduled/authored (real critique: a
  # human drummer's chaos doesn't land on a metronomic grid). Probabilistic
  # instead, same ~1-in-8 average rate but the actual bars land irregularly.
  fill_bar = bar.positive? && Random.new(seed_base + bar).rand < 0.125
  density_mult = fill_bar ? 6.0 : 3.4
  min_gap = fill_bar ? 1 : 2
  prev_hit = false
  candidates = (0..15).select do |i|
    position_prob = (KICK_POSITION_WEIGHTS[i] / total) * density_mult
    markov_mult = prev_hit ? KICK_MARKOV[:after_hit] : KICK_MARKOV[:after_rest]
    hit = rng.rand < (position_prob * markov_mult).clamp(0.0, fill_bar ? 0.98 : 0.95)
    prev_hit = hit
    hit
  end
  # Pure independent-per-step probability could land two hits a single
  # 16th apart — reads as a mistake/flam, not a groove. Enforce a minimum
  # gap like a real kick pattern would have (relaxed on fill bars, where
  # tight clusters are the point).
  steps = []
  candidates.each { |i| steps << i if steps.empty? || i - steps.last >= min_gap }
  steps << 0 if steps.empty?
  steps.uniq.sort
end

def dilla_kick_pattern(bar, n_bars, feel)
  # Detroit techno/house: steady four-on-the-floor, not humanized — that
  # relentless, unswung quarter-note pulse is the actual genre signature,
  # the opposite move from every Dilla-descended feel here.
  return [0, 4, 8, 12] if feel == :techno_house
  # Replaced entirely: every feel now gets a freshly generated, per-bar
  # impromptu pattern instead of rotating a small fixed set — kept the old
  # arrays as KICK_POSITION_WEIGHTS' source data (real, curated position
  # frequencies) rather than throwing them away.
  # @render_seed varies per render (set once in render_dilla) — without it
  # every render of the same feel produced the exact same bar-for-bar kick
  # sequence, which reads as authored/looped rather than freshly generated.
  generate_organic_kick_pattern(bar, (feel.hash.abs + (@render_seed || 0)) % 10_000)
end

def dilla_section_bounds(n_bars)
  intro = [[(n_bars * 0.12).round, 4].max, (n_bars * 0.22).round].min
  outro = [[(n_bars * 0.10).round, 4].max, (n_bars * 0.18).round].min
  body = [n_bars - intro - outro, 8].max
  cycle = [[body, 16].max, 32].min
  { intro: intro, outro: outro, cycle: cycle, body_start: intro }
end

def dilla_section(bar, n_bars)
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

def dilla_section_gain(bar, n_bars, chord_phases: nil, pad_chords: nil, chord_bars: 2, phrase_bars: nil)
  sec_gain = case dilla_section(bar, n_bars)
             when :intro then 0.72
             when :breakdown then 0.58
             when :build then 0.88
             when :outro then 0.62
             else 1.0
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
  approach = rng.rand < 0.28 ? base_midi - (rng.rand < 0.5 ? 1 : 2) : base_midi
  midi_to_hz(approach + 12)
end

def generate_organic_hat_steps(bar, seed_base = 9203, n_bars: nil)
  rng = Random.new(seed_base + bar * 421)
  # Finale acceleration: in the last 2 bars, hat density ramps toward every
  # step — a real "speeding up until it's almost a solid tone" ending.
  if n_bars && bar >= n_bars - 2
    progress = 1.0 - ((n_bars - 1 - bar).to_f / 2)
    return (0..15).select { |i| i.even? || rng.rand < (0.4 + 0.5 * progress) }.uniq.sort
  end
  base = (0..15).select { |i| i.even? || rng.rand < 0.4 }
  base = base.reject { rng.rand < 0.12 }
  base << 0 if base.empty?
  base.uniq.sort
end

def dilla_hat_steps(bar, feel, n_bars: nil)
  if n_bars && bar >= (n_bars * 0.82).to_i
    progress = 1.0 - ((n_bars - 1 - bar).to_f / [n_bars * 0.18, 1].max)
    rng = Random.new(bar * 421)
    return (0..15).select { |i| i.even? || rng.rand < (0.35 + 0.55 * progress) }.uniq.sort
  end
  case feel
  when :techno_house
    # Erratic, denser than the organic generator, no minimum-spacing
    # smoothing — real acid/Detroit-house hats are chaotic on purpose.
    rng = Random.new(bar * 971 + 3)
    (0..15).select { rng.rand < 0.55 }
  when :organic
    generate_organic_hat_steps(bar, n_bars:)
  when :syncopated_slash_ninth
    (0..15).step(2).to_a + [3, 11]
  when :chromatic_planing
    bar.even? ? [0, 2, 4, 6, 8, 10, 12, 14] : [1, 3, 5, 7, 9, 11, 13, 15]
  when :loose_pocket
    steps = (0..15).step(2).to_a
    steps += [1, 5, 9, 13] if bar.odd?
    steps += [7, 15] if (bar % 4) == 3
    steps -= [8] if (bar % 8) == 5
    steps.uniq.sort
  when :timeless
    if bar % 8 == 7
      [0, 4, 8, 12]
    elsif bar % 4 == 2
      [0, 2, 4, 6, 8, 10, 12, 14, 3, 11]
    elsif bar.odd?
      [0, 1, 3, 4, 6, 8, 10, 11, 13, 14]
    else
      (0..15).step(2).to_a + [3, 7, 11]
    end
  else
    if bar % 8 == 7
      [0, 4, 8, 12]
    elsif bar.odd?
      [0, 1, 3, 4, 6, 8, 10, 11, 13, 14]
    else
      (0..15).step(2).to_a + [3, 11]
    end
  end.uniq.sort
end

def dilla_schedule(n_bars, beat_p, pad_chords, chord_bars: 4, phrase_bars: nil, drums_only: false,
                   swing: 58.0, feel: :default, timing: nil, quintuplet: false, bass_pads: nil,
                   chord_phases: nil)
  bar_p  = (beat_p * 4.0).round(6)
  step_p = (beat_p / 4.0).round(6)
  events = Hash.new { |h, k| h[k] = [] }
  # Odd-meter/hemiola nod (Aydin Esen's Turkish-modal odd meters, without a
  # full rewrite of the 16-step grid): every 16th bar loses its last 2
  # steps — a real short bar, not a fake accent. Cumulative bar starts
  # since bar durations are no longer uniform.
  drop_beat_bar = ->(b) { b.positive? && b % 16 == 15 }
  bar_starts = [0.0]
  (1..n_bars).each { |b| bar_starts << bar_starts.last + (drop_beat_bar.call(b - 1) ? bar_p * 0.875 : bar_p) }

  n_bars.times do |bar|
    base = bar_starts[bar]
    section = dilla_section(bar, n_bars)
    sec_gain = dilla_section_gain(bar, n_bars, chord_phases: chord_phases, pad_chords: pad_chords,
                                  chord_bars: chord_bars, phrase_bars: phrase_bars)
    phase = chord_phase_at(bar, pad_chords, chord_phases, chord_bars: chord_bars, phrase_bars: phrase_bars)
    pattern = dilla_kick_pattern(bar, n_bars, feel)
    pattern = [7, 14] if section == :breakdown
    pattern = [0, 10] if section == :intro && bar < 4
    pattern = pattern.select { |s| s < 14 } if drop_beat_bar.call(bar)

    cur_chord = drums_only || pad_chords.empty? ? nil : pad_chords[dilla_chord_index(bar, pad_chords, chord_bars: chord_bars, phrase_bars: phrase_bars)]
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
      events[:bass] << [base + 0.012, dilla_velocity(0.52, bar, 99, spread: 0.04) * sec_gain, bass_root, bar_p * 0.92]
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

    if kicks_enabled?
      pattern.each_with_index do |step, i|
        role = (feel == :syncopated_slash_ninth || step.nonzero?) ? :kick_sync : :kick_anchor
        t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
             dilla_timing_ms(role, bar, step, timing, beat_p) / 1000.0, 0.0].max
        ks = kick_velocity_scale
        kick_vel = dilla_velocity(step.zero? ? 0.52 : 0.44, bar, step, spread: 0.05) * sec_gain * ks
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

    unless section == :breakdown || (section == :intro && bar < 4)
      [4, 12].each_with_index do |step, si|
        t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
             dilla_timing_ms(:snare, bar, step, timing, beat_p) / 1000.0, 0.0].max
        events[:snare] << [t.round(6), dilla_velocity(si.zero? ? 0.64 : 0.56, bar, step) * sec_gain]
        # 1ms flam on the downbeat snare — reads as one fatter drum, not two
        # separate hits, a real mixing/drumming trick, not audible as a
        # distinct second hit.
        if si.zero?
          events[:ghost] << [(t - 0.001).round(6).clamp(0.0, Float::INFINITY),
                              dilla_velocity(0.22, bar, step, spread: 0.04) * sec_gain]
        end
      end
      if section == :main && bar % 4 == 2
        step = 10
        t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
             dilla_timing_ms(:ghost, bar, step, timing, beat_p) / 1000.0, 0.0].max
        events[:ghost] << [t.round(6), dilla_velocity(0.18, bar, step, spread: 0.05) * sec_gain]
      end
    end

    ghost_steps = if feel == :loose_pocket
                    ghost_base = GHOST_NOTE_PATTERNS[(bar * 2) % GHOST_NOTE_PATTERNS.length]
                    ghost_base + (bar.odd? ? [1, 9] : [5])
                  else
                    GHOST_NOTE_PATTERNS[(bar + bar / 4) % GHOST_NOTE_PATTERNS.length]
                  end
    ghost_steps.uniq.each do |step|
      t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
           dilla_timing_ms(:ghost, bar, step, timing, beat_p) / 1000.0, 0.0].max
      vel = feel == :loose_pocket ? 0.34 : 0.28
      events[:ghost] << [t.round(6), dilla_velocity(vel, bar, step, spread: 0.07) * sec_gain]
    end

    hat_steps = dilla_hat_steps(bar, feel, n_bars:)
    hat_steps = hat_steps.select.with_index { |_, i| i.even? } if section == :breakdown
    hat_steps.each_with_index do |step, i|
      role = if [3, 11].include?(step) && feel == :syncopated_slash_ninth
               :hat_up
             elsif feel == :loose_pocket && step.odd?
               :hat_up
             else
               i.even? ? :hat_down : :hat_up
             end
      t = [base + step * step_p + dilla_swing_offset(step, step_p, swing, quintuplet: quintuplet) +
           dilla_timing_ms(role, bar, step, timing, beat_p) / 1000.0, 0.0].max
      events[:hat] << [t.round(6), dilla_velocity(i.even? ? 0.48 : 0.38, bar, step, spread: 0.08) * sec_gain]
    end

    if section != :breakdown && ([1, 3].include?(bar % 4) || (feel == :loose_pocket && bar % 8 == 5))
      open_step = feel == :loose_pocket && bar % 8 == 5 ? 10 : 6
      events[:open] << [[base + open_step * step_p + dilla_swing_offset(open_step, step_p, swing, quintuplet: quintuplet) + 0.008, 0.0].max.round(6),
                        dilla_velocity(0.32, bar, open_step, spread: 0.05) * sec_gain]
    end
    if feel == :loose_pocket && section == :main && bar % 6 == 4
      events[:ghost] << [[base + 10 * step_p + dilla_swing_offset(10, step_p, swing, quintuplet: quintuplet), 0.0].max.round(6),
                         dilla_velocity(0.22, bar, 10, spread: 0.04) * sec_gain]
    end

    next if drums_only
    next if section == :intro && bar < 2

    next unless (bar % chord_bars).zero?

    chord = pad_chords[dilla_chord_index(bar, pad_chords, chord_bars: chord_bars, phrase_bars: phrase_bars)]
    pad_offset = case feel
                 when :syncopated_slash_ninth then step_p * 2 + 0.012
                 when :chromatic_planing then -step_p * 2
                 else 0.0
                 end
    pad_t = base + pad_offset + dilla_timing_ms(:pad, bar, 0, timing, beat_p) / 1000.0
    sustain = (chord_bars * bar_p * 0.97).round(4)
    pad_vel = dilla_velocity(phase == :recapitulation ? 0.96 : 0.92, bar, 0, spread: 0.03) * sec_gain
    pad_vel *= 0.88 if phase == :development
    events[:pad] << [[pad_t, 0.0].max.round(6), pad_vel, chord, sustain]
    if feel == :timeless && section == :main && bar % 4 == 1 && phase != :development
      events[:pad] << [[pad_t + step_p * 0.5, 0.0].max.round(6),
                       dilla_velocity(0.22, bar, 1, spread: 0.05) * sec_gain, chord, sustain * 0.72]
    end
    unless section == :breakdown || phase == :development
      chop_steps = phase == :recapitulation ? [[1, 5, 9, 13], [2, 6, 10, 14], [1, 9, 13], [3, 7, 11, 15]][bar % 4]
                                             : [[1, 5, 9], [2, 6, 10], [1, 9, 13], [3, 7, 11]][bar % 4]
      chop_steps.each do |chop_step|
        chop_t = [base + chop_step * step_p + dilla_swing_offset(chop_step, step_p, swing, quintuplet: quintuplet), 0.0].max
        chop_vel = phase == :recapitulation ? 0.58 : 0.52
        events[:chop] << [chop_t.round(6), dilla_velocity(chop_vel, bar, chop_step, spread: 0.04) * sec_gain, chord]
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
  filter << "[4:a]aformat=channel_layouts=stereo,lowpass=f=2800,aphaser=speed=0.12:decay=0.35,adelay=9|13,aecho=0.18:0.22:120:0.22[pads]"
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
  @render_seed = rand(1_000_000)
end

def pick_external_drum_kit!
  @current_external_kit = ensure_external_assets_lazy! && rand < 0.35 ? EXTERNAL_DRUM_KITS.sample : nil
end

def drum_sample_path(name)
  custom = File.join(CUSTOM_DRUM_DIR, name)
  return custom if File.exist?(custom)

  subdir = DRUM_SAMPLE_SUBDIR[name]
  if subdir && @current_external_kit
    kit_dir = File.join(EXTERNAL_DRUM_KIT_CACHE, "drum-samples", @current_external_kit, subdir)
    picked = Dir.glob(File.join(kit_dir, "*.wav")).sample
    return picked if picked
  end

  File.join(DRUM_DIR, name)
end

def generate_drum_kit!
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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

def fetch_assets!
  abort "curl required" unless tool_available?("curl")
  sf_dir = File.expand_path("~/.cache/dilla-soundfonts")
  FileUtils.mkdir_p(sf_dir)
  EXTERNAL_SOUNDFONTS.each do |name, url|
    dest = File.join(sf_dir, name)
    if File.exist?(dest)
      puts "have: #{name}"
      next
    end
    puts "fetching #{name}..."
    sh! "curl", "-sL", "--fail", "-o", dest, url
  end

  if Dir.exist?(EXTERNAL_DRUM_KIT_CACHE)
    puts "have: free-drum-samples"
  else
    abort "git required" unless tool_available?("git")
    puts "fetching free-drum-samples (CC0)..."
    FileUtils.mkdir_p(File.dirname(EXTERNAL_DRUM_KIT_CACHE))
    sh! "git", "clone", "--depth", "1", EXTERNAL_DRUM_KIT_REPO, EXTERNAL_DRUM_KIT_CACHE
  end
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
  pipe_floats(path, "aformat=channel_layouts=mono:sample_fmts=flt")
end

# LA beat-scene kicks (Brainfeeder/Flying Lotus lineage) are never one thin
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
  out.map { |s| (Math.tanh(s * gain * drive) / ceiling) * (0.16 * kick_velocity_scale + 0.06) }
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

def native_waveform_body(frequency, wave:, bloom: 0.2, drift: "1", detune: 0.004, phase_seed: 0.0)
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
    mod = "sin(2*PI*#{f * 1.5}*#{drift}*t)"
    "0.65*sin(2*PI*#{f}*#{drift}*t+2.2*#{mod})+0.20*sin(2*PI*#{f * 2.0}*#{drift}*t)"
  when :organ
    "0.42*sin(2*PI*#{f}*#{drift}*t)+0.28*sin(2*PI*#{f * 2.0}*#{drift}*t)+0.18*sin(2*PI*#{f * 3.0}*#{drift}*t)+0.12*sin(2*PI*#{f * 4.0}*#{drift}*t)"
  when :bowed
    "0.55*sin(2*PI*#{f}*#{drift}*t)+0.25*sin(2*PI*#{f * 2.0}*#{drift}*t)+0.12*sin(2*PI*#{f * 3.0}*#{drift}*t)"
  when :juno
    "0.50*sin(2*PI*#{f}*#{drift}*t)+0.30*sin(2*PI*#{det_up}*#{drift}*t)+0.20*sin(2*PI*#{det_dn}*#{drift}*t)+" \
    "#{bloom.round(3)}*sin(2*PI*#{f * 2.0}*#{drift}*t)"
  when :moog
    sub = (frequency * 0.5).round(4)
    "0.58*(2*mod(#{f}*#{drift}*t,1)-1)+0.22*(2*mod(#{det_up}*#{drift}*t,1)-1)+" \
    "0.14*(2*mod(#{det_dn}*#{drift}*t,1)-1)+#{bloom.round(3)}*(2*mod(#{sub}*#{drift}*t,1)-1)+" \
    "0.10*sin(2*PI*#{f}*#{drift}*t)"
  when :prophet
    det2 = (frequency * (1.0 + detune * 1.6)).round(4)
    det3 = (frequency * (1.0 - detune * 1.6)).round(4)
    "0.38*(2*mod(#{f}*#{drift}*t,1)-1)+0.24*(2*mod(#{det_up}*#{drift}*t,1)-1)+" \
    "0.24*(2*mod(#{det_dn}*#{drift}*t,1)-1)+0.14*(2*mod(#{det2}*#{drift}*t,1)-1)+" \
    "0.12*(2*mod(#{det3}*#{drift}*t,1)-1)+#{bloom.round(3)}*sin(2*PI*#{f * 2.0}*#{drift}*t)"
  else # :rhodes default
    "0.72*sin(2*PI*#{f}*#{drift}*t)+#{bloom.round(3)}*sin(2*PI*#{f * 3.0}*#{drift}*t)+" \
    "0.08*sin(2*PI*#{f * 2.0}*#{drift}*t)+0.30*sin(2*PI*#{det_up}*#{drift}*t)+0.30*sin(2*PI*#{det_dn}*#{drift}*t)"
  end
end

def native_pad_voice_expression(hz, amp, voice_i, pan, phase_seed, native_patch: nil)
  frequency = hz.round(4)
  drift = "(1+0.0014*sin(2*PI*0.065*t+#{phase_seed.round(3)}))"
  native = native_patch&.dig(:native) || @render_native_patch&.dig(:native) || { wave: :rhodes, detune: 0.004, bloom: 0.28 }
  body = native_waveform_body(frequency, wave: native[:wave] || :rhodes, bloom: native[:bloom] || 0.2,
                              drift: drift, detune: native[:detune] || 0.004, phase_seed: phase_seed)
  breathe = "(0.80+0.20*sin(2*PI*#{(0.16 + voice_i * 0.025).round(3)}*t+#{phase_seed.round(3)}))"
  env = "min(1,pow(t/0.072,1.35))*exp(-t*0.07)*#{breathe}"
  ["#{amp.round(6)}*#{(0.5 - pan * 0.5).round(4)}*#{env}*#{body}",
   "#{amp.round(6)}*#{(0.5 + pan * 0.5).round(4)}*#{env}*#{body}"]
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
      pair = native_pad_voice_expression(hz, amp, voice_i, pan, event_i * 0.55 + voice_i * 0.9)
      left_parts << pair[0]
      right_parts << pair[1]
      next unless voice_i.zero?

      sub_pair = native_pad_voice_expression(hz * 0.5, amp * 0.42, voice_i + 5, pan, event_i * 0.61)
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

# Writes a minimal single-track Standard MIDI File by hand (no midilib
# dependency — this codebase otherwise stays dependency-light) from
# pad_events shaped like render_native_pad_wav's: [time, velocity, chord, sustain].
def write_pad_smf(path, pad_events, program: PAD_GM_PROGRAM, bank: 0)
  notes = []
  pad_events.each do |(time, velocity, chord, sustain)|
    next unless chord

    chord[:hz].each do |hz|
      note = hz_to_midi(hz).round.clamp(0, 127)
      on_tick = (time * SMF_TICKS_PER_SECOND).round
      off_tick = (on_tick + (sustain * SMF_TICKS_PER_SECOND)).round
      vel = (velocity.clamp(0.0, 1.0) * 108).round.clamp(48, 127)
      notes << [on_tick, :on, note, vel]
      notes << [off_tick, :off, note, 0]
    end
  end
  notes.sort_by! { |tick, kind, _, _| [tick, kind == :off ? 0 : 1] }

  # Bank Select MSB (CC#0) before the program change — some curated
  # single-purpose soundfonts (e.g. fetched specialty fonts) scatter their
  # presets across non-zero banks instead of the standard GM bank 0 layout.
  events = [[0, [0xB0, 0x00, bank & 0x7f].pack("C*")], [0, [0xC0, program].pack("C*")]]
  last_tick = 0
  notes.each do |tick, kind, note, vel|
    delta = [tick - last_tick, 0].max
    status = kind == :on ? 0x90 : 0x80
    events << [delta, [status, note, vel].pack("C*")]
    last_tick = tick
  end
  events << [0, [0xFF, 0x2F, 0x00].pack("C*")]

  track_data = events.map { |delta, bytes| midi_vlq(delta) + bytes }.join
  track_chunk = "MTrk" + [track_data.bytesize].pack("N") + track_data
  header = "MThd" + [6].pack("N") + [0, 1, SMF_PPQN].pack("n3")
  File.binwrite(path, header + track_chunk)
  path
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
def render_pad_via_fluidsynth(path, pad_events, duration)
  ep_path = "#{path}.ep.wav"
  warm_path = "#{path}.warm.wav"
  texture_path = "#{path}.texture.wav"
  ep_voice = resolve_ep_voice
  warm_voice = resolve_warm_voice
  texture_voice = resolve_texture_voice
  ep_mix = ep_voice[:patch]&.fetch(:mix, 1.0) || 1.0
  warm_mix = warm_voice[:patch]&.fetch(:mix, 0.7) || 0.7
  layers = [[ep_path, ep_voice, ep_mix], [warm_path, warm_voice, warm_mix]]
  if texture_voice
    tex_mix = @render_texture_patch&.fetch(:mix, 0.15) || 0.15
    layers << [texture_path, texture_voice, tex_mix]
  end
  layers.each do |voice_path, voice, _w|
    midi_path = "#{voice_path}.smf.mid"
    write_pad_smf(midi_path, pad_events, program: voice[:program], bank: voice[:bank])
    fs_gain = voice[:patch]&.fetch(:fs_gain, 1.5) || 1.5
    sh! "fluidsynth", "-ni", "-g", fs_gain.to_s, "-F", voice_path, "-r", SAMPLE_RATE.to_s, voice[:sf2], midi_path
    FileUtils.rm_f(midi_path)
    if voice[:patch]&.dig(:fx) && tool_available?("ffmpeg")
      fx_tmp = "#{voice_path}.fx.wav"
      begin
        sh! "ffmpeg", "-y", "-i", voice_path, "-af", voice[:patch][:fx], "-c:a", "pcm_s16le", fx_tmp
        FileUtils.mv(fx_tmp, voice_path)
      rescue StandardError => e
        warn "patch fx skipped (#{voice[:patch][:id]}): #{e.message}"
        FileUtils.rm_f(fx_tmp)
      end
    end
  end
  # Classic analog-synth unison detune on warm layer (Juno/Prophet chorus).
  filt = "[0:a]apad=whole_dur=#{duration}[ep];" \
         "[1:a]apad=whole_dur=#{duration}[warmsrc];" \
         "[warmsrc]asplit=2[w1][w2];" \
         "[w1]asetrate=44100*1.0035,aresample=44100[wup];" \
         "[w2]asetrate=44100*0.9965,aresample=44100[wdown];" \
         "[wup][wdown]amix=inputs=2:weights=0.55 0.55:duration=first:normalize=0[wdetuned];" \
         "[ep][wdetuned]amix=inputs=2:weights=#{ep_mix} #{warm_mix}:duration=first:normalize=0[blend]"
  inputs = ["-i", ep_path, "-i", warm_path]
  if texture_voice && File.exist?(texture_path)
    filt += ";[2:a]apad=whole_dur=#{duration}[tex];[blend][tex]amix=inputs=2:weights=1.0 #{layers.last[2]}:duration=first:normalize=0[blend2]"
    map_label = "[blend2]"
    inputs << "-i" << texture_path
  else
    map_label = "[blend]"
  end
  sh! "ffmpeg", "-y", *inputs, "-filter_complex", filt, "-map", map_label, "-c:a", "pcm_s16le", path
  FileUtils.rm_f(ep_path)
  FileUtils.rm_f(warm_path)
  FileUtils.rm_f(texture_path)
  # GeneralUser GS's EP patch renders far quieter than the old additive-synth
  # pad engine did (measured ~-35dB RMS vs the tones bus's ~-27dB at equal
  # amix weight, which buried the chords entirely) — a fixed -g wasn't enough
  # across different voicings/velocities, so measure and normalize toward a
  # fixed target instead of guessing a static boost.
  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  boost_db = (PAD_TARGET_RMS_DB - measured_rms).clamp(0.0, 24.0)
  sh! "ffmpeg", "-y", "-i", path, "-af",
      "equalizer=f=360:t=o:w=1.1:g=2.2,equalizer=f=2100:t=h:w=1500:g=1.6," \
      "volume=#{boost_db.round(2)}dB,alimiter=limit=0.95:level_out=0.96",
      "-c:a", "pcm_s16le", "#{path}.pad.wav"
  FileUtils.mv("#{path}.pad.wav", path)
  path
end

# 81 Sawtooth (original), 87 Lead 8 "bass+lead" (GM's own name traces to the
# classic Prophet-5 "BigLead" patch — literally the historical big-lead
# archetype), 84 Lead 5 Charang (aggressive/bright, cuts through), 86 Lead 7
# Fifths (built-in parallel fifths give arps instant harmonic width free).
LEAD_GM_PROGRAMS = [81, 87, 84, 86].freeze
LEAD_TARGET_RMS_DB = -26.0

def invert_motif(motif)
  top = motif.max
  motif.map { |d| top - d }
end

# Leitmotif seeded from the progression's own opening chord — stable for
# a given piece, so the lead states one real idea and develops it
# (inversion/retrograde/augmentation) instead of generating a fresh,
# unrelated arp pattern at every chord change.
def leitmotif_for(pad_events)
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
  lead_events_creative(pad_events, cfg, duration: duration, n_bars: n_bars)
end

def lead_post_fx_chain(patch, duration, boost_db)
  base = "volume=#{boost_db.round(2)}dB"
  patch_fx = patch&.dig(:fx)
  default_fx = "aecho=0.6:0.4:180|340:0.35|0.22,lowpass=f=3600:width_type=q:width=0.8,aphaser=speed=0.12:decay=0.6"
  [base, patch_fx || default_fx, "apad=whole_dur=#{duration}", "alimiter=limit=0.95:level_out=0.96"].join(",")
end

def render_lead_via_fluidsynth(path, lead_events, duration)
  return nil if lead_events.empty? || !fluidsynth_pad_available?
  midi_path = "#{path}.smf.mid"
  lead_voice = resolve_lead_voice
  write_pad_smf(midi_path, lead_events, program: lead_voice[:program], bank: lead_voice[:bank])
  sh! "fluidsynth", "-ni", "-g", "1.3", "-F", path, "-r", SAMPLE_RATE.to_s, lead_voice[:sf2], midi_path
  FileUtils.rm_f(midi_path)
  measured_rms = band_rms(path, highpass: 20, lowpass: 20_000)
  boost_db = (LEAD_TARGET_RMS_DB - measured_rms).clamp(0.0, 24.0)
  patch = lead_voice[:patch] || @render_lead_patch
  sh! "ffmpeg", "-y", "-i", path, "-af", lead_post_fx_chain(patch, duration, boost_db),
      "-c:a", "pcm_s16le", "#{path}.lead.wav"
  FileUtils.mv("#{path}.lead.wav", path)
  path
end

def render_harmonic_wav(path, pad_events, chop_events, bass_events, duration, melody_events: [], cfg: nil)
  cfg ||= dilla_resolve_config
  pick_synth_patches!(cfg) unless @render_ep_patch
  tones_path = "#{path}.tones.wav"
  pads_path = "#{path}.pads.wav"
  lead_path = "#{path}.lead.wav"
  if fluidsynth_pad_available?
    render_pad_via_fluidsynth(pads_path, pad_events, duration)
  else
    render_native_pad_wav(pads_path, pad_events, duration)
  end
  n_bars_est = (duration / ((60.0 / cfg[:bpm]) * 4.0)).ceil
  lead_rendered = render_lead_via_fluidsynth(lead_path, lead_events_from_pads(pad_events, duration: duration, n_bars: n_bars_est), duration)
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
      total = [((hit[3] || BASS_SUSTAIN_SEC) * SAMPLE_RATE).round, 1].max
      event_frame = (t * SAMPLE_RATE).round
      window = overlap_window(event_frame, total, chunk_start, chunk_frames)
      next unless window
      local_start, source_offset, count = window
      count.times do |i|
        tt = (source_offset + i).to_f / SAMPLE_RATE
        lfo = 0.03 * Math.sin(2 * Math::PI * 0.12 * tt)
        # Was 0.42 — ~3-4x melody(0.11)/chop(0.13)'s coefficient, so bass
        # transients dominated the shared tones+pads limiter downstream and
        # ducked the chords every time the bass hit.
        sample = v * 0.30 * Math.exp(-tt * BASS_DECAY_RATE) *
                 Math.sin(2 * Math::PI * root * (1.0 + lfo) * tt)
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
  if lead_rendered
    sh! "ffmpeg", "-y", "-i", pads_path, "-i", tones_path, "-i", lead_path,
        "-filter_complex", "[0:a]volume=1.18[padsl];" \
                           "[1:a]volume=0.72[tonesl];" \
                           "[2:a]volume=0.75[leadl];" \
                           "[padsl][tonesl][leadl]amix=inputs=3:weights=1.45 0.55 0.22:duration=longest:normalize=0," \
                           "aresample=#{SAMPLE_RATE},alimiter=limit=0.96:level_out=0.98[harmonic]",
        "-map", "[harmonic]", "-t", duration.to_s, "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", path
    FileUtils.rm_f(lead_path)
  else
    sh! "ffmpeg", "-y", "-i", pads_path, "-i", tones_path,
        "-filter_complex", "[0:a]volume=1.18[padsl];" \
                           "[1:a]volume=0.72[tonesl];" \
                           "[padsl][tonesl]amix=inputs=2:weights=1.45 0.55:duration=longest:normalize=0," \
                           "aresample=#{SAMPLE_RATE},alimiter=limit=0.96:level_out=0.98[harmonic]",
        "-map", "[harmonic]", "-t", duration.to_s, "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", path
  end
  FileUtils.rm_f(pads_path)
  FileUtils.rm_f(tones_path)
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
      pan = hit[3] || 0.0
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
SAMPLE_NATURAL_HZ = { bass_43: 49.0 }.freeze

def render_sample_bus_wav(path, events, duration, kit, mapping)
  write_stereo_chunks(path, duration) do |chunk_start, chunk_frames, left, right|
    mapping.each do |event_key, default_key|
      events.fetch(event_key, []).each do |hit|
        time, velocity = hit[0], hit[1]
        target_hz = hit[2].is_a?(Numeric) ? hit[2] : nil
        sample_key = hit[2].is_a?(Symbol) ? hit[2] : default_key
        pan = hit[3] || 0.0
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

PROGRESSION_LOG_PATH = File.join(OUTPUT_DIR, ".dilla_progressions_log.txt")

# Every chord walked during a render, appended so nothing explored is lost —
# generated progressions especially never repeat, so this is the only
# record of what actually played if it's worth turning into a real song.
def log_progression!(track, bpm, pads)
  return if pads.empty?
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
SELF_SAMPLE_CACHE = File.join(ROOT, ".dilla_self_sample.wav")

# "Collapse over accretion": before this render's predecessor is deleted,
# grab a short slice of it and cache it — the next render can layer that
# slice back in as texture, a real feedback loop across renders rather
# than each one starting from nothing.
def cache_self_sample!(destination)
  return unless File.exist?(destination) && tool_available?("ffprobe")
  # Not media_metadata: it calls abort() on failure, which would kill the
  # whole render for what's meant to be a best-effort optional step.
  output, _err, status = capture("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of",
                                  "default=noprint_wrappers=1:nokey=1", destination)
  return unless status.success?
  duration = output.to_f
  return if duration < 2.0
  offset = (rand * [duration - 1.5, 0.1].max).round(2)
  sh! "ffmpeg", "-y", "-i", destination, "-ss", offset.to_s, "-t", "1.2",
      "-ac", "2", "-ar", SAMPLE_RATE.to_s, "-c:a", "pcm_s16le", SELF_SAMPLE_CACHE
rescue StandardError
  FileUtils.rm_f(SELF_SAMPLE_CACHE)
end

def render_dilla(destination = File.join(OUTPUT_DIR, "beat.mp3"), bars_count = nil, keep_stems: false)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
  pick_render_seed!
  ensure_drum_kit!
  FileUtils.mkdir_p(File.dirname(destination))
  cache_self_sample!(destination)
  FileUtils.rm_f(destination)
  cfg      = dilla_resolve_config
  pick_synth_patches!(cfg)
  n_bars   = bars_count || bars
  beat_p   = 60.0 / cfg[:bpm]
  duration = (beat_p * 4.0 * n_bars).round(3)
  needed_chords = (n_bars.to_f / cfg[:chord_bars]).ceil + 1
  if GENERATED_STYLES.include?(cfg[:progression].to_sym) || cfg[:progression].to_sym == :generated
    ENV["GEN_LENGTH"] = needed_chords.to_s
  end
  pads = dilla_progression(cfg[:progression])
  # A fugue subject: stated (the hook), developed (explored away from it),
  # then recapitulated (the hook returns). Plain looping felt static; pure
  # endless generative wandering never resolved into anything recognizable.
  # This is neither — the curated/generated hook repeats a couple of times
  # to establish itself, a generative development section explores outward
  # from its last chord, then the hook returns to close it.
  fugue_phases = []
  pads, fugue_phases = arrange_fugue_progression(pads, needed_chords, cfg) unless pads.empty?
  pads = apply_pedal_point(pads, probability: 0.35, seed: cfg[:track].hash.abs)
  pads, fugue_phases = enrich_progression(pads, cfg, phases: fugue_phases)
  pads = voice_lead_chords(pads)
  @chord_phases = fugue_phases
  @progression_chords = pads
  @render_chord_bars = cfg[:chord_bars]
  @render_phrase_bars = cfg[:phrase_bars]
  log_progression_phases!(cfg[:track], cfg[:bpm], pads, fugue_phases)
  # Bitonal bass on roughly a third of renders: a genuinely independent
  # generated progression drives the bass root, disagreeing with the pad
  # chords on purpose rather than always doubling their root.
  bass_pads = nil
  if Random.new(cfg[:track].to_s.hash.abs).rand < 0.33
    bass_pads = voice_lead_chords(generate_progression(root_hz: pads.first[:hz].min * 0.5, mode: :minor,
                                                         length: pads.length))
  end
  events   = dilla_schedule(
    n_bars, beat_p, pads,
    chord_bars: cfg[:chord_bars], phrase_bars: cfg[:phrase_bars],
    swing: cfg[:swing], feel: cfg[:feel], timing: cfg[:timing], quintuplet: cfg[:quintuplet],
    bass_pads:, chord_phases: fugue_phases
  )

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

  drum_tmp     = File.join(ROOT, ".dilla_drums.wav")
  harmonic_tmp = File.join(ROOT, ".dilla_harmonic.wav")
  render_sample_bus_wav(drum_tmp, events, duration, kit, drum_bus_mapping)

  chop_gate = gate_expr(events[:chop], hold: 0.32, scale: 0.95)
  pad_gate  = pad_gate_expr(events[:pad])
  stems = dilla_stem_paths
  stem_tempo = (cfg[:bpm] / 90.0).round(4)
  pan_hz = (cfg[:bpm] / 15.0).round(3)
  use_stem_harmony = !stems.empty?
  unless use_stem_harmony
    render_harmonic_wav(harmonic_tmp, events[:pad], events[:chop], events[:bass], duration,
                        melody_events: events[:melody], cfg: cfg)
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
  if File.exist?(SELF_SAMPLE_CACHE)
    command += ["-stream_loop", "-1", "-i", SELF_SAMPLE_CACHE]
    self_sample_idx = idx
    idx += 1
  end
  ir_path = synth_impulse_response!(CONVOLUTION_ROOMS.keys.sample)
  command += ["-i", ir_path]
  ir_input_idx = idx
  idx += 1
  vinyl_amp = sonic_vinyl_level(cfg[:sonic])
  command += ["-f", "lavfi", "-i", "anoisesrc=color=pink:r=#{SAMPLE_RATE}:amplitude=#{vinyl_amp}:d=#{duration}"]
  turntable_rumble = sonitex_enabled? && TURNTABLE_RUMBLE_VARIANTS.include?(analog_resolve_variant(track: cfg[:track].to_s))
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
  mix_weights = ["0.72"]
  intro_bars = cfg.fetch(:intro_bars, 4)
  harm_fade_start = (beat_p * 4.0 * [intro_bars, 2].min).round(2)
  harm_fade_dur = (beat_p * 4.0 * 1.25).round(2)
  unless use_stem_harmony
    filt << build_harm_bus_filter(1, duration, cfg, cfg[:sonic], harm_fade_start, harm_fade_dur, beat_p, n_bars)
    if cfg[:sidechain]
      filt.concat(flylo_sidechain_filters)
      mix_labels = ["[sc_mix]"]
      mix_weights = ["1.0"]
    else
      mix_labels << "[harm]"
      mix_weights << "2.35"
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

  filt << "[#{idx}:a]highpass=f=120,lowpass=f=6000,volume=0.07[vinyl]"
  mix_labels << "[vinyl]"
  mix_weights << "0.6"
  if turntable_rumble
    filt << "[#{idx + 1}:a]lowpass=f=40,highpass=f=22,volume=0.05[rumble]"
    mix_labels << "[rumble]"
    mix_weights << "0.35"
  end
  if self_sample_idx
    # The previous render, looped and buried quiet underneath this one — a
    # genuine feedback loop across renders, not a fresh start every time.
    filt << "[#{self_sample_idx}:a]atrim=0:#{duration},asetpts=PTS-STARTPTS," \
             "lowpass=f=2200,areverse,volume=0.1[selfsample]"
    mix_labels << "[selfsample]"
    mix_weights << "1.0"
  end
  filt << "#{mix_labels.join}amix=inputs=#{mix_labels.length}:weights=#{mix_weights.join(' ')}:duration=first:normalize=0[mix]"
  filt.concat(master_bus_filters("mix", track: cfg[:track].to_s, duration:, ir_input_idx:, cfg:))

  command += ["-filter_complex", filt.join(";"), "-map", "[out]", "-t", duration.to_s, *codec_for(destination), destination]
  File.write("/tmp/last_filter_graph.txt", filt.join(";\n")) if ENV["DEBUG_FILTER_DUMP"]
  sh!(*command)
  if ENV["STEM_EXPORT"] == "1"
    stem_dir = File.join(File.dirname(destination), "#{File.basename(destination, '.*')}_stems")
    FileUtils.mkdir_p(stem_dir)
    FileUtils.cp(drum_tmp, File.join(stem_dir, "drums.wav"))
    FileUtils.cp(harmonic_tmp, File.join(stem_dir, "harmonic.wav")) if !use_stem_harmony && File.exist?(harmonic_tmp)
    FileUtils.cp(destination, File.join(stem_dir, "master#{File.extname(destination)}")) if File.exist?(destination)
    puts "stems: #{stem_dir}"
  end
  unless keep_stems
    FileUtils.rm_f(drum_tmp)
    FileUtils.rm_f(harmonic_tmp) unless use_stem_harmony
  end
  stem_note = use_stem_harmony ? stems.keys.join("+") : "synth-harmony+melody"
  mix_note  = sonitex_label
  patch_note = [@render_ep_patch&.dig(:id), @render_warm_patch&.dig(:id), @render_lead_patch&.dig(:id),
                @render_arp_style].compact.join("/")
  kick_note = kicks_enabled? ? "kicks" : "no-kicks"
  puts "wrote #{destination} (#{cfg[:bpm].to_i} BPM, #{n_bars} bars, #{cfg[:track]}, #{kick_note}, #{mix_note}, #{stem_note}, patches=#{patch_note})"
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
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
# HELP
# =============================================================================

def help
  puts <<~HELP
    Dilla Lab — unified audio engine (#{ROOT})

    SYNTHESIS
      loose_pocket [out.wav|mp3]         Dirty Madlib drums — Delicious pocket + VLC FX (default on)
      loose_pocket beats [dir]           Batch beat_01..14 wav+mp3 → renders/beats/
      DELICIOUS=1 (default)        0.72x pocket BPM | VLC=1 (default) all audio effects
      dilla [out.mp3]              J Dilla beat — TRACK= preset (default chromatic_minor_descent)
      hiphop [out.mp3]             Slum Village engine (default TRACK=syncopated_slash_ninth)
      slum [dir]                   Batch session_01..14 → renders/ (Sonitex on)
      industrial [out.mp3]         Industrial techno (default renders/foundry_pulse.mp3)
      techno [out.mp3]             Hard distorted techno (#{TECHNO_BPM} BPM)
      analog [out.mp3]             Full analog pad restoration renderer
      analog_liveset [out] [min]   Long-form analog render
      render [out.mp3]             Core pad + drum synthesis
      electronium [out.mid]        Raymond Scott × Dilla MIDI (requires midilib)
      midi [out.mid]               Alias for electronium

    VOCAL MIXES (Sirkel Sag × Voicemails)
      mix | v11                    Latest mix recipe (default v11)
      v7 | v8 | v9 | v10           Earlier mix generations

    SAMPLE PIPELINE
      prepare [path]               Drum kit + FFmpeg stem rack (neosoul.mp3 default)
      sample                       source → demucs → clean harmonic
      source [url|path] [out]      Capture audio
      separate [path]              Demucs stem separation
      demux <url|path> [deep]      6-stem demucs + optional EQ sub-bands
      clean <in> [out]             Denoise + loudnorm

    STEM RACK (stems/manifest.json)
      stems                        Register default rack from stems/
      stems add <name> <dir> [bpm] Add a stem set to manifest
      stems scan [root] [manifest] Legacy directory scan → manifest

    LIVESET
      liveset [set] [minutes]      Long-form WAV from stem rack (LIVESET_MIN=#{LIVESET_MIN})

    ANALYSIS & GRADE
      scan | ears | verify | study | grade | grade_list | chords

    SONITEX
      sonitex_list                   List STX-1260 subset presets

    EXTERNAL ASSETS (opt-in only — engine is pure-Ruby/ffmpeg by default)
      fetch-assets                   Cache CC0 drum WAVs + 2 extra soundfonts
      use-external-kit <name>        Install a fetched kit into samples/drums/custom/
                                      (01-hard-trap | 02-bounce | 03-soulful-vintage)
    ENV: BPM BARS TRACK PROGRESSION SWING KICKS SONITEX SONITEX_PRESET BEAT LIVESET_MIN
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
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
    [4:a]aformat=channel_layouts=stereo,lowpass=f=#{ANALOG_CFG[:lowpass_hz]},aphaser=speed=0.1:decay=0.35,adelay=#{ANALOG_CFG[:chorus_delay_l_ms]}|#{ANALOG_CFG[:chorus_delay_r_ms]},aecho=0.18:0.22:120:0.22[pad];
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

# Pure drums: MPC one-shots + Madlib pockets + Dilla microtiming + SP-1200 dirt.
def render_madlib_drums(destination = File.join(ROOT, "renders", "beats", "beat.wav"), bars_count = nil)
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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

def demux_fetch_audio(src)
  return File.expand_path(src) unless src.match?(%r{\Ahttps?://})
  FileUtils.mkdir_p(DEMUX_DIR)
  raw = File.join(DEMUX_DIR, "yt_#{Time.now.strftime("%Y%m%d_%H%M%S")}.wav")
  abort "yt-dlp required" unless tool_available?("yt-dlp")
  sh! "yt-dlp", "-x", "--audio-format", "wav", "-o", raw, src
  raw
end

def demux_six(src)
  audio = demux_fetch_audio(src)
  out = File.join(DEMUX_DIR, "demux")
  FileUtils.mkdir_p(out)
  abort "demucs required" unless tool_available?("demucs")
  sh! "demucs", "-n", DEMUX_MODEL, "-o", out, audio
  stem_dir = File.join(out, DEMUX_MODEL, File.basename(audio, ".*"))
  puts "stems -> #{stem_dir}"
  if Dir.exist?(stem_dir) && !stems_scan_set(stem_dir).empty?
    name = File.basename(audio, ".*").gsub(/[^A-Za-z0-9_-]/, "_")[0, 32]
    stems_register(name, stem_dir, source: src)
  end
  stem_dir
end

def demux_slice_band(src, dest, label, eq:)
  mix_render "band: #{label}", dest, inputs: ["-i", src], map: "[out]", filter: "[0:a]#{eq}[out]"
end

def demux_deep(src)
  stem_dir = demux_six(src)
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
  abort "ffmpeg required" unless tool_available?("ffmpeg")
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
# ELECTRONIUM MIDI (electronium.rb) — lazy-loaded (requires midilib)
# =============================================================================

ELECTRONIUM_SOURCE = <<~'RUBY'
  module DillaElectronium
    PPQN = 480
    CHORDS = {
      fm9: [53, 56, 60, 63, 67], dbmaj9: [49, 53, 56, 60, 63], eb9: [51, 55, 58, 63, 65],
      bbm9: [46, 49, 53, 56, 60], cm7b5: [48, 51, 54, 58], c7alt: [48, 52, 58, 61, 63]
    }.freeze
    PROGRESSION = %i[fm9 dbmaj9 eb9 bbm9 cm7b5 fm9 c7alt fm9].freeze
    DRUMS = { kick: 36, snare: 38, closed_hat: 42, open_hat: 46 }.freeze
    F_MINOR = [65, 67, 68, 70, 72, 73, 75].freeze

    module Groove
      module_function
      def offset_ticks(type)
        case type
        when :kick then rand(-5..1)
        when :snare then rand(2..9)
        when :hat then rand(-3..4)
        when :bass then rand(-4..5)
        else rand(-5..5)
        end
      end
      def beat_to_ticks(beat, type = :melody)
        ((beat * PPQN) + offset_ticks(type)).round.clamp(0, 1 << 30)
      end
    end

    class TrackBuilder
      include MIDI
      def initialize(sequence, name, channel)
        @sequence = sequence
        @track = Track.new(sequence)
        @track.name = name
        @sequence.tracks << @track
        @channel = channel
      end
      def note(note, start_beat, duration_beats, velocity, feel: :melody)
        return if duration_beats <= 0
        start = Groove.beat_to_ticks(start_beat, feel)
        stop = [start + (duration_beats * PPQN).round, start + 1].max
        @track.events << NoteOn.new(@channel, note, velocity.clamp(1, 127), 0, start)
        @track.events << NoteOff.new(@channel, note, 0, 0, stop)
      end
      def finish
        @track.events.sort_by! { |e| [e.time_from_start, e.is_a?(NoteOff) ? 0 : 1] }
        @track.recalc_times
      end
    end

    class Composer
      include MIDI
      def initialize(bpm:, bars:)
        @bpm = bpm
        @bars = bars
        @sequence = Sequence.new
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
      def add_tempo_track
        track = Track.new(@sequence)
        @sequence.tracks << track
        track.events << Tempo.new(Tempo.bpm_to_mpq(@bpm))
        track.events << MetaEvent.new(META_SEQ_NAME, "Dilla Electronium")
        track.events << MetaEvent.new(META_TIME_SIG, [4, 2, 24, 8].pack("cccc"))
      end
      def add_drums
        drums = TrackBuilder.new(@sequence, "drums", 9)
        @bars.times do |bar|
          base = bar * 4.0
          [0.0, 1.75, 2.5, 3.5].each { |beat| drums.note(DRUMS[:kick], base + beat, 0.18, 105, feel: :kick) }
          [1.0, 3.0].each { |beat| drums.note(DRUMS[:snare], base + beat, 0.12, 92, feel: :snare) }
          drums.note(DRUMS[:snare], base + 2.75, 0.08, 42, feel: :snare) if bar.odd?
          8.times do |step|
            drums.note(DRUMS[:closed_hat], base + step * 0.5 + (step.odd? ? 0.055 : 0.0), 0.08, step.odd? ? 48 : 68, feel: :hat)
          end
          drums.note(DRUMS[:open_hat], base + 3.5, 0.18, 58, feel: :hat) if (bar % 4).zero?
        end
        drums.finish
      end
      def add_bass
        bass = TrackBuilder.new(@sequence, "bass", 0)
        chord_cycle.each_with_index do |chord_name, index|
          root = CHORDS.fetch(chord_name).first - 12
          start = index * 2.0
          bass.note(root, start, 0.62, 98, feel: :bass)
          bass.note(root + 12, start + 0.75, 0.25, 72, feel: :bass)
          bass.note(root, start + 1.5, 0.38, 86, feel: :bass)
        end
        bass.finish
      end
      def add_chords
        chords = TrackBuilder.new(@sequence, "electric-piano", 1)
        chord_cycle.each_with_index do |chord_name, index|
          CHORDS.fetch(chord_name).each_with_index do |note, voice|
            chords.note(note + 12, index * 2.0, 1.82, 48 + voice * 4, feel: :melody)
          end
        end
        chords.finish
      end
      def add_melody
        lead = TrackBuilder.new(@sequence, "lead-chops", 2)
        note_index = 2
        direction = 1
        (@bars * 4).times do |step|
          if rand < 0.78
            note = F_MINOR[note_index] + (rand < 0.25 ? 12 : 0)
            lead.note(note, step * 1.0, [0.25, 0.5, 0.75].sample, rand(62..88), feel: :melody)
          end
          note_index += direction * (rand < 0.2 ? 2 : 1)
          if note_index >= F_MINOR.length - 1
            note_index = F_MINOR.length - 2
            direction = -1
          elsif note_index <= 0
            note_index = 1
            direction = 1
          end
          direction *= -1 if rand < 0.18
        end
        lead.finish
      end
      def chord_cycle
        repeats = ((@bars * 4.0) / (PROGRESSION.length * 2.0)).ceil
        PROGRESSION.cycle.take(PROGRESSION.length * repeats)
      end
    end
  end
RUBY

def electronium_ensure_loaded!
  return if defined?(DillaElectronium::Composer)
  begin
    require "midilib"
    require "midilib/sequence"
    require "midilib/track"
    require "midilib/consts"
  rescue LoadError
    abort "midilib required — gem install midilib"
  end
  eval(ELECTRONIUM_SOURCE, TOPLEVEL_BINDING, __FILE__, __LINE__)
end

def electronium_generate(destination = File.join(OUTPUT_DIR, "electronium.mid"))
  electronium_ensure_loaded!
  FileUtils.rm_f(destination)
  path = DillaElectronium::Composer.new(bpm: bpm.to_i, bars: bars).write(destination)
  puts "wrote #{path}"
end

cmd = ARGV.shift
case cmd
when "capabilities" then puts Master::Reach::AnalogCapabilities.report(:dilla)
when "quality" then dilla_quality(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3"), ARGV.shift)
when nil, "help" then help
when "scan" then scan
when "sweep" then sweep
when "council" then council
when "debug" then debug
when "sample" then sample
when "source" then source(ARGV.shift, ARGV.shift)
when "livestream" then livestream(ARGV.shift, ARGV.shift)
when "separate" then separate(ARGV.shift)
when "render" then render(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3"))
when "verify" then verify(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3"))
when "chords" then chords
when "clean" then clean(ARGV.shift, ARGV.shift || File.join(OUTPUT_DIR, "clean.wav"))
when "stems" then stems(*ARGV)
when "study" then study(ARGV.shift, ARGV.shift)
when "rhythm" then rhythm(ARGV.shift)
when "melody" then melody(ARGV.shift)
when "harmony" then harmony(ARGV.shift)
when "semantics" then semantics(ARGV.shift)
when "ears"       then ears(ARGV.shift || File.join(OUTPUT_DIR, "full_track.mp3"))
when "play"       then play(ARGV.shift, (ARGV.shift || 8).to_i)
when "live"       then live((ARGV.shift || 32).to_i)
when "stream"     then stream((ARGV.shift || STREAM_BARS_COUNT).to_i)
when "live_now"    then live_now
when "harmony_now" then harmony_now
when "regenerate"  then regenerate((ARGV.shift || 16).to_i)
when "bass"       then bass((ARGV.shift || 55.0).to_f)
when "grade"      then grade(ARGV.shift, ARGV.shift, ARGV.shift)
when "fetch-assets" then fetch_assets!
when "use-external-kit" then use_external_kit!(ARGV.shift || abort("usage: use-external-kit <01-hard-trap|02-bounce|03-soulful-vintage>"))
when "grade_list" then grade_list
when "sonitex_list" then sonitex_list
when "analog_list"  then analog_list
when "prepare"         then prepare(ARGV.shift)
when "loose_pocket"
  out = ARGV.shift
  if out.nil? || out == "beats"
    render_madlib_album(out == "beats" ? (ARGV.shift || File.join(ROOT, "renders", "beats")) : File.join(ROOT, "renders", "beats"))
  else
    render_madlib_drums(out)
  end
when "dilla"
  dest = ARGV.shift || File.join(OUTPUT_DIR, "beat.mp3")
  n_bars = ARGV[0]&.match?(/\A\d+\z/) ? ARGV.shift.to_i : nil
  render_dilla(dest, n_bars)
when "hiphop"          then render_hiphop(ARGV.shift || File.join(OUTPUT_DIR, "hiphop.mp3"))
when "slum"            then render_slum_album(ARGV.shift || File.join(ROOT, "renders"))
when "industrial"      then render_industrial(ARGV.shift || File.join(ROOT, "renders", "foundry_pulse.mp3"))
when "techno"          then render_techno(ARGV.shift || File.join(OUTPUT_DIR, "techno_hate.mp3"))
when "analog"          then render_analog(ARGV.shift || File.join(OUTPUT_DIR, "analog_full.mp3"))
when "analog_liveset"  then analog_liveset(ARGV.shift || File.join(OUTPUT_DIR, "analog_liveset.mp3"), (ARGV.shift || 12).to_f)
when "electronium", "midi" then electronium_generate(ARGV.shift || File.join(OUTPUT_DIR, "electronium.mid"))
when "mix"  then run_mix(ARGV.shift || "v11")
when "v7"   then run_mix("v7")
when "v8"   then run_mix("v8")
when "v9"   then run_mix("v9")
when "v10"  then run_mix("v10")
when "v11"  then run_mix("v11")
when "demux"
  src = ARGV.shift or abort "usage: ruby dilla.rb demux <url-or-path> [deep]"
  ARGV[0] == "deep" ? demux_deep(src) : demux_six(src)
when "liveset"
  set = ARGV.shift || stems_load_manifest["active"] || "default"
  mins = (ARGV.shift || LIVESET_MIN).to_i
  render_liveset(set, minutes: mins)
else
  help
end
