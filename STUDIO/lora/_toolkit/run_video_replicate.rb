#!/usr/bin/env ruby
# frozen_string_literal: true

# One approved still becomes one short clip, on Replicate.
#
# The first frame is an image you have already chosen, so the face is the
# trained LoRA's work and the video model only moves it. Draft first: the draft
# preset is a cheap 480p look at motion and framing, and the final preset is the
# take. The presets, their pinned versions and their quirks are in
# video_models.yml; the lengths each model allows are applied by video.rb.
#
#   ./lora --video-replicate --image out/selfies/07.jpg --prompt "she turns and smiles" --dry-run
#   ./lora --video-replicate --image out/selfies/07.jpg --prompt "..." --preset draft
#   ./lora --video-replicate --image out/selfies_postpro/07.jpg --prompt "..." --preset final --seconds 6
#
# A clip lands in out/video/ with clips.jsonl beside it, and its billed seconds
# go to the same ledger.jsonl the stills use. Replicate deletes API outputs an
# hour after the run, so the file is downloaded before anything else happens.

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

SUBJECT = ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path.freeze
TOOLKIT = Pathname.new(__dir__).expand_path
REPO_ROOT = TOOLKIT.join("../../..").expand_path
OUT_DIR = SUBJECT_DIR.join("out", "video")
LEDGER = SUBJECT_DIR.join("out", "ledger.jsonl")

require_relative "preflight"
require_relative "video"

options = { preset: "draft", image: nil, prompt: nil, seconds: nil, seed: 42, audio: nil, dry_run: false,
            max_seconds: ENV["LORA_MAX_SECONDS"].to_s.empty? ? nil : ENV["LORA_MAX_SECONDS"].to_f }
OptionParser.new do |p|
  p.banner = "Usage: run_video_replicate.rb --image FILE --prompt TEXT [options]"
  p.on("--image FILE", "The approved still: the clip's first frame") { |v| options[:image] = v }
  p.on("--prompt TEXT", "What moves, in plain words") { |v| options[:prompt] = v }
  p.on("--preset NAME", "#{Video.presets.keys.join(', ')} (default draft)") { |v| options[:preset] = v }
  p.on("--seconds N", Float, "About this long; the model's nearest length is used") { |v| options[:seconds] = v }
  p.on("--seed N", Integer, "Seed (default 42)") { |v| options[:seed] = v }
  p.on("--audio", "Generate sound, where the model can") { options[:audio] = true }
  p.on("--no-audio", "No generated sound") { options[:audio] = false }
  p.on("--max-seconds N", Float, "Stop once the ledger shows N billed seconds (env LORA_MAX_SECONDS)") { |v| options[:max_seconds] = v }
  p.on("--dry-run", "Print the model and input; upload and render nothing") { options[:dry_run] = true }
  p.on("-h", "--help") { puts p; exit 0 }
end.parse!

abort "warn: --image and --prompt are required" unless options[:image] && options[:prompt]

image = Pathname.new(options[:image]).expand_path
image = SUBJECT_DIR.join(options[:image]) unless image.file?
abort "warn: no image at #{options[:image]}" unless image.file?

size = Preflight.image_size(image.to_s)
abort "warn: #{image.basename} is not a readable jpg, png or webp" unless size
abort "warn: #{image.basename} is #{size.min} px on the short edge; a first frame under #{Preflight::FLOOR_SHORT_EDGE} makes a soft clip" if size.min < Preflight::FLOOR_SHORT_EDGE

spec = Video.preset(options[:preset])
model = Video.model_id(spec)
input = Video.build_input(spec, prompt: options[:prompt], image_url: "<uploaded>", seconds: options[:seconds],
                                seed: options[:seed], audio: options[:audio])
puts "ok: #{options[:preset]}: #{model}"
puts "ok: #{spec['note']}"
puts "ok: input #{JSON.generate(input)}"
puts "note: #{image.basename} is #{size.join('x')}; #{spec['model']} reframes it" if input["aspect_ratio"]

if options[:dry_run]
  puts "ok: dry-run (nothing uploaded, nothing rendered)"
  exit 0
end

require REPO_ROOT.join("STUDIO/replicate/client").to_s
client = Studio::ReplicateClient.new

declared = client.input_names(spec.fetch("model"))
unknown = input.keys - declared
abort "warn: #{spec['model']} does not declare #{unknown.join(', ')}; the schema moved, re-read it and update video_models.yml" if declared.any? && unknown.any?

spent = Preflight.ledger_seconds(LEDGER, "video")
if options[:max_seconds] && spent >= options[:max_seconds]
  abort "warn: ledger shows #{spent.round} billed seconds, at the ceiling #{options[:max_seconds].round}"
end

input[spec.fetch("image_key")] = client.upload_file(image.to_s)
prediction = client.run(model, input, timeout: 900)

FileUtils.mkdir_p(OUT_DIR)
path = OUT_DIR.join("#{image.basename('.*')}_#{options[:preset]}_s#{options[:seed]}.mp4")
client.download_url(Array(prediction["output"]).first, path.to_s)

seconds = prediction.dig("metrics", "predict_time").to_f
Preflight.ledger_append(LEDGER, kind: "video", preset: options[:preset], id: prediction["id"], seconds:)
File.open(OUT_DIR.join("clips.jsonl"), "a") do |log|
  log.puts JSON.generate(clip: path.basename.to_s, source: image.basename.to_s, preset: options[:preset], model:,
                         prompt: options[:prompt], input: input.except("prompt", spec.fetch("image_key")),
                         prediction: prediction["id"], predict_seconds: seconds, rendered_at: Time.now.utc.iso8601)
end
puts "ok: #{path} (#{seconds.round(1)} s billed)"
