#!/usr/bin/env ruby
# frozen_string_literal: true

# Stable MASTER entrypoint for the Dilla Lab (chat + RAILS product).
# Keeps generated audio outside source.
#
# Style taxonomy (flattened):
#   Profiles (mix DNA):  dilla | comfort | warp
#   Track shortcuts:     flylo | baroque | bach | neo-soul | jazz
#   Aliases:             punch/beat/camel → dilla
#                        sofa/smooth → comfort
#                        neo_soul → neo-soul
#
# Profiles set RENDER_MODE / comfort flags. Track shortcuts only pin TRACK
# (under the dilla profile unless comfort/warp was also requested via ENV).
require "optparse"
require "fileutils"
require "rbconfig"

module DillaEntrypoint
  ROOT = File.expand_path("dilla", __dir__)

  # --- Taxonomy -------------------------------------------------------------

  # Canonical mix profiles. Everything else is an alias or a track shortcut.
  PROFILES = {
    "dilla" => :dilla,
    "punch" => :dilla,
    "beat" => :dilla,
    "camel" => :dilla,
    "comfort" => :comfort,
    "sofa" => :comfort,
    "smooth" => :comfort,
    "warp" => :warp,
  }.freeze

  # Product --style names that only select a progression/track.
  TRACK_SHORTCUTS = {
    "flylo" => "chromatic_mediant_drift",
    "baroque" => "baroque",
    "bach" => "baroque",
    "neo-soul" => "neo_soul",
    "neo_soul" => "neo_soul",
    "jazz" => "aydin_jazz_turn",
  }.freeze

  # Default track when a profile is used without a track shortcut.
  PROFILE_DEFAULT_TRACK = {
    dilla: "get_dis_money",
    comfort: "get_dis_money",
    warp: "chromatic_mediant_drift",
  }.freeze

  # Per-track light master flags (sonitex / analog / sidechain).
  SETTINGS_FOR_TRACK = {
    "chromatic_mediant_drift" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast", "sidechain" => "1" },
    "baroque" => { "sonitex" => "classic", "analog-chain" => "broadcast" },
    "neo_soul" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast" },
    "get_dis_money" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast", "sidechain" => "1" },
    "timeless" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast" },
    "aydin_jazz_turn" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast" },
  }.freeze
  DEFAULT_SETTINGS = { "sonitex" => "donuts_soul", "analog-chain" => "broadcast" }.freeze

  # Accepted --style tokens (profiles + aliases + track shortcuts).
  STYLES = (PROFILES.keys + TRACK_SHORTCUTS.keys).uniq.freeze

  # --- Shared / profile ENV (merged; single source, no kit/comfort twin) ----

  # Always-on engine wiring for product one-shots.
  SHARED_CORE = {
    "STREAM_CONTINUOUS" => "0",
    "SPEAK" => "0",
    "COMPOSITION" => "1",
    "GROOVE_ENGINE" => "1",
    "POCKET_DNA" => "1",
    "PHRASE_DRIFT" => "1",
    "ARRANGEMENT_VARIATION" => "1",
    "MARKOV_DRUMS" => "1",
    "FLAM" => "1",
    "FM_NATIVE" => "1",
    "FM_DRUMS" => "1",
    "SWING_JITTER" => "1",
    "KICK_DOUBLE" => "1",
    "KICK_DROP" => "1",
    "SNARE_PREHIT_GHOST" => "1",
    "POCKET_KICK_SILENCE" => "1",
    "POCKET_RUSH" => "1",
    "MASTER_HEURISTICS" => "1",
    "STREAM_NORMALIZE" => "1",
    "SONITEX" => "donuts_soul",
    "SONITEX_PRESET" => "donuts_soul",
    "ANALOG_CHAIN" => "broadcast",
    "PAD_VOICE" => "stack_soul",
    "PAD_ARP_MODE" => "held",
    "KICKS" => "1",
    "POCKET_KICKS" => "1",
    "BACKBEAT_CLAP" => "1",
    "RAP_VOCAL" => "jonas_v",
    "RAP_VOCAL_STYLE" => "rap",
    "RAP_VOCAL_SIDECHAIN" => "1",
  }.freeze

  # Kit-forward punch (matches engine DILLA_STYLE_DEFAULTS intent).
  PROFILE_ENV = {
    dilla: SHARED_CORE.merge(
      "RENDER_MODE" => "dilla",
      "STREAM_COMFORT" => "0",
      "DILLA_COMFORT" => "0",
      "PAD_TEXTURE" => "1",
      "PAD_LAYERS" => "1",
      "LEAD_VOICE" => "soul_prophet",
      "LEAD_ARP_MODE" => "flylo_spiral",
      "FLYLO_DRUMS_ONLY" => "0",
      "FLYLO_DRUM_OVERLAY" => "1",
      "FLYLO_QUINT_HATS" => "1",
      "DRUM_CHOPS" => "1",
      "NO_QUANTIZE" => "1",
      "KICK_GAIN" => "1.2",
      "FLYLO_KICK_GAIN" => "1.45",
      "FLYLO_OVERLAY_GAIN" => "1.35",
      "FLYLO_SUB_MIX" => "1.55",
      "FLYLO_TOP_MIX" => "0.95",
      "FLYLO_MERGE_BOOST" => "1.55",
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
      "LEAD_ARP" => "1",
      "MELODIC_LEAD" => "0",
      "EXPERIMENTAL_LEADS" => "1",
      "SCALE_LEAD" => "1",
      "HARMONY_LEAD" => "1",
      "CREATIVE_LEAD" => "1",
      "RAP_VOCAL_MIX" => "1.85",
      "RAP_VOCAL_WEIGHT" => "1.75",
      "RAP_VOCAL_BED_WEIGHT" => "0.72",
      "RAP_VOCAL_DUCK" => "0.58",
      "STREAM_LUFS" => "-14.5",
    ).freeze,

    # Sofa mix (matches engine DILLA_COMFORT_DEFAULTS intent).
    comfort: SHARED_CORE.merge(
      "RENDER_MODE" => "dilla",
      "STREAM_COMFORT" => "1",
      "DILLA_COMFORT" => "1",
      "STREAM_SOUL" => "1",
      "DRUM_PRESET" => "dilla_slight",
      "POCKET_SET" => "dusty",
      "FLYLO_DRUMS_ONLY" => "0",
      "FLYLO_DRUM_OVERLAY" => "0",
      "FLYLO_QUINT_HATS" => "0",
      "DRUM_CHOPS" => "0",
      "KICK_GAIN" => "1.0",
      "FLYLO_KICK_GAIN" => "0.9",
      "KICK_SAMPLE_GAIN" => "1.0",
      "FLYLO_OVERLAY_GAIN" => "0.9",
      "FLYLO_SUB_MIX" => "1.0",
      "FLYLO_TOP_MIX" => "0.65",
      "FLYLO_MERGE_BOOST" => "1.0",
      "FLYLO_BASE_DRUM_VOL" => "0.9",
      "DRUM_BUS_VOL" => "1.05",
      "DRUM_BUS_GAIN" => "1.0",
      "DRUM_MIX_WEIGHT" => "0.9",
      "DRUM_AIR_DB" => "1.2",
      "DRUM_PRESENCE_DB" => "1.2",
      "DRUM_PEAK_DB" => "-3.0",
      "DRUM_PEAK_LIFT_DB" => "0",
      "HARM_MIX_WEIGHT" => "0.95",
      "HARM_BUS_VOL" => "1.15",
      "HARMONIC_PADS_WEIGHT" => "1.15",
      "HARMONIC_PADS_VOLUME" => "1.25",
      "PAD_VOL" => "70",
      "LEAD_ARP" => "1",
      "LEAD_ARP_MODE" => "melodic_soul",
      "LEAD_VOICE" => "soul_prophet",
      "MELODIC_LEAD" => "1",
      "EXPERIMENTAL_LEADS" => "0",
      "SCALE_LEAD" => "0",
      "HARMONY_LEAD" => "0",
      "CREATIVE_LEAD" => "0",
      "RAP_VOCAL_MIX" => "3.2",
      "RAP_VOCAL_WEIGHT" => "2.6",
      "RAP_VOCAL_BED_WEIGHT" => "0.52",
      "RAP_VOCAL_DUCK" => "0.42",
      "HARSHNESS_NOTCH" => "1",
      "PERCEPTUAL_LIMIT" => "1",
      "STREAM_LUFS" => "-17.5",
      "STREAM_TRUE_PEAK" => "-2.0",
      "STREAM_LRA" => "9",
      "STREAM_ROTATE_LEAD" => "1",
      "STREAM_ROTATE_SYNTH" => "1",
      "SWING" => "56",
    ).freeze,

    # Warp / Brainfeeder bias — engine RENDER_MODE=warp fills spectral knobs.
    warp: SHARED_CORE.merge(
      "RENDER_MODE" => "warp",
      "STREAM_COMFORT" => "0",
      "DILLA_COMFORT" => "0",
      "SPECTRAL_ENGINE" => "1",
      "SPECTRAL_ARP" => "1",
      "HARMONIC_STACK" => "1",
      "ARP_IDM_BIAS" => "1",
      "DRUM_CHOPS" => "1",
      "GROOVE_DNA" => "cosmogramma",
      "PERFORMER" => "thundercat",
      "VOICING" => "quartal",
      "LEAD_ARP" => "1",
      "HARMONY_LEAD" => "1",
      "PAD_ARP_MODE" => "wash",
      "LUSH_SYNTH" => "1",
      "SYNTH_MORPH" => "1",
      "ANALOG_CHAIN" => "dub_chamber",
      "FLYLO_DRUM_OVERLAY" => "1",
      "FLYLO_QUINT_HATS" => "1",
      "PAD_VOL" => "58",
      "STREAM_LUFS" => "-14.5",
    ).freeze,
  }.freeze

  # Compat aliases for older code / docs that still say PRODUCT_KIT_ENV.
  PRODUCT_KIT_ENV = PROFILE_ENV[:dilla]
  PRODUCT_COMFORT_ENV = PROFILE_ENV[:comfort]

  module_function

  def resolve_style(style)
    key = style.to_s.downcase.strip
    candidates = [key, key.tr("-", "_"), key.tr("_", "-")].uniq

    profile = candidates.lazy.map { |c| PROFILES[c] }.find { |p| p }
    track = candidates.lazy.map { |c| TRACK_SHORTCUTS[c] }.find { |t| t }

    if profile
      { profile: profile, track: PROFILE_DEFAULT_TRACK[profile], style_key: key }
    elsif track
      { profile: :dilla, track: track, style_key: key }
    else
      nil
    end
  end

  def known_style?(style)
    !resolve_style(style).nil?
  end

  def comfort_style?(style)
    resolve_style(style)&.dig(:profile) == :comfort
  end

  def comfort_requested?
    return false if ENV["STREAM_PUNCH"] == "1"
    return true if ENV["STREAM_COMFORT"] == "1" || ENV["DILLA_COMFORT"] == "1"
    return true if ENV["RENDER_MODE"].to_s.downcase == "comfort"

    false
  end

  def track_for(style)
    resolve_style(style)&.dig(:track) || PROFILE_DEFAULT_TRACK[:dilla]
  end

  def profile_for(style)
    resolved = resolve_style(style)
    return :comfort if comfort_requested? && resolved && resolved[:profile] != :warp
    return :comfort if comfort_style?(style) || (resolved.nil? && comfort_requested?)
    resolved&.dig(:profile) || :dilla
  end

  def engine_command_for(profile)
    case profile
    when :comfort then "comfort"
    when :warp then "dilla" # engine applies RENDER_MODE=warp from env
    else "dilla"
    end
  end

  def engine_args(style, output, bars)
    resolved = resolve_style(style) || { profile: :dilla, track: PROFILE_DEFAULT_TRACK[:dilla] }
    profile = profile_for(style)
    track = resolved[:track] || PROFILE_DEFAULT_TRACK[profile]
    settings = SETTINGS_FOR_TRACK.fetch(track, DEFAULT_SETTINGS).merge("track" => track)
    flags = settings.map { |key, value| "--#{key}=#{value}" }
    argv = [File.join(ROOT, "dilla.rb"), engine_command_for(profile), output, *flags]
    argv << bars.to_s if bars
    argv
  end

  def product_env(style: "dilla")
    profile = profile_for(style)
    base = PROFILE_ENV.fetch(profile, PROFILE_ENV[:dilla])
    env = base.dup
    base.each_key do |key|
      env[key] = ENV[key] if ENV[key] && !ENV[key].empty?
    end
    %w[STREAM_COMFORT DILLA_COMFORT STREAM_PUNCH RAP_VOCAL PAD_VOL STREAM_LUFS RENDER_MODE].each do |key|
      env[key] = ENV[key] if ENV[key] && !ENV[key].empty?
    end
    env["SPEAK"] = ENV.fetch("DILLA_SPEAK", env["SPEAK"])
    if profile == :comfort
      env["STREAM_COMFORT"] = "1"
      env["DILLA_COMFORT"] = "1"
    end
    # Pin track for track shortcuts / profile defaults when operator didn't.
    track = track_for(style)
    env["TRACK"] = track if env["TRACK"].to_s.empty?
    env["PROGRESSION"] = track if env["PROGRESSION"].to_s.empty?
    env
  end

  def style_help
    "profiles: dilla|comfort|warp  tracks: flylo|baroque|bach|neo-soul|jazz  " \
      "aliases: punch|beat|camel→dilla  sofa|smooth→comfort"
  end
end

if __FILE__ == $PROGRAM_NAME
  # Default 16 bars: product/chat previews. Full masters pass --bars 64|112.
  options = { style: "dilla", output: nil, bars: 16 }
  parser = OptionParser.new do |p|
    p.banner = "Usage: dilla.rb generate [--style STYLE] [--output FILE] [--bars N]\n  #{DillaEntrypoint.style_help}"
    p.on("--style STYLE") { |v| options[:style] = v.downcase }
    p.on("--output FILE") { |v| options[:output] = v }
    p.on("--bars N", Integer) { |v| options[:bars] = v }
    p.on("--comfort") { options[:style] = "comfort" }
    p.on("--warp") { options[:style] = "warp" }
  end
  command = ARGV.shift || "help"
  parser.parse!(ARGV)
  abort parser.to_s unless command == "generate"
  abort "warn: --bars must be a positive integer" unless options[:bars].positive?
  unless DillaEntrypoint.known_style?(options[:style])
    abort "warn: unknown style #{options[:style].inspect}; #{DillaEntrypoint.style_help}"
  end

  output = options[:output] || File.join(Dir.pwd, ".master", "media", "#{options[:style].tr('-', '_')}_beat.mp3")
  FileUtils.mkdir_p(File.dirname(output))
  env = DillaEntrypoint.product_env(style: options[:style])
  ok = system(env, RbConfig.ruby, *DillaEntrypoint.engine_args(options[:style], output, options[:bars]))
  abort "warn: dilla render failed" unless ok && File.file?(output)
  length_label = options[:bars] >= 64 ? "full-length" : "preview"
  profile = DillaEntrypoint.profile_for(options[:style])
  puts "ok: generated #{length_label} #{options[:style]} (profile=#{profile}) track (#{options[:bars]} bars) #{output}"
end
