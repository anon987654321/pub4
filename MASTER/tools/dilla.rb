#!/usr/bin/env ruby
# frozen_string_literal: true

# Stable MASTER entrypoint for the Dilla Lab. Keeps generated audio outside source.
require "optparse"
require "fileutils"
require "rbconfig"

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

root = File.expand_path("dilla", __dir__)
output = options[:output] || File.join(Dir.pwd, ".master", "media", "#{options[:style]}_beat.mp3")
FileUtils.mkdir_p(File.dirname(output))
case options[:style]
when "dilla", "flylo", "baroque", "bach", "neo-soul", "neo_soul", "jazz"
  # 112 bars at the default 86 BPM is a five-minute arranged master: intro,
  # groove, breakdown, build, peak and outro are all scheduled by Dilla Lab.
  # The renderer synthesizes drums, bass, pads, chops and melody, then applies
  # its tape/vinyl/parallel-bus/master chain; it does not return stems/snippets.
  style = options[:style].tr("-", "_")
  # "flylo" -> "chromatic_mediant": the underlying engine's track/preset
  # keys were renamed away from artist names (theory-based names instead).
  track = { "bach" => "baroque", "dilla" => "timeless", "flylo" => "chromatic_mediant" }.fetch(style, style)
  env = case track
        when "chromatic_mediant" then { "TRACK" => track, "SONITEX_PRESET" => "classic", "ANALOG_CHAIN" => "cassette" }
        when "baroque" then { "TRACK" => track, "SONITEX_PRESET" => "classic", "ANALOG_CHAIN" => "broadcast" }
        when "neo_soul" then { "TRACK" => track, "SONITEX_PRESET" => "donuts_warm", "ANALOG_CHAIN" => "dub_chamber" }
        else { "TRACK" => track, "SONITEX_PRESET" => "heavy", "ANALOG_CHAIN" => "broadcast" }
        end
  argv = [RbConfig.ruby, File.join(root, "dilla.rb"), "dilla", output]
  argv << options[:bars].to_s if options[:bars]
  ok = system(env, *argv)
else
  abort "warn: unknown style #{options[:style].inspect}; use dilla, flylo, baroque, neo-soul, or jazz"
end
abort "warn: dilla render failed" unless ok && File.file?(output)
length_label = options[:bars] >= 64 ? "full-length" : "preview"
puts "ok: generated #{length_label} #{options[:style]} track (#{options[:bars]} bars) #{output}"
