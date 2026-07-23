#!/usr/bin/env ruby
# frozen_string_literal: true

# Stable MASTER entrypoint for the Dilla Lab (chat + RAILS product).
# Keeps generated audio outside source.
#
# There is one style: dilla.rb itself. Optional --track pins a progression;
# optional ENV (STREAM_COMFORT, RENDER_MODE=warp, …) are mix knobs, not styles.
require "optparse"
require "fileutils"
require "rbconfig"

module DillaEntrypoint
  ROOT = File.expand_path("dilla", __dir__)

  DEFAULT_SETTINGS = { "sonitex" => "donuts_soul", "analog-chain" => "broadcast", "sidechain" => "1" }.freeze
  DEFAULT_TRACK = "get_dis_money"

  # Kit-forward product ENV — mirrors engine DILLA_STYLE_DEFAULTS / BEST core.
  # Single table: the style is dilla.rb.
  PRODUCT_ENV = {
    "RENDER_MODE" => "dilla",
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
    "FM_DRUMS" => "0",
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
    "PAD_TEXTURE" => "1",
    "PAD_LAYERS" => "1",
    "CHOIR_VOX" => "1",
    "CHOIR_VOX_GAIN" => "0.28",
    "VOCAL_CARVE" => "1",
    "STREAM_DRUM_ROTATE" => "1",
    "LEAD_VOICE" => "soul_prophet",
    "LEAD_ARP_MODE" => "flylo_spiral",
    "KICKS" => "1",
    "POCKET_KICKS" => "1",
    "BACKBEAT_CLAP" => "0",
    "FLYLO_DRUMS_ONLY" => "0",
    "FLYLO_DRUM_OVERLAY" => "0",
    "FLYLO_QUINT_HATS" => "0",
    "DRUM_CHOPS" => "0",
    "NO_QUANTIZE" => "1",
    "KICK_GAIN" => "0.68",
    "FLYLO_KICK_GAIN" => "0.75",
    "FLYLO_OVERLAY_GAIN" => "0.95",
    "FLYLO_SUB_MIX" => "1.0",
    "FLYLO_TOP_MIX" => "0.65",
    "FLYLO_MERGE_BOOST" => "1.05",
    "DRUM_BUS_VOL" => "0.95",
    "DRUM_BUS_GAIN" => "0.92",
    "DRUM_MIX_WEIGHT" => "0.95",
    "DRUM_AIR_DB" => "1.8",
    "DRUM_PRESENCE_DB" => "1.5",
    "HARM_MIX_WEIGHT" => "1.12",
    "HARM_BUS_VOL" => "1.4",
    "HARMONIC_PADS_WEIGHT" => "1.12",
    "HARMONIC_PADS_VOLUME" => "1.2",
    "PAD_VOL" => "62",
    "LEAD_ARP" => "1",
    "MELODIC_LEAD" => "0",
    "EXPERIMENTAL_LEADS" => "1",
    "SCALE_LEAD" => "1",
    "HARMONY_LEAD" => "1",
    "CREATIVE_LEAD" => "1",
    "THEORY_RUNTIME" => "1",
    "THEORY_DILLA" => "1",
    "RAP_VOCAL" => "jonas_v",
    "RAP_VOCAL_STYLE" => "rap",
    "RAP_VOCAL_MIX" => "1.85",
    "RAP_VOCAL_WEIGHT" => "1.75",
    "RAP_VOCAL_BED_WEIGHT" => "0.72",
    "RAP_VOCAL_DUCK" => "0.58",
    "RAP_VOCAL_SIDECHAIN" => "1",
    "STREAM_LUFS" => "-16.5",
  }.freeze

  PRODUCT_KIT_ENV = PRODUCT_ENV

  module_function

  def track_for(name)
    key = name.to_s.downcase.strip.tr("-", "_")
    return DEFAULT_TRACK if key.empty? || key == "dilla" || key == "default"
    key
  end

  def engine_args(track, output, bars)
    t = track_for(track)
    flags = DEFAULT_SETTINGS.merge("track" => t).map { |key, value| "--#{key}=#{value}" }
    argv = [File.join(ROOT, "dilla.rb"), "dilla", output, *flags]
    argv << bars.to_s if bars
    argv
  end

  def product_env(track: nil)
    env = PRODUCT_ENV.dup
    PRODUCT_ENV.each_key do |key|
      env[key] = ENV[key] if ENV[key] && !ENV[key].empty?
    end
    %w[STREAM_COMFORT DILLA_COMFORT RAP_VOCAL PAD_VOL STREAM_LUFS RENDER_MODE SPEAK THEORY_BACH THEORY_RUNTIME THEORY_DILLA CHOIR_VOX CHOIR_VOX_GAIN].each do |key|
      env[key] = ENV[key] if ENV[key] && !ENV[key].empty?
    end
    env["SPEAK"] = ENV.fetch("DILLA_SPEAK", env["SPEAK"]) if ENV["DILLA_SPEAK"]
    t = track_for(track || ENV["TRACK"] || DEFAULT_TRACK)
    env["TRACK"] = t if env["TRACK"].to_s.empty?
    env["PROGRESSION"] = t if env["PROGRESSION"].to_s.empty?
    env
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { output: nil, bars: 16, track: nil }
  parser = OptionParser.new do |p|
    p.banner = "Usage: dilla.rb generate [--track PROGRESSION] [--output FILE] [--bars N]\n  engine: dilla.rb (one DNA). theory: THEORY_BACH=1 THEORY_RUNTIME=1"
    p.on("--track TRACK", "Progression id (e.g. get_dis_money, neo_soul, bach_circle_descent)") { |v| options[:track] = v.downcase }
    p.on("--output FILE") { |v| options[:output] = v }
    p.on("--bars N", Integer) { |v| options[:bars] = v }
  end
  command = ARGV.shift || "help"
  parser.parse!(ARGV)
  abort parser.to_s unless command == "generate"
  abort "warn: --bars must be a positive integer" unless options[:bars].positive?

  track = DillaEntrypoint.track_for(options[:track] || "get_dis_money")
  output = options[:output] || File.join(Dir.pwd, ".master", "media", "dilla_#{track}_beat.mp3")
  FileUtils.mkdir_p(File.dirname(output))
  env = DillaEntrypoint.product_env(track:)
  ok = system(env, RbConfig.ruby, *DillaEntrypoint.engine_args(track, output, options[:bars]))
  abort "warn: dilla render failed" unless ok && File.file?(output)
  length_label = options[:bars] >= 64 ? "full-length" : "preview"
  puts "ok: generated #{length_label} dilla track=#{track} (#{options[:bars]} bars) #{output}"
end
