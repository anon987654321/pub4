#!/usr/bin/env ruby
# frozen_string_literal: true

# Dual-track train: zip the curated dataset, train via Replicate
# ostris/flux-dev-lora-trainer, pull LoRA weights into weights/#{MODEL}/.
#
# Usage:
#   ./run_train_replicate.rb
#   ./run_train_replicate.rb --dry-run
#   ./run_train_replicate.rb --async
#   LORA_REPLICATE_DEST=you/#{SUBJECT}-flux ./run_train_replicate.rb
#
# Env:
#   REPLICATE_API_TOKEN / REPLICATE_API_KEY / ~/.config/repligen/config.json
#   LORA_REPLICATE_DEST   owner/name (default: $username/#{SUBJECT}-flux)
#   LORA_TRIGGER          default #{SUBJECT}
#   LORA_REPLICATE_STEPS  default 1000 (Replicate sweet spot; local YAML uses 1800)
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
# two copies when lora/ moved under STUDIO/; now there is one.
REPO_ROOT = SCRIPT_DIR.join("../../..").expand_path
DATASET_DIR = SUBJECT_DIR.join("dataset")
WEIGHTS_DIR = SUBJECT_DIR.join("weights", MODEL)
# Scratch: the zip we upload and the tar we download. Neither is a deliverable,
# which is why it is no longer called exports/.
EXPORTS_DIR = SUBJECT_DIR.join(".cache")
LOG_PATH = WEIGHTS_DIR.join("replicate_train.log")

MASTER_CLIENT = REPO_ROOT.join("MASTER/lib/io/replicate_client.rb")
abort "warn: missing #{MASTER_CLIENT}" unless MASTER_CLIENT.file?

require MASTER_CLIENT.to_s

options = {
  dry_run: false,
  async: false,
  destination: ENV["LORA_REPLICATE_DEST"].to_s.strip,
  trigger: ENV.fetch("LORA_TRIGGER", "#{SUBJECT}"),
  steps: (ENV["LORA_REPLICATE_STEPS"] || "1000").to_i,
  lora_rank: (ENV["LORA_REPLICATE_LORA_RANK"] || "16").to_i,
  timeout: (ENV["LORA_REPLICATE_TIMEOUT"] || "3600").to_i,
  webhook: ENV["REPLICATE_WEBHOOK_URL"].to_s.strip,
}

OptionParser.new do |p|
  p.banner = "Usage: run_train_replicate.rb [options]"
  p.on("--dry-run", "Zip + plan only; no upload or train") { options[:dry_run] = true }
  p.on("--async", "Create training and exit (use with webhook or poll later)") { options[:async] = true }
  p.on("--destination OWNER/NAME", "Private model destination") { |v| options[:destination] = v }
  p.on("--trigger WORD", "Trigger word (default #{SUBJECT})") { |v| options[:trigger] = v }
  p.on("--steps N", Integer, "Training steps (default 1000)") { |v| options[:steps] = v }
  p.on("--lora-rank N", Integer, "LoRA rank (default 16; local YAML uses 32)") { |v| options[:lora_rank] = v }
  p.on("--timeout SEC", Integer, "Poll timeout seconds") { |v| options[:timeout] = v }
  p.on("--webhook URL", "Replicate webhook URL") { |v| options[:webhook] = v }
  p.on("-h", "--help") { puts p; exit 0 }
end.parse!

IMAGE_EXT = %w[.jpg .jpeg .png .webp].freeze

def dataset_images(dir)
  dir.children.select { |p| p.file? && IMAGE_EXT.include?(p.extname.downcase) }.sort_by(&:to_s)
end

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

images = dataset_images(DATASET_DIR)
abort "warn: no images in #{DATASET_DIR}" if images.empty?

zip_path = EXPORTS_DIR.join("#{SUBJECT}_dataset.zip")
zip_dataset(DATASET_DIR, zip_path)
puts "ok: zip #{zip_path} (#{images.length} images, #{File.size(zip_path)} bytes)"

client = nil
unless options[:dry_run]
  begin
    client = Master::Io::ReplicateClient.new
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

puts "ok: destination #{destination}"
puts "ok: trigger #{options[:trigger]} steps=#{options[:steps]} lora_rank=#{options[:lora_rank]}"

if options[:dry_run]
  puts "ok: dry-run (no upload/train)"
  puts "tip: ./lora --train-replicate"
  exit 0
end

zip_url = client.upload_zip(zip_path.to_s)
puts "ok: uploaded #{zip_url}"

training = client.train_lora(
  zip_url,
  destination,
  trigger_word: options[:trigger],
  steps: options[:steps],
  lora_rank: options[:lora_rank],
  webhook: options[:webhook].empty? ? nil : options[:webhook],
  webhook_events_filter: options[:webhook].empty? ? nil : %w[completed],
  wait: !options[:async],
  timeout: options[:timeout]
)

training_id = training["id"]
status = training["status"]
puts "ok: training id=#{training_id} status=#{status}"

if options[:async]
  append_log([
    "async training id=#{training_id}",
    "destination=#{destination}",
    "trigger=#{options[:trigger]}",
    "steps=#{options[:steps]}",
    "zip=#{zip_path}",
    "webhook=#{options[:webhook]}",
  ])
  puts "ok: async — poll: ruby -e '...' or https://replicate.com/trainings/#{training_id}"
  puts "ok: when succeeded, re-run without --async or pull weights from training output.weights"
  exit 0
end

version = training.dig("output", "version") || training["output"]
weights_url = client.training_weights_url(training)
puts "ok: version #{version}" if version
puts "ok: weights_url #{weights_url}" if weights_url

WEIGHTS_DIR.mkpath
sidecar = {
  trained_at: Time.now.utc.iso8601,
  destination: destination,
  training_id: training_id,
  trigger_word: options[:trigger],
  steps: options[:steps],
  lora_rank: options[:lora_rank],
  version: version,
  weights_url: weights_url,
  dataset_images: images.length,
  zip: zip_path.to_s,
}
File.write(WEIGHTS_DIR.join("replicate_training.json"), JSON.pretty_generate(sidecar))

extracted = []
if weights_url.to_s.match?(%r{\Ahttps://}i)
  tar_path = EXPORTS_DIR.join("trained_model_#{training_id}.tar")
  begin
    client.download_url(weights_url, tar_path.to_s)
    puts "ok: downloaded #{tar_path}"
    extracted = extract_weights_tar(tar_path, WEIGHTS_DIR)
    extracted.each { |path| puts "ok: weight #{path}" }
  rescue StandardError => e
    warn "warn: could not download/extract weights: #{e.message}"
    warn "fix: open #{weights_url} or use destination model on Replicate API"
  end
else
  warn "warn: no downloadable weights URL; use destination model version for API generate"
end

append_log([
  "lora-train: name=#{SUBJECT} images=#{images.length} trigger=#{options[:trigger]}",
  "destination: #{destination}",
  "version: #{version}",
  "training_id: #{training_id}",
  "weights: #{extracted.join(', ')}",
  "zip: #{zip_path}",
])

puts "ok: done destination=#{destination} weights_dir=#{WEIGHTS_DIR}"
puts "tip: ./lora --generate   # local sample if .safetensors present"
puts "tip: predict via Replicate on #{destination} (include trigger word in prompts)"
