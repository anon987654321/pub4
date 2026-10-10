#!/usr/bin/env ruby
# frozen_string_literal: true

# Dual-track train: zip the curated dataset, train via Replicate
# ostris/flux-dev-lora-trainer, pull LoRA weights into weights/#{MODEL}/.
#
# The trainer fixes the base at FLUX.1-dev. Moving to a FLUX 2 base is a choice
# of model generation, made by changing the trainer, not a default to drift into.
#
# Nothing is uploaded until the dataset and the trigger pass preflight.rb: a
# paid run on twelve soft frames costs the same per second as one on twenty good
# ones. --dry-run prints the report and the cost estimate and stops there.
#
# Usage:
#   ./run_train_replicate.rb
#   ./run_train_replicate.rb --dry-run
#   ./run_train_replicate.rb --async
#   ./run_train_replicate.rb --resume TRAINING_ID
#   ./run_train_replicate.rb --cancel TRAINING_ID
#   LORA_REPLICATE_DEST=you/#{SUBJECT}-flux ./run_train_replicate.rb
#
# Env:
#   REPLICATE_API_TOKEN / REPLICATE_API_KEY / ~/.config/replicate/config.json
#   LORA_REPLICATE_DEST   owner/name (default: $username/#{SUBJECT}-flux)
#   LORA_TRIGGER          default #{SUBJECT}
#   LORA_REPLICATE_STEPS  default 1000 (Replicate's default; local YAML uses 1800)
#   REPLICATE_WEBHOOK_URL     optional; also set --async to not poll
#   LORA_REPLICATE_TIMEOUT seconds (default 3600)

require "fileutils"
require "json"
require "optparse"
require "pathname"
require "tmpdir"
require "time"

# The subject is chosen by the wrapper that invoked this (see _toolkit/toolkit.sh):
# SUBJECT_DIR points at STUDIO/lora/<subject>, and subject.env there names
# SUBJECT, MODEL and TRIGGER.
SUBJECT = ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
MODEL = ENV.fetch("MODEL") { abort "run a subject wrapper, not this script directly" }
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path.freeze

SCRIPT_DIR = Pathname.new(__dir__).expand_path
# _toolkit -> lora -> studio -> repo root. This depth had to be corrected in
# two copies when lora/ moved under MASTER/tools/; now there is one.
REPO_ROOT = SCRIPT_DIR.join("../../..").expand_path
DATASET_DIR = SUBJECT_DIR.join("dataset")
WEIGHTS_DIR = SUBJECT_DIR.join("weights", MODEL)
# Scratch: the zip we upload and the tar we download. Neither is a deliverable,
# which is why it is no longer called exports/.
EXPORTS_DIR = SUBJECT_DIR.join(".cache")
LOG_PATH = WEIGHTS_DIR.join("replicate_train.log")
LEDGER_PATH = SUBJECT_DIR.join("out", "ledger.jsonl")

MASTER_CLIENT = REPO_ROOT.join("STUDIO/replicate/client.rb")
abort "warn: missing #{MASTER_CLIENT}" unless MASTER_CLIENT.file?

require MASTER_CLIENT.to_s
require_relative "preflight"

options = {
  dry_run: false,
  async: false,
  force: false,
  resume: nil,
  cancel: nil,
  destination: ENV["LORA_REPLICATE_DEST"].to_s.strip,
  trigger: ENV.fetch("LORA_TRIGGER", "#{SUBJECT}"),
  steps: (ENV["LORA_REPLICATE_STEPS"] || "1000").to_i,
  lora_rank: (ENV["LORA_REPLICATE_LORA_RANK"] || "16").to_i,
  timeout: (ENV["LORA_REPLICATE_TIMEOUT"] || "3600").to_i,
  webhook: ENV["REPLICATE_WEBHOOK_URL"].to_s.strip,
}

OptionParser.new do |p|
  p.banner = "Usage: run_train_replicate.rb [options]"
  p.on("--dry-run", "Preflight, zip and estimate only; no upload or train") { options[:dry_run] = true }
  p.on("--async", "Create training and exit (use with webhook or poll later)") { options[:async] = true }
  p.on("--force", "Train although preflight found problems") { options[:force] = true }
  p.on("--resume ID", "Fetch a training started with --async, then pull its weights") { |v| options[:resume] = v }
  p.on("--cancel ID", "Cancel a running training") { |v| options[:cancel] = v }
  p.on("--destination OWNER/NAME", "Private model destination") { |v| options[:destination] = v }
  p.on("--trigger WORD", "Trigger word (default #{SUBJECT})") { |v| options[:trigger] = v }
  p.on("--steps N", Integer, "Training steps (default 1000)") { |v| options[:steps] = v }
  p.on("--lora-rank N", Integer, "LoRA rank (default 16, as train.yaml)") { |v| options[:lora_rank] = v }
  p.on("--timeout SEC", Integer, "Poll timeout seconds") { |v| options[:timeout] = v }
  p.on("--webhook URL", "Replicate webhook URL") { |v| options[:webhook] = v }
  p.on("-h", "--help") { puts p; exit 0 }
end.parse!

def zip_dataset(dataset_dir, zip_path)
  FileUtils.mkdir_p(zip_path.dirname)
  FileUtils.rm_f(zip_path)
  # Flat zip: images + matching .txt captions at archive root (trainer expects this).
  Dir.chdir(dataset_dir) do
    entries = Dir.entries(".").reject { |e| e.start_with?(".") }
    abort "warn: dataset empty" if entries.empty?

    ok = system("zip", "-q", "-r", zip_path.to_s, *entries)
    abort "warn: zip failed" unless ok
  end
  zip_path
end

def extract_weights_tar(tar_path, dest_dir)
  unsafe = Preflight.unsafe_tar_entries(tar_path.to_s)
  abort "warn: refusing #{tar_path}: #{unsafe.first(3).join(', ')}" unless unsafe.empty?

  FileUtils.mkdir_p(dest_dir)
  before = dest_dir.glob("*.safetensors").map(&:to_s)
  ok = system("tar", "-xf", tar_path.to_s, "-C", dest_dir.to_s)
  abort "warn: tar extract failed: #{tar_path}" unless ok

  # Flatten common trainer layouts (trained_model/*.safetensors).
  dest_dir.glob("**/*.safetensors").each do |sf|
    next if sf.dirname == dest_dir

    target = dest_dir.join(sf.basename)
    FileUtils.mv(sf.to_s, target.to_s) unless target.exist?
  end

  after = dest_dir.glob("*.safetensors").map(&:to_s)
  new_files = after - before
  new_files
end

def append_log(lines)
  FileUtils.mkdir_p(LOG_PATH.dirname)
  File.open(LOG_PATH, "a") do |f|
    f.puts "--- #{Time.now.utc.iso8601}"
    lines.each { |line| f.puts line }
  end
end

# Everything after a finished training: the sidecar generation reads, the
# weights, the log and the ledger. Shared by a live run and --resume.
def finish_training(client, training, context)
  version = training.dig("output", "version") || training["output"]
  weights_url = client.training_weights_url(training)
  seconds = training.dig("metrics", "predict_time").to_f
  puts "ok: version #{version}" if version
  puts "ok: weights_url #{weights_url.to_s.sub(/\?.*/, '')}" if weights_url
  puts format("ok: billed %.0f s (~$%.2f at the published rate)", seconds, seconds * Preflight::TRAIN_USD_PER_SECOND) if seconds.positive?

  WEIGHTS_DIR.mkpath
  # The base generation beside the weights, because a .safetensors file does not
  # say which model it adapts and nothing can infer it later: a FLUX.1-dev LoRA
  # loads into no FLUX 2 model. The trainer fixes the base, so naming the trainer
  # names it. The ai-toolkit lanes need no such line; ai-toolkit writes the config
  # it trained from, name_or_path included, into the training folder. Written
  # before the download: generation pins the version, and needs no local weights.
  sidecar = context.merge(
    trained_at: Time.now.utc.iso8601,
    base_model: "black-forest-labs/FLUX.1-dev",
    trainer: Studio::ReplicateClient::LORA_TRAINER,
    training_id: training["id"],
    version: version,
    billed_seconds: seconds,
  )
  File.write(WEIGHTS_DIR.join("replicate_training.json"), JSON.pretty_generate(sidecar))

  extracted = fetch_weights(client, weights_url, training["id"])
  append_log([
    "lora-train: name=#{SUBJECT} images=#{sidecar[:dataset_images]} trigger=#{sidecar[:trigger_word]}",
    "destination: #{sidecar[:destination]}",
    "version: #{version}",
    "training_id: #{training['id']}",
    "weights: #{extracted.join(', ')}",
  ])
  Preflight.ledger_append(LEDGER_PATH, kind: "train", id: training["id"], seconds:, steps: sidecar[:steps],
                                       usd: (seconds * Preflight::TRAIN_USD_PER_SECOND).round(2))
  puts "ok: done destination=#{sidecar[:destination]} weights_dir=#{WEIGHTS_DIR}"
  puts "tip: ./lora --generate   # local sample if .safetensors present"
  puts "tip: predict via Replicate on #{sidecar[:destination]} (include trigger word in prompts)"
end

def fetch_weights(client, weights_url, training_id)
  unless weights_url.to_s.match?(%r{\Ahttps://}i)
    warn "warn: no downloadable weights URL; use destination model version for API generate"
    return []
  end

  tar_path = EXPORTS_DIR.join("trained_model_#{training_id}.tar")
  FileUtils.mkdir_p(EXPORTS_DIR)
  client.download_url(weights_url, tar_path.to_s)
  puts "ok: downloaded #{tar_path}"
  extract_weights_tar(tar_path, WEIGHTS_DIR).each { |path| puts "ok: weight #{path}" }
rescue StandardError => e
  warn "warn: could not download/extract weights: #{e.message}"
  warn "fix: open #{weights_url.to_s.sub(/\?.*/, '')} or use destination model on Replicate API"
  []
end

if options[:cancel]
  Studio::ReplicateClient.new.stop_training(options[:cancel])
  puts "ok: cancel requested for #{options[:cancel]}"
  exit 0
end

if options[:resume]
  client = Studio::ReplicateClient.new
  training = client.resume_training(options[:resume], timeout: options[:timeout])
  input = training["input"] || {}
  finish_training(client, training, {
    destination: options[:destination].empty? ? training.dig("output", "version").to_s.split(":").first : options[:destination],
    trigger_word: input["trigger_word"] || options[:trigger],
    steps: input["steps"] || options[:steps],
    lora_rank: input["lora_rank"] || options[:lora_rank],
    dataset_images: Preflight.image_files(DATASET_DIR.to_s).length,
  })
  exit 0
end

# --- preflight: free, local, before anything is uploaded -------------------

trigger_report = Preflight.trigger_report(options[:trigger])
dataset_report = Preflight.dataset_report(DATASET_DIR.to_s, trigger: options[:trigger])
images = dataset_report.images
abort "warn: no images in #{DATASET_DIR}" if images.empty?

problems = trigger_report.problems + dataset_report.problems
(trigger_report.warnings + dataset_report.warnings).each { |line| warn "note: #{line}" }
problems.each { |line| warn "warn: #{line}" }
puts "ok: preflight #{images.length} image(s), #{problems.length} problem(s)"
puts "ok: #{Preflight.cost_estimate(options[:steps])}"
puts "note: images x 100 = #{images.length * 100} steps; steps=#{options[:steps]}"
abort "fix: repair the dataset, or --force to train anyway" unless problems.empty? || options[:force] || options[:dry_run]

zip_path = EXPORTS_DIR.join("#{SUBJECT}_dataset.zip")
zip_dataset(DATASET_DIR, zip_path)
puts "ok: zip #{zip_path} (#{images.length} images, #{File.size(zip_path)} bytes)"

client = nil
unless options[:dry_run]
  begin
    client = Studio::ReplicateClient.new
  rescue ArgumentError => e
    abort "warn: #{e.message} (set REPLICATE_API_TOKEN)"
  end
end

destination = options[:destination]
if destination.empty?
  username = options[:dry_run] ? "YOUR_USERNAME" : client.account_username
  abort "warn: could not resolve Replicate username; set LORA_REPLICATE_DEST=owner/name" if username.to_s.empty?
  destination = "#{username}/#{SUBJECT}-flux"
end

puts "ok: destination #{destination} (a repeat training adds a version; earlier versions stay)"
puts "ok: trigger #{options[:trigger]} steps=#{options[:steps]} lora_rank=#{options[:lora_rank]}"

if options[:dry_run]
  puts "ok: dry-run (no upload/train)"
  puts "tip: ./lora --train-replicate"
  exit 0
end

# A key the trainer does not declare is ignored by the API, so it is sent only
# when the live schema names it.
trainer_input = {}
trainer_input[:lora_type] = "subject" if client.input_names(Studio::ReplicateClient::LORA_TRAINER).include?("lora_type")
trainer_version = client.trainer_version
puts "ok: trainer #{Studio::ReplicateClient::LORA_TRAINER}:#{trainer_version}"

zip_url = client.upload_zip(zip_path.to_s)
puts "ok: uploaded #{zip_url.sub(/\?.*/, '')}"

training = client.train_lora(
  zip_url,
  destination,
  trigger_word: options[:trigger],
  steps: options[:steps],
  lora_rank: options[:lora_rank],
  webhook: options[:webhook].empty? ? nil : options[:webhook],
  webhook_events_filter: options[:webhook].empty? ? nil : %w[completed],
  wait: !options[:async],
  timeout: options[:timeout],
  extra_input: trainer_input,
  version: trainer_version
)

training_id = training["id"]
puts "ok: training id=#{training_id} status=#{training['status']}"

if options[:async]
  append_log([
    "async training id=#{training_id}",
    "destination=#{destination}",
    "trigger=#{options[:trigger]}",
    "steps=#{options[:steps]}",
    "zip=#{zip_path}",
    "webhook=#{options[:webhook]}",
  ])
  puts "ok: async -- when it finishes: ./lora --train-replicate --resume #{training_id}"
  puts "ok: or watch https://replicate.com/trainings/#{training_id}"
  exit 0
end

finish_training(client, training, {
  destination:,
  trigger_word: options[:trigger],
  steps: options[:steps],
  lora_rank: options[:lora_rank],
  dataset_images: images.length,
  dataset_sha256: Preflight.sha256(zip_path.to_s),
  trainer_version:,
  trainer_input: { input_images: "<zip>", trigger_word: options[:trigger], steps: options[:steps],
                   lora_rank: options[:lora_rank] }.merge(trainer_input),
  zip: zip_path.to_s,
})
