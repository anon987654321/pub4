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

require "digest"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "open3"
require "optparse"
require "pathname"
require "rbconfig"
require "time"
require "tmpdir"

SUBJECT =ENV.fetch("SUBJECT") { abort "run a subject wrapper, not this script directly" }
MODEL = ENV.fetch("MODEL") { abort "run a subject wrapper, not this script directly" }
SUBJECT_DIR = Pathname.new(ENV.fetch("SUBJECT_DIR")).expand_path.freeze
TOOLKIT = Pathname.new(__dir__).expand_path
SIDECAR = SUBJECT_DIR.join("weights", MODEL, "replicate_training.json")
REPO_ROOT = TOOLKIT.join("../../../..").expand_path

require_relative "preflight"
require_relative "shoots"

# FLUX 2 holds a person across up to eight reference photographs with no
# training (flux-2-pro's page: eight on the API, nine megapixels in all). A
# reference is shrunk to REFERENCE_EDGE on its long side, so eight of them stay
# under that total.
REFERENCE_MODEL = "black-forest-labs/flux-2-pro"
REFERENCE_LIMIT = 8
REFERENCE_EDGE = 1024
REFERENCE_EXTENSIONS = %w[.jpg .jpeg .png .webp].freeze

options = { set: "selfies", only: nil, side: nil, scale: 1.0, seed: 42, dry_run: false,
            guidance: 3.0, steps: 28, draft: false,
            max_seconds: ENV["LORA_MAX_SECONDS"].to_s.empty? ? nil : ENV["LORA_MAX_SECONDS"].to_f,
            model: ENV["LORA_REPLICATE_MODEL"].to_s.strip, grade: ENV.fetch("LORA_GRADE", "random"),
            references: [], max_images: nil }
OptionParser.new do |p|
  p.banner = "Usage: run_generate_replicate.rb [options]"
  p.on("--set NAME", "Prompt set (#{available_sets.join(', ')}); default selfies") { |v| options[:set] = v }
  p.on("--only LIST", "Sitting numbers, e.g. 1,5,9") { |v| options[:only] = v.split(",").map { |n| Integer(n) } }
  p.on("--side NAME", "One side of a written set") { |v| options[:side] = v }
  p.on("--scale X", Float, "lora_scale (default 1.0; 0.85 lifts the ageing this adapter bakes in)") { |v| options[:scale] = v }
  p.on("--seed N", Integer, "Seed for sitting 1; sitting n uses seed + n - 1, the distance set holds it") { |v| options[:seed] = v }
  p.on("--model ID", "owner/name:version (default: the trained version)") { |v| options[:model] = v }
  p.on("--grade NAME", "postpro preset, or random (default), or none") { |v| options[:grade] = v }
  p.on("--guidance X", Float, "guidance_scale (default 3.0, as the validation frames)") { |v| options[:guidance] = v }
  p.on("--steps N", Integer, "num_inference_steps (default 28, as the validation frames)") { |v| options[:steps] = v }
  p.on("--draft", "Cheap seed-picking pass: webp, go_fast, out/<set>_draft/, ungraded") { options[:draft] = true }
  p.on("--max-seconds N", Float, "Stop once the ledger shows N billed seconds for this subject (env LORA_MAX_SECONDS)") { |v| options[:max_seconds] = v }
  p.on("--reference PATH", "Photograph of the subject, up to #{REFERENCE_LIMIT}; renders on #{REFERENCE_MODEL}, no LoRA") do |v|
    options[:references] << v
  end
  p.on("--max-images N", Integer, "Reference mode: render at most N sittings (billed per image)") do |v|
    options[:max_images] = v
  end
  p.on("--dry-run", "Print the prompts and the model; render nothing") { options[:dry_run] = true }
  p.on("-h", "--help") { puts p; exit 0 }
end.parse!

REFERENCE_MODE = !options[:references].empty?
# Reference frames share sitting numbers with LoRA frames, so the ledger keeps them apart.
LEDGER_SET = REFERENCE_MODE ? "#{options[:set]}_ref" : options[:set]
if REFERENCE_MODE
  refs = options[:references].map { |path| File.expand_path(path) }
  abort "warn: --reference takes at most #{REFERENCE_LIMIT} photographs, got #{refs.length}" if refs.length > REFERENCE_LIMIT
  refs.each do |path|
    image = File.file?(path) && REFERENCE_EXTENSIONS.include?(File.extname(path).downcase)
    abort "warn: reference #{path} is not a jpg, png or webp file" unless image
  end
  abort "warn: --reference needs --max-images N; flux-2 bills per image, the ledger counts seconds" unless options[:max_images]&.positive?
  options[:references] = refs
  options[:model] = REFERENCE_MODEL if options[:model].empty?
end

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
def render_input(prompt, seed, options)
  if REFERENCE_MODE
    return { prompt:, input_images: Array(options[:reference_urls]), aspect_ratio: "3:4",
             output_format: "jpg", output_quality: 95, seed: }
  end

  input = { prompt:, model: "dev", lora_scale: options[:scale], aspect_ratio: "3:4", num_outputs: 1,
            guidance_scale: options[:guidance], num_inference_steps: options[:steps], output_format: "jpg",
            output_quality: 95, go_fast: false, seed: }
  # A draft picks seeds; it is not a take, so it trades the look for the price.
  input.merge!(output_format: "webp", output_quality: 80, go_fast: true) if options[:draft]
  input
end

# Only explicit refusals are safe to repeat. Replicate's throttling 429 rejects
# the create, and an NSFW refusal creates no prediction, so the latter gets a new
# seed. A read timeout/reset may follow a successful paid create; stop and
# reconcile instead of creating a duplicate. A connection-open timeout is safe.
TRANSIENT = [Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, Errno::ECONNRESET, EOFError].freeze

def render(client, model, input, attempts: 4)
  attempts.times do |attempt|
    return client.run(model, input, timeout: 900)
  rescue *TRANSIENT, RuntimeError => e
    raise if attempt == attempts - 1

    refused = e.is_a?(RuntimeError) && e.message.match?(/\AReplicate API 429:|NSFW/i)
    safe_connect_failure = e.is_a?(Net::OpenTimeout)
    raise unless refused || safe_connect_failure

    input = input.merge(seed: input[:seed] + 1000) if e.message.match?(/NSFW/i)
    warn "note: #{e.class}: #{e.message[0, 80]} — retrying with seed #{input[:seed]}"
    sleep(e.message.match?(/NSFW/i) ? 1 : 10)
  end
end

POSTPRO = REPO_ROOT.join("STUDIO/postpro/postpro.rb")

# A different real chain per frame rather than one house look over the set.
#
# postpro's own --random reads the Downloads folder and writes back to it, so a
# set rendered here cannot reach it. Its presets are those chains under names,
# so the draw happens here and postpro is handed one preset per frame. Every
# preset prints an `fx:` line of its own, which is a chain and not a preset name. Drawn by
# sitting number, so frame 7 grades the same way on every run and two takes of
# it stay comparable.
# Avoid writing a second row when a run resumes after local output delivery.
# Missing, non-finite or negative provider timing is unknown spend, not zero.
def measured_predict_seconds(prediction)
  seconds = Float(prediction.dig("metrics", "predict_time"))
  seconds if seconds.finite? && seconds >= 0
rescue ArgumentError, TypeError
  nil
end

def prompt_receipt_exists?(path, n:, prediction:)
  return false unless File.file?(path)

  File.foreach(path).with_index do |line, index|
    row = begin
      JSON.parse(line)
    rescue JSON::ParserError
      raise IOError, "prompt manifest line #{index + 1} is invalid JSON"
    end
    raise IOError, "prompt manifest line #{index + 1} is not an object" unless row.is_a?(Hash)

    return true if row["n"].to_i == n.to_i && row["prediction"].to_s == prediction.to_s
  end
  false
end

def postpro_presets
  return @postpro_presets if defined?(@postpro_presets)

  stdout, stderr, status = Open3.capture3(RbConfig.ruby, POSTPRO.to_s, "--list-presets")
  unless status.success?
    diagnostic = [stderr.strip, stdout.lines.first(4).join(" ").strip].reject(&:empty?).join(" — ")[0, 300]
    detail = diagnostic.empty? ? "" : ": #{diagnostic}"
    abort "warn: postpro --list-presets failed (#{status.exitstatus})#{detail}"
  end

  presets = stdout.scan(/^([a-z][a-z0-9_]*): /).flatten.uniq - %w[fx]
  abort "warn: postpro listed no presets" if presets.empty?

  @postpro_presets = presets.freeze
end

def preset_for(grade, number)
  return if grade == "none"
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
if REFERENCE_MODE
  # The prompts name the LoRA's trigger word, which means nothing to a model
  # that has not been trained on it. The photographs carry the person instead.
  env = subject_env(SUBJECT)
  trigger = env.fetch("TRIGGER")
  # The written scenes say "her" and "she", because they were drafted for
  # Ragnhild. A man's frame reads them as his: "her" before a noun is "his",
  # "her" ending a clause is "him".
  man = env.fetch("DESCRIPTOR", "").match?(/\bman\b/i)
  object_her = /\bher\b(?= *(?:[,.;:]|\z|and\b|with\b|from\b|in\b|while\b|as\b|but\b))/
  sittings = sittings.first(options[:max_images]).map do |shoot, prompt|
    prompt = prompt.gsub(trigger, "the person in the reference photographs")
    prompt = prompt.gsub(object_her, "him").gsub(/\bher\b/, "his").gsub(/\bshe\b/, "he") if man
    [shoot, prompt]
  end
end

lane = REFERENCE_MODE ? "_ref" : ""
suffix = options[:draft] ? "_draft" : lane
out_dir = SUBJECT_DIR.join("..", "out", SUBJECT_DIR.basename.to_s, "#{options[:set]}#{suffix}")
graded_dir = SUBJECT_DIR.join("..", "out", SUBJECT_DIR.basename.to_s, "#{options[:set]}#{lane}_postpro")
extension = options[:draft] ? "webp" : "jpg"
LEDGER = SUBJECT_DIR.join("..", "out", SUBJECT_DIR.basename.to_s, "ledger.jsonl")
puts "ok: model #{model}"
puts "ok: #{sittings.length} sitting(s) -> #{out_dir}#{options[:draft] ? " (draft: webp, go_fast, ungraded)" : ""}"

if options[:dry_run]
  options[:references].each { |path| puts "ok: reference #{path}" }
  sittings.each { |shoot, prompt| puts format("%02d  %s", shoot["n"], prompt) }
  if REFERENCE_MODE
    puts "ok: #{sittings.length} image(s) at the model's per-image price; its page lists the rate"
  else
    puts "ok: #{Preflight.render_estimate(sittings.length)}"
  end
  exit 0
end

require REPO_ROOT.join("STUDIO/replicate/client").to_s
client = Studio::ReplicateClient.new

# References are shrunk, then uploaded, once per run. Their upload URLs change
# every run, so the fingerprint that guards a resume uses the photographs' own
# digests and not the URLs.
REFERENCE_DIGESTS = options[:references].map { |path| Digest::SHA256.file(path).hexdigest[0, 16] }.freeze
if REFERENCE_MODE
  scratch = Dir.mktmpdir("lora_reference")
  at_exit { FileUtils.remove_entry(scratch) }
  options[:reference_urls] = options[:references].each_with_index.map do |path, index|
    small = File.join(scratch, format("%02d.jpg", index))
    edge = "#{REFERENCE_EDGE}x#{REFERENCE_EDGE}>"
    ok = system("magick", path, "-auto-orient", "-resize", edge, "-quality", "92", small)
    abort "warn: could not shrink reference #{path}" unless ok && File.size?(small)

    client.upload_file(small)
  end
  puts "ok: #{options[:reference_urls].length} reference photograph(s) uploaded"
end

# A key the model does not declare is dropped by the API without a word, which
# is a differently-rendered picture and no error.
declared = client.input_names(model.split(":").first)
unknown = render_input("", 0, options).keys.map(&:to_s) - declared
abort "warn: #{model} does not declare #{unknown.join(', ')}; fix the input or pass --model" if declared.any? && unknown.any?

FileUtils.mkdir_p(out_dir)
failed = 0
start_usd = Preflight.ledger_usd(LEDGER)
start_render_seconds = Preflight.ledger_seconds(LEDGER, "render")
inconclusive = Preflight.inconclusive_render_receipts(LEDGER)
unless inconclusive.empty?
  receipts = inconclusive.map do |row|
    "#{row["set"] || "?"}/#{row["n"] || "?"} prediction=#{row["id"] || "unknown"}"
  end
  abort "warn: render spend is inconclusive for #{receipts.join(", ")}; reconcile the ledger before paid work"
end
todo = sittings.count { |shoot, _| !out_dir.join(format("%02d.%s", shoot["n"], extension)).file? }
puts "ok: #{Preflight.render_estimate(todo)}"
spent = start_render_seconds
observed_render_seconds = 0.0
cost_inconclusive = false
cost_inconclusive_reason = nil

sittings.each do |shoot, prompt|
  path = out_dir.join(format("%02d.%s", shoot["n"], extension))
  abort "warn: refusing symlinked output path #{path}" if File.symlink?(path)
  next puts("ok: have #{path.basename}") if File.file?(path) && File.size?(path)
  abort "warn: output path is not a regular file: #{path}" if File.exist?(path) && !File.file?(path)

  seed = FIXED_SEED_SETS.include?(options[:set]) ? options[:seed] : options[:seed] + shoot["n"] - 1
  input = render_input(prompt, seed, options)
  fingerprint = Preflight.render_fingerprint(model:, input: REFERENCE_MODE ? input.merge(input_images: REFERENCE_DIGESTS) : input)
  receipt = Preflight.latest_render_event(LEDGER, set: LEDGER_SET, n: shoot["n"])
  action = Preflight.render_receipt_action(receipt, fingerprint:)
  abort "warn: unresolved paid render receipt for #{path.basename}; inspect #{LEDGER} and reconcile before rerunning" if action == :blocked

  if action == :new
    if options[:max_seconds] && spent >= options[:max_seconds]
      warn "warn: ledger shows #{spent.round} billed seconds, at the ceiling #{options[:max_seconds].round}; stopping"
      failed += 1
      break
    end

    # Persist the intent before the create request. If the response is lost,
    # the next run stops rather than accidentally creating the same paid job again.
    Preflight.ledger_append(LEDGER, kind: "render_attempt", status: "started",
                                     set: LEDGER_SET, n: shoot["n"], model:,
                                     fingerprint:, seed:)
    begin
      prediction = render(client, model, input)
      seconds = measured_predict_seconds(prediction)
      output_url = Array(prediction["output"]).first.to_s
      if seconds
        spent += seconds
        observed_render_seconds += seconds
      else
        cost_inconclusive = true
        cost_inconclusive_reason = "prediction #{prediction["id"]} omitted finite non-negative metrics.predict_time"
      end
      # The durable prediction receipt comes before downloading its expiring URL.
      Preflight.ledger_append(LEDGER, kind: "render_attempt", status: "prediction_received",
                                       set: LEDGER_SET, n: shoot["n"], model:, fingerprint:,
                                       id: prediction["id"], output_url:, seconds:)
      if prediction["id"].to_s.empty? || output_url.empty?
        raise IOError, "prediction response omitted its id or output URL; receipt retained"
      end
    rescue StandardError => e
      failed += 1
      warn "warn: #{shoot['title']}: #{e.message[0, 200]}"
      break
    end
  else
    prediction = {
      "id" => receipt["id"],
      "output" => [receipt["output_url"]],
      "metrics" => { "predict_time" => receipt["seconds"].to_f },
    }
    output_url = receipt["output_url"]
    seconds = receipt["seconds"].to_f
  end

  begin
    # A receipt resume is a free re-download of the same prediction, never a
    # second create request.
    client.download_url(output_url, path.to_s)
  rescue StandardError => e
    failed += 1
    warn "warn: #{shoot['title']}: #{e.message[0, 200]}"
    break if cost_inconclusive
    next
  end

  if action == :new || receipt["kind"] == "render_attempt"
    Preflight.ledger_append(LEDGER, kind: "render", status: "output_ready",
                                     set: LEDGER_SET, n: shoot["n"], model:, fingerprint:,
                                     id: prediction["id"], output_url:, seconds:)
  end
  preset = options[:draft] ? nil : preset_for(options[:grade], shoot["n"])
  grade(path, graded_dir, preset) if preset
  manifest = out_dir.join("prompts.jsonl")
  unless prompt_receipt_exists?(manifest, n: shoot["n"], prediction: prediction["id"])
    File.open(manifest, "a") do |log|
      log.puts JSON.generate(n: shoot["n"], title: shoot["title"], prompt:, model:, input: input.except(:prompt),
                             prediction: prediction["id"], predict_seconds: seconds,
                             grade: preset, rendered_at: Time.now.utc.iso8601)
    end
  end
  duration = seconds ? "#{seconds.round(1)} s" : "billed duration unavailable"
  puts "ok: #{path}#{preset ? " + #{preset}" : ""} (#{duration})"
  break if cost_inconclusive
end

[out_dir, graded_dir].each do |dir|
  next unless dir.directory?

  sheet = SUBJECT_DIR.join("..", "out", SUBJECT_DIR.basename.to_s, "#{dir.basename}_sheet.jpg")
  system("ruby", TOOLKIT.join("contact_sheet.rb").to_s, dir.to_s, "--cols", "4", "--cell", "384",
         "--label", "--out", sheet.to_s)
end
abort "warn: cost total inconclusive: #{cost_inconclusive_reason}; no further paid renders were sent" if cost_inconclusive

ledger_total_usd = Preflight.ledger_usd(LEDGER)
recorded_render_delta = Preflight.ledger_seconds(LEDGER, "render") - start_render_seconds
unrecorded_render_seconds = [observed_render_seconds - recorded_render_delta, 0.0].max
if unrecorded_render_seconds > 0.001
  warn format("warn: %.1f observed paid seconds are not in the ledger; cost below includes them, but receipt reconciliation is required",
              unrecorded_render_seconds)
end
known_unrecorded_usd = unrecorded_render_seconds * Preflight::RENDER_USD_PER_SECOND
puts format("ok: cost after: this run ~$%<run>.3f; subject known spend ~$%<all>.2f (ledger $%<ledger>.2f + %<unrecorded>.1f unrecorded observed seconds)",
            run: ledger_total_usd - start_usd + known_unrecorded_usd,
            all: ledger_total_usd + known_unrecorded_usd,
            ledger: ledger_total_usd, unrecorded: unrecorded_render_seconds)
abort "warn: #{failed} sitting(s) did not render" if failed.positive?
