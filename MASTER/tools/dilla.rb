#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true
# frozen_string_literal: true

# Stable MASTER entrypoint for the Dilla Lab (chat + RAILS product).
# Keeps generated audio outside source. Kit-forward ENV matches
# DILLA_STYLE_DEFAULTS / STREAM_EXTRA kit keys so one-shots sound like stream.
require "optparse"
require "fileutils"
require "rbconfig"

module DillaEntrypoint
  ROOT = File.expand_path("dilla", __dir__)
  STYLES = %w[dilla flylo baroque bach neo-soul neo_soul jazz].freeze

  # Theory-named tracks (not artist labels). dilla style → get_dis_money
  # matches DILLA_STYLE_DEFAULTS::TRACK.
  TRACK_FOR_STYLE = {
    "bach" => "baroque",
    "dilla" => "get_dis_money",
    "flylo" => "chromatic_mediant_drift",
    "baroque" => "baroque",
    "neo_soul" => "neo_soul",
    "neo-soul" => "neo_soul",
    "jazz" => "aydin_jazz_turn",
  }.freeze

  SETTINGS_FOR_TRACK = {
    "chromatic_mediant" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast", "sidechain" => "1" },
    "chromatic_mediant_drift" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast", "sidechain" => "1" },
    "baroque" => { "sonitex" => "classic", "analog-chain" => "broadcast" },
    "neo_soul" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast" },
    "get_dis_money" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast", "sidechain" => "1" },
    "timeless" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast" },
    "aydin_jazz_turn" => { "sonitex" => "donuts_soul", "analog-chain" => "broadcast" },
  }.freeze
  DEFAULT_SETTINGS = { "sonitex" => "donuts_soul", "analog-chain" => "broadcast" }.freeze

  # Subset of DILLA_STYLE_DEFAULTS / STREAM kit layer — applied before engine
  # so soft_fill does not leave product renders on the old pad-forward path.
  PRODUCT_KIT_ENV = {
    "RENDER_MODE" => "dilla",
    "STREAM_CONTINUOUS" => "0",
    "SPEAK" => "0",
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
    "RAP_VOCAL" => "jonas_v",
    "RAP_VOCAL_STYLE" => "rap",
    "RAP_VOCAL_MIX" => "1.85",
    "RAP_VOCAL_WEIGHT" => "1.75",
    "RAP_VOCAL_BED_WEIGHT" => "0.72",
    "RAP_VOCAL_DUCK" => "0.58",
    "RAP_VOCAL_SIDECHAIN" => "1",
    "SONITEX" => "donuts_soul",
    "SONITEX_PRESET" => "donuts_soul",
    "ANALOG_CHAIN" => "broadcast",
    "MASTER_HEURISTICS" => "1",
    "STREAM_NORMALIZE" => "1",
    "STREAM_LUFS" => "-14.5",
  }.freeze

  module_function

  def track_for(style)
    key = style.to_s.downcase
    TRACK_FOR_STYLE.fetch(key) { TRACK_FOR_STYLE.fetch(key.tr("-", "_"), key.tr("-", "_")) }
  end

  def engine_args(style, output, bars)
    track = track_for(style)
    settings = SETTINGS_FOR_TRACK.fetch(track, DEFAULT_SETTINGS).merge("track" => track)
    flags = settings.map { |key, value| "--#{key}=#{value}" }
    argv = [File.join(ROOT, "dilla.rb"), "dilla", output, *flags]
    argv << bars.to_s if bars
    argv
  end

  def product_env
    env = PRODUCT_KIT_ENV.dup
    # Allow operator override (e.g. RAP_VOCAL=0 for instrumental product tracks).
    PRODUCT_KIT_ENV.each_key do |key|
      env[key] = ENV[key] if ENV[key] && !ENV[key].empty?
    end
    env["SPEAK"] = ENV.fetch("DILLA_SPEAK", env["SPEAK"])
    env
  end
end

if __FILE__ == $PROGRAM_NAME
  # Default 16 bars: product/chat previews. Full masters pass --bars 64|112.
  options = { style: "dilla", output: nil, bars: 16 }
  parser = OptionParser.new do |p|
    p.banner = "Usage: dilla.rb generate [--style dilla|flylo|baroque|neo-soul|jazz] [--output FILE] [--bars N]"
    p.on("--style STYLE") { |v| options[:style] = v.downcase }
    p.on("--output FILE") { |v| options[:output] = v }
    p.on("--bars N", Integer) { |v| options[:bars] = v }
  end
  command = ARGV.shift || "help"
  parser.parse!(ARGV)
  abort parser.to_s unless command == "generate"
  abort "warn: --bars must be a positive integer" unless options[:bars].positive?
  unless DillaEntrypoint::STYLES.include?(options[:style])
    abort "warn: unknown style #{options[:style].inspect}; use dilla, flylo, baroque, neo-soul, or jazz"
  end

  output = options[:output] || File.join(Dir.pwd, ".master", "media", "#{options[:style]}_beat.mp3")
  FileUtils.mkdir_p(File.dirname(output))
  env = DillaEntrypoint.product_env
  ok = system(env, RbConfig.ruby, *DillaEntrypoint.engine_args(options[:style], output, options[:bars]))
  abort "warn: dilla render failed" unless ok && File.file?(output)
  length_label = options[:bars] >= 64 ? "full-length" : "preview"
  puts "ok: generated #{length_label} #{options[:style]} track (#{options[:bars]} bars) #{output}"
end
