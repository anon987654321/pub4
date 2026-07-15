#!/usr/bin/env ruby
# frozen_string_literal: true

# Stable MASTER entrypoint for the Dilla Lab. Keeps generated audio outside source.
require "optparse"
require "fileutils"
require "rbconfig"

module DillaEntrypoint
  ROOT = File.expand_path("dilla", __dir__)
  STYLES = %w[dilla flylo baroque bach neo-soul neo_soul jazz].freeze

  # "flylo" -> "chromatic_mediant_drift" etc.: the underlying engine's
  # track/preset keys were renamed away from artist names (theory-based
  # names instead).
  TRACK_FOR_STYLE = {
    "bach" => "baroque", "dilla" => "timeless", "flylo" => "chromatic_mediant_drift"
  }.freeze

  # Engine settings per track, passed as `--flag=value` args (the engine's
  # documented flag interface — see FLAG_ENV in dilla/dilla.rb).
  SETTINGS_FOR_TRACK = {
    "chromatic_mediant" => { "sonitex" => "classic", "analog-chain" => "cassette", "sidechain" => "1" },
    "chromatic_mediant_drift" => { "sonitex" => "classic", "analog-chain" => "cassette", "sidechain" => "1" },
    "baroque" => { "sonitex" => "classic", "analog-chain" => "broadcast" },
    "neo_soul" => { "sonitex" => "donuts_warm", "analog-chain" => "dub_chamber" },
    "timeless" => { "sonitex" => "donuts_warm", "analog-chain" => "broadcast" }
  }.freeze
  DEFAULT_SETTINGS = { "sonitex" => "heavy", "analog-chain" => "broadcast" }.freeze

  module_function

  def track_for(style)
    TRACK_FOR_STYLE.fetch(style.tr("-", "_"), style.tr("-", "_"))
  end

  def engine_args(style, output, bars)
    track = track_for(style)
    settings = SETTINGS_FOR_TRACK.fetch(track, DEFAULT_SETTINGS).merge("track" => track)
    flags = settings.map { |key, value| "--#{key}=#{value}" }
    argv = [File.join(ROOT, "dilla.rb"), "dilla", output, *flags]
    argv << bars.to_s if bars
    argv
  end
end

if __FILE__ == $PROGRAM_NAME
  options = { style: "dilla", output: nil, bars: 112 }
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
  # 112 bars at the default 86 BPM is a five-minute arranged master: intro,
  # groove, breakdown, build, peak and outro are all scheduled by Dilla Lab.
  # The renderer synthesizes drums, bass, pads, chops and melody, then applies
  # its tape/vinyl/parallel-bus/master chain; it does not return stems/snippets.
  ok = system(RbConfig.ruby, *DillaEntrypoint.engine_args(options[:style], output, options[:bars]))
  abort "warn: dilla render failed" unless ok && File.file?(output)
  length_label = options[:bars] >= 64 ? "full-length" : "preview"
  puts "ok: generated #{length_label} #{options[:style]} track (#{options[:bars]} bars) #{output}"
end
