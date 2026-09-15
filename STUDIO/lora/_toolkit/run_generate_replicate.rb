#!/usr/bin/env ruby
# frozen_string_literal: true

# Render a prompt set on the subject's LoRA where it was trained: Replicate.
#
# --generate needs a CUDA GPU and ai-toolkit, and this Mac has neither. A LoRA
# trained on Replicate is already a hosted model there, so its frames can be
# rendered without moving the weights anywhere. The model is pinned to the
# version the training produced, read from the sidecar run_train_replicate.rb
# wrote, so a later training cannot silently change what a set renders against.
#
#   ./lora --generate-replicate --set selfies
#   ./lora --generate-replicate --set distance --dry-run
#   ./lora --generate-replicate --set scenarios --only 3,7 --scale 1.0
#
# Frames land in out/<set>/NN.jpg with a prompts.jsonl beside them, and a frame
# already on disk is skipped, so an interrupted run resumes. One request at a
# time: under $10 of credit Replicate allows a burst of five, and a parallel run
# lost two frames of twelve to it.

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

SUBJECT = ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
MODEL = ENV.fetch("MODEL") { abort "run a subject wrapper, not this script directly" }
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path.freeze
TOOLKIT = Pathname.new(__dir__).expand_path
SIDECAR = SUBJECT_DIR.join("weights", MODEL, "replicate_training.json")
REPO_ROOT = TOOLKIT.join("../../..").expand_path

require_relative "shoots"

options = { set: "selfies", only: nil, side: nil, scale: 1.0, seed: 42, dry_run: false,
            model: ENV["LORA_REPLICATE_MODEL"].to_s.strip }
OptionParser.new do |p|
  p.banner = "Usage: run_generate_replicate.rb [options]"
  p.on("--set NAME", "Prompt set (#{available_sets.join(', ')}); default selfies") { |v| options[:set] = v }
  p.on("--only LIST", "Sitting numbers, e.g. 1,5,9") { |v| options[:only] = v.split(",").map { |n| Integer(n) } }
  p.on("--side NAME", "One side of a written set") { |v| options[:side] = v }
  p.on("--scale X", Float, "lora_scale (default 1.0; 0.8 lost the fringe)") { |v| options[:scale] = v }
  p.on("--seed N", Integer, "Seed for sitting 1; sitting n uses seed + n - 1") { |v| options[:seed] = v }
  p.on("--model ID", "owner/name:version (default: the trained version)") { |v| options[:model] = v }
  p.on("--dry-run", "Print the prompts and the model; render nothing") { options[:dry_run] = true }
  p.on("-h", "--help") { puts p; exit 0 }
end.parse!

abort "warn: unknown set #{options[:set]} — have: #{available_sets.join(', ')}" unless available_sets.include?(options[:set])

def trained_model
  abort "warn: no #{SIDECAR}\nfix: ./lora --train-replicate, or --model owner/name:version" unless SIDECAR.file?

  version = JSON.parse(SIDECAR.read)["version"].to_s
  abort "warn: #{SIDECAR} names no version" unless version.include?(":")
  version
end

# The settings the first twelve validation frames of this LoRA were rendered and
# judged at, so a new set is comparable with them.
def render_input(prompt, seed, scale)
  { prompt:, model: "dev", lora_scale: scale, aspect_ratio: "3:4", num_outputs: 1,
    guidance_scale: 3.0, num_inference_steps: 28, output_format: "jpg",
    output_quality: 95, go_fast: false, seed: }
end

# A throttle is waited out; a safety refusal is one new seed, because bare
# shoulders in the dataset trip the checker on prompts that ask for nothing of
# the kind. Anything else is a failure worth reading.
def render(client, model, input, attempts: 4)
  attempts.times do |attempt|
    return Array(client.predict(model, input, timeout: 900)).first
  rescue RuntimeError => e
    raise if attempt == attempts - 1
    raise unless e.message.match?(/429|NSFW/)

    input = input.merge(seed: input[:seed] + 1000) if e.message.include?("NSFW")
    warn "note: #{e.message[/429|NSFW/]} — retrying with seed #{input[:seed]}"
    sleep(e.message.include?("429") ? 10 : 1)
  end
end

model = options[:model].empty? ? trained_model : options[:model]
sittings = prompts_for(SUBJECT, side: options[:side], only: options[:only], set: options[:set])
abort "warn: set #{options[:set]} matched no sittings" if sittings.empty?

out_dir = SUBJECT_DIR.join("out", options[:set])
puts "ok: model #{model}"
puts "ok: #{sittings.length} sitting(s) -> #{out_dir}"

if options[:dry_run]
  sittings.each { |shoot, prompt| puts format("%02d  %s", shoot["n"], prompt) }
  exit 0
end

require REPO_ROOT.join("MASTER/lib/io/replicate_client").to_s
client = Master::Io::ReplicateClient.new
FileUtils.mkdir_p(out_dir)
failed = 0

sittings.each do |shoot, prompt|
  path = out_dir.join(format("%02d.jpg", shoot["n"]))
  next puts("ok: have #{path.basename}") if path.file?

  input = render_input(prompt, options[:seed] + shoot["n"] - 1, options[:scale])
  begin
    client.download_url(render(client, model, input), path.to_s)
  rescue StandardError => e
    failed += 1
    next warn("warn: #{shoot['title']}: #{e.message[0, 200]}")
  end
  File.open(out_dir.join("prompts.jsonl"), "a") do |log|
    log.puts JSON.generate(n: shoot["n"], title: shoot["title"], prompt:, model:, input: input.except(:prompt),
                           rendered_at: Time.now.utc.iso8601)
  end
  puts "ok: #{path}"
end

sheet = SUBJECT_DIR.join("out", "#{options[:set]}_sheet.jpg")
system("ruby", TOOLKIT.join("contact_sheet.rb").to_s, out_dir.to_s, "--cols", "4", "--cell", "384",
       "--label", "--out", sheet.to_s)
abort "warn: #{failed} sitting(s) did not render" if failed.positive?
