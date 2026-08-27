#!/usr/bin/env ruby
# frozen_string_literal: true

# Refuse to ship a frame that is worse than a real photograph of the subject.
#
# A diffusion model produces its failures confidently: waxy skin, blown
# highlights, a plastic sheen on the cheekbone. None of those raise anything.
# They arrive as a finished JPEG alongside the good ones, and the only thing that
# has ever caught them here is somebody scrolling a folder.
#
# The four failures below are measurable, and STUDIO/PHOTOGRAPHY.md names three
# of them in prose already — this is that document with numbers attached, which
# is what it needed to become something a pipeline can enforce.
#
# Thresholds are CALIBRATED, not chosen. They come from the subject's own
# training photographs, on the argument that a generated frame has no business
# being further from a photograph than her actual photographs are:
#
#   ruby _toolkit/judge.rb --calibrate lora/ragnhild/dataset
#
# The seven that produced the shipped defaults are dim phone selfies, which makes
# these floors permissive rather than strict — a studio render should clear them
# comfortably. Recalibrate against a better reference set and they tighten.
#
#   ruby _toolkit/judge.rb ~/Downloads --match 000001000
#   ruby _toolkit/judge.rb <dir> --quarantine     # move rejects to <dir>/rejected
#
# Exits non-zero when anything is rejected, so it can gate a render.

require "optparse"
require "pathname"
require "yaml"

require_relative "../../postpro/uncanny"

TOOLKIT = Pathname.new(__dir__).expand_path
THRESHOLDS_FILE = TOOLKIT.join("judge_thresholds.yml")
IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze

# Each check names the failure in the language a photographer would use, because
# "texture 0.0102 < 0.0126" tells you nothing about what to change.
CHECKS = {
  "texture" => {
    direction: :floor,
    fault: "waxy, over-smoothed skin — the model rendered a face with no pores",
    remedy: "lower guidance_scale, or add grain in postpro; the negative prompt already asks against it",
  },
  "tonal_range" => {
    direction: :floor,
    fault: "flat and veiled — no real blacks, the whole frame sits in the midtones",
    remedy: "a grade may have lifted the shadows; check postpro before blaming the render",
  },
  "clipping" => {
    direction: :ceiling,
    fault: "blown highlights — detail destroyed rather than rolled off",
    remedy: "lower guidance_scale; every real photograph in the reference set clipped exactly 0%",
  },
  "specular_spread" => {
    direction: :ceiling,
    fault: "plastic sheen — highlights pooling on the skin like wet vinyl",
    remedy: "the 'glossy skin' and 'editorial beauty lighting' phrasings invite this",
  },
}.freeze

def load_thresholds
  return YAML.safe_load_file(THRESHOLDS_FILE).fetch("thresholds") if THRESHOLDS_FILE.file?

  abort "warn: no #{THRESHOLDS_FILE.basename} — run --calibrate <reference dir> first"
end

def frames_in(dir, match)
  found = dir.children.select { |p| p.file? && IMAGE_EXT.include?(p.extname.downcase) }
             .reject { |p| p.basename.to_s.start_with?("contact_sheet") }
  found = found.select { |p| p.basename.to_s.include?(match) } if match
  found.sort_by { |p| p.basename.to_s }
end

# A reference set defines the envelope. Floors take the minimum rather than the
# median: the question is "is this worse than any real photograph", not "is this
# better than average", and a generated frame that merely matches the weakest
# real one is not the thing worth blocking.
def calibrate(dir, match)
  frames = frames_in(dir, match)
  abort "warn: no images in #{dir}" if frames.empty?

  readings = frames.map { |path| Postpro::Uncanny.read(path.to_s) }
  thresholds = CHECKS.to_h do |metric, spec|
    values = readings.map { |r| r.send(metric) }
    # Rounded outward, not to nearest. The file is written to six decimal places,
    # and rounding a floor UP excludes the very image that set it — the first
    # calibration failed two of its own seven reference photographs for exactly
    # that reason. A floor rounds down and a ceiling rounds up, so the envelope
    # can only ever grow by less than a millionth.
    [metric, spec[:direction] == :floor ? (values.min * 1e6).floor / 1e6 : (values.max * 1e6).ceil / 1e6]
  end

  THRESHOLDS_FILE.write(<<~YAML)
    # Calibrated from #{frames.length} reference image(s) in #{dir}.
    #
    # Floors are the reference minimum and ceilings the reference maximum: the
    # question a render has to answer is "am I worse than any real photograph of
    # her", not "am I better than the average one".
    #
    # Regenerate with:
    #   ruby _toolkit/judge.rb --calibrate <dir>
    thresholds:
    #{thresholds.map { |k, v| "  #{k}: #{format('%.6f', v)}" }.join("\n")}
  YAML
  puts "ok: calibrated from #{frames.length} image(s) -> #{THRESHOLDS_FILE}"
  thresholds.each { |metric, value| puts format("  %-16s %s %.6f", metric, CHECKS[metric][:direction], value) }
end

def faults_for(reading, thresholds)
  CHECKS.filter_map do |metric, spec|
    limit = thresholds[metric] or next
    value = reading.send(metric)
    breached = spec[:direction] == :floor ? value < limit : value > limit
    next unless breached

    { metric: metric, value: value, limit: limit, fault: spec[:fault], remedy: spec[:remedy] }
  end
end

options = { match: nil, quarantine: false, calibrate: nil }
OptionParser.new do |parser|
  parser.banner = "usage: judge.rb <dir> [--match STR] [--quarantine] | --calibrate <dir>"
  parser.on("--match STR", "only files whose name contains STR") { |v| options[:match] = v }
  parser.on("--quarantine", "move rejected frames to <dir>/rejected rather than only naming them") do
    options[:quarantine] = true
  end
  parser.on("--calibrate DIR", "recompute thresholds from a reference set") { |v| options[:calibrate] = v }
end.parse!

if options[:calibrate]
  calibrate(Pathname.new(options[:calibrate]).expand_path, options[:match])
  exit 0
end

dir = Pathname.new(ARGV.fetch(0) { abort "warn: usage: judge.rb <dir> [options]" }).expand_path
abort "warn: not a directory: #{dir}" unless dir.directory?

thresholds = load_thresholds
frames = frames_in(dir, options[:match])
abort "warn: no images in #{dir}#{options[:match] && " matching #{options[:match]}"}" if frames.empty?

rejected = []
frames.each do |path|
  faults = faults_for(Postpro::Uncanny.read(path.to_s), thresholds)
  if faults.empty?
    puts "ok:   #{path.basename}"
    next
  end

  rejected << path
  puts "FAIL: #{path.basename}"
  faults.each do |f|
    comparison = CHECKS[f[:metric]][:direction] == :floor ? "below floor" : "above ceiling"
    puts format("        %s %.4f — %s %.4f", f[:metric], f[:value], comparison, f[:limit])
    puts "        #{f[:fault]}"
    puts "        #{f[:remedy]}"
  end
end

puts
puts "#{frames.length - rejected.length}/#{frames.length} frames are at least as photographic as the reference set"

if rejected.any? && options[:quarantine]
  # Moved, never deleted. A frame this refuses is still a render that took thirty
  # seconds of GPU, and the judgement is four numbers against a small reference
  # set — it is allowed to be wrong, and it must be possible to look.
  target = dir.join("rejected")
  target.mkpath
  rejected.each { |path| File.rename(path.to_s, target.join(path.basename).to_s) }
  puts "ok: moved #{rejected.length} frame(s) to #{target} — moved, not deleted"
end

exit(rejected.empty? ? 0 : 1)
