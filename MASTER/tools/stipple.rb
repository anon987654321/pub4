#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true

# Stipple - density-weighted PNG to SVG portrait stippler.
#
# Usage: ruby multimedia/stipple.rb --in face.png --out face.svg --dots 8000

require "optparse"

begin
  require "chunky_png"
rescue LoadError
  warn "stipple: missing chunky_png — gem install chunky_png"
  exit 1
end

DEFAULT_IN   = File.join(__dir__, "dilla", "face.png")
DEFAULT_DOTS = 8000
DEFAULT_SIZE = 0.6
DEFAULT_BG   = "#ffffff"
DEFAULT_FG   = "#000000"
LUMA         = [0.299, 0.587, 0.114].freeze
LUMA_MAX     = 255.0
EPSILON      = 1e-9

opts = { input: DEFAULT_IN, output: nil, dots: DEFAULT_DOTS, dot_size: DEFAULT_SIZE,
         width: nil, invert: false, bg: DEFAULT_BG, fg: DEFAULT_FG }

OptionParser.new do |o|
  o.banner = "Usage: ruby multimedia/stipple.rb [options]"
  o.on("--in PATH",        "Input PNG (default: #{DEFAULT_IN})")     { |v| opts[:input]    = v }
  o.on("--out PATH",       "Output SVG (default: input with .svg)")  { |v| opts[:output]   = v }
  o.on("--dots N", Integer, "Dot count (default: #{DEFAULT_DOTS})")  { |v| opts[:dots]     = v }
  o.on("--dot-size F", Float, "Dot radius (default: #{DEFAULT_SIZE})") { |v| opts[:dot_size] = v }
  o.on("--width W", Integer, "Output width (default: input width)")  { |v| opts[:width]    = v }
  o.on("--invert",         "Light dots on dark image")               { opts[:invert] = true }
  o.on("--bg COLOR",       "Background (default: #{DEFAULT_BG})")    { |v| opts[:bg] = v }
  o.on("--fg COLOR",       "Dot color (default: #{DEFAULT_FG})")     { |v| opts[:fg] = v }
  o.on("-h", "--help") { puts o; exit }
end.parse!

abort "stipple: input not found: #{opts[:input]}" unless File.exist?(opts[:input])
opts[:output] ||= opts[:input].sub(/\.png\z/i, ".svg")

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

img = begin
  ChunkyPNG::Image.from_file(opts[:input])
rescue StandardError => e
  abort "stipple: read failed: #{e.message}"
end

iw, ih = img.width, img.height
ow = opts[:width] || iw
scale = ow.to_f / iw
oh = (ih * scale).round

cdf = Array.new(iw * ih)
acc = 0.0
ih.times do |y|
  row = y * iw
  iw.times do |x|
    px = img[x, y]
    luma = (LUMA[0] * ChunkyPNG::Color.r(px) + LUMA[1] * ChunkyPNG::Color.g(px) + LUMA[2] * ChunkyPNG::Color.b(px)) / LUMA_MAX
    w = opts[:invert] ? luma : (1.0 - luma)
    acc += w
    cdf[row + x] = acc
  end
end

abort "stipple: image has no contrast" if acc < EPSILON

rng = Random.new
circles = String.new(capacity: opts[:dots] * 48)
opts[:dots].times do
  idx = cdf.bsearch_index { |v| v >= rng.rand * acc } || (cdf.size - 1)
  y, x = idx.divmod(iw)
  cx = ((x + rng.rand) * scale).round(2)
  cy = ((y + rng.rand) * scale).round(2)
  circles << %(<circle cx="#{cx}" cy="#{cy}" r="#{opts[:dot_size]}"/>\n)
end

svg = <<~SVG
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{ow} #{oh}" width="#{ow}" height="#{oh}">
  <rect width="100%" height="100%" fill="#{opts[:bg]}"/>
  <g fill="#{opts[:fg]}">
  #{circles}</g>
  </svg>
SVG

begin
  File.write(opts[:output], svg)
rescue StandardError => e
  abort "stipple: write failed: #{e.message}"
end

ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
puts "stipple: #{opts[:dots]} dots → #{opts[:output]} (#{ms}ms)"
