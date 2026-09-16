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
require "net/http"
require "openssl"
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
            model: ENV["LORA_REPLICATE_MODEL"].to_s.strip, grade: ENV.fetch("LORA_GRADE", "random") }
OptionParser.new do |p|
  p.banner = "Usage: run_generate_replicate.rb [options]"
  p.on("--set NAME", "Prompt set (#{available_sets.join(', ')}); default selfies") { |v| options[:set] = v }
  p.on("--only LIST", "Sitting numbers, e.g. 1,5,9") { |v| options[:only] = v.split(",").map { |n| Integer(n) } }
  p.on("--side NAME", "One side of a written set") { |v| options[:side] = v }
  p.on("--scale X", Float, "lora_scale (default 1.0; 0.85 lifts the ageing this adapter bakes in)") { |v| options[:scale] = v }
  p.on("--seed N", Integer, "Seed for sitting 1; sitting n uses seed + n - 1, the distance set holds it") { |v| options[:seed] = v }
  p.on("--model ID", "owner/name:version (default: the trained version)") { |v| options[:model] = v }
  p.on("--grade NAME", "postpro preset, or random (default), or none") { |v| options[:grade] = v }
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

# A set that varies one thing holds the seed, or the seed varies with it and the
# frames cannot say which of the two moved the face. The first distance ladder
# drew a new seed per rung and could not answer its own question.
FIXED_SEED_SETS = %w[distance].freeze

# The settings the first twelve validation frames of this LoRA were rendered and
# judged at, so a new set is comparable with them.
def render_input(prompt, seed, scale)
  { prompt:, model: "dev", lora_scale: scale, aspect_ratio: "3:4", num_outputs: 1,
    guidance_scale: 3.0, num_inference_steps: 28, output_format: "jpg",
    output_quality: 95, go_fast: false, seed: }
end

# A throttle or a dropped connection is waited out; a safety refusal is one new
# seed, because bare shoulders in the dataset trip the checker on prompts that
# ask for nothing of the kind. Anything else is a failure worth reading. Three of
# forty-eight selfies were lost to a reset and two timeouts before the network
# half retried.
TRANSIENT = [Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, Errno::ECONNRESET, EOFError].freeze

def render(client, model, input, attempts: 4)
  attempts.times do |attempt|
    return Array(client.predict(model, input, timeout: 900)).first
  rescue *TRANSIENT, RuntimeError => e
    raise if attempt == attempts - 1
    raise if e.is_a?(RuntimeError) && !e.message.match?(/429|NSFW/)

    input = input.merge(seed: input[:seed] + 1000) if e.message.include?("NSFW")
    warn "note: #{e.class}: #{e.message[0, 80]} — retrying with seed #{input[:seed]}"
    sleep(e.message.include?("NSFW") ? 1 : 10)
  end
end

POSTPRO = REPO_ROOT.join("STUDIO/postpro/postpro.rb")

# A different real chain per frame rather than one house look over the set.
#
# postpro's own --random reads the Downloads folder and writes back to it, so a
# set rendered here cannot reach it. Its presets are those chains under names,
# so the draw happens here and postpro is handed one preset per frame. Drawn by
# sitting number, so frame 7 grades the same way on every run and two takes of
# it stay comparable.
def postpro_presets
  @postpro_presets ||= `ruby #{POSTPRO} --list-presets 2>/dev/null`.scan(/^([a-z][a-z0-9_]*): /).flatten.uniq
end

def preset_for(grade, number)
  return nil if grade == "none"
  return grade unless grade == "random"

  presets = postpro_presets
  abort "warn: postpro listed no presets" if presets.empty?
  presets[(number - 1) % presets.length]
end

# The grade rides beside the frame rather than over it: a regrade needs the
# ungraded render, and a render costs money where a grade costs seconds.
def grade(path, graded_dir, preset)
  FileUtils.mkdir_p(graded_dir)
  ok = system("ruby", POSTPRO.to_s, "--input", path.to_s, "--output", graded_dir.join(path.basename).to_s,
              "--preset", preset, out: File::NULL, err: File::NULL)
  warn "warn: postpro #{preset} failed on #{path.basename}" unless ok
  ok
end

model = options[:model].empty? ? trained_model : options[:model]
sittings = prompts_for(SUBJECT, side: options[:side], only: options[:only], set: options[:set])
abort "warn: set #{options[:set]} matched no sittings" if sittings.empty?

out_dir = SUBJECT_DIR.join("out", options[:set])
graded_dir = SUBJECT_DIR.join("out", "#{options[:set]}_postpro")
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

  seed = FIXED_SEED_SETS.include?(options[:set]) ? options[:seed] : options[:seed] + shoot["n"] - 1
  input = render_input(prompt, seed, options[:scale])
  begin
    client.download_url(render(client, model, input), path.to_s)
  rescue StandardError => e
    failed += 1
    next warn("warn: #{shoot['title']}: #{e.message[0, 200]}")
  end
  preset = preset_for(options[:grade], shoot["n"])
  grade(path, graded_dir, preset) if preset
  File.open(out_dir.join("prompts.jsonl"), "a") do |log|
    log.puts JSON.generate(n: shoot["n"], title: shoot["title"], prompt:, model:, input: input.except(:prompt),
                           grade: preset, rendered_at: Time.now.utc.iso8601)
  end
  puts "ok: #{path}#{preset ? " + #{preset}" : ""}"
end

[out_dir, graded_dir].each do |dir|
  next unless dir.directory?

  sheet = SUBJECT_DIR.join("out", "#{dir.basename}_sheet.jpg")
  system("ruby", TOOLKIT.join("contact_sheet.rb").to_s, dir.to_s, "--cols", "4", "--cell", "384",
         "--label", "--out", sheet.to_s)
end
abort "warn: #{failed} sitting(s) did not render" if failed.positive?
