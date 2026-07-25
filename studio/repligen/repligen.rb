#!/usr/bin/env ruby
# frozen_string_literal: true
# frozen_string_literal: true

# Small, non-interactive Replicate image entrypoint. Credentials stay in env/user config.
require "optparse"
require "fileutils"
require "json"
require "time"
require "digest"
require "securerandom"
require_relative "../lib/io/replicate_client"
require_relative "../lib/io/script_dispatch"
require_relative "../lib/io/analog_capabilities"
require_relative "../lib/master_paths"

# Structured fields compose onto the free-text --prompt; each is optional and
# only known vocabulary keys take effect, so an unrecognized value is a no-op
# rather than a crash.
STOCK_VOCAB = {
  "portra" => "Kodak Portra 400 color negative scan, fine grain, gentle highlight rolloff",
  "gold" => "Kodak Gold 200 warm consumer color, soft contrast",
  "trix" => "Kodak Tri-X 400 black and white, silver-rich contrast, visible grain",
  "provia" => "Fujifilm Provia 100F, neutral saturated color, clean shadows",
  "cinestill" => "CineStill 800T tungsten-balanced, halation around highlights",
}.freeze

LENS_VOCAB = {
  "35mm" => "35mm lens, moderate depth of field, slight environmental context",
  "50mm" => "50mm lens, natural perspective, shallow depth of field",
  "85mm" => "85mm portrait lens, compressed background, creamy bokeh",
  "medium_format" => "medium-format Hasselblad look, high resolution tonal smoothness",
}.freeze

CAMERA_HEIGHT_VOCAB = {
  "eye" => "eye-level camera height",
  "low" => "low camera angle looking slightly up",
  "high" => "elevated camera angle looking slightly down",
  "overhead" => "overhead camera angle",
}.freeze

DISTANCE_VOCAB = {
  "closeup" => "tight close-up crop, face fills frame",
  "portrait" => "head-and-shoulders portrait crop",
  "half" => "half-body framing",
  "full" => "full-body framing",
  "wide" => "wide environmental framing, subject small in frame",
}.freeze

LIGHTING_VOCAB = {
  "soft" => "soft diffused key light, low contrast falloff",
  "hard" => "hard direct key light, defined shadow edges",
  "backlit" => "backlit rim light, subject silhouetted against source",
  "window" => "window light from camera-left, natural falloff",
  "golden_hour" => "warm low-angle golden-hour sunlight",
}.freeze

WEATHER_VOCAB = {
  "rain" => "Bergen rain, wet pavement reflections, overcast diffusion",
  "fog" => "coastal fog, desaturated distance, soft contrast",
  "clear" => "clear Nordic sky, crisp daylight",
  "snow" => "winter light off snow, cool color temperature",
}.freeze

TIME_OF_DAY_VOCAB = {
  "dawn" => "pale dawn light, low saturation, cool blue shadows",
  "midday" => "neutral midday light, even exposure",
  "golden_hour" => "golden-hour warmth, long soft shadows",
  "blue_hour" => "blue-hour ambient light, deep shadow tones",
  "night" => "practical night lighting, mixed color temperature",
}.freeze

PLASTIC_SKIN_NEGATIVE = "plastic skin, waxy face, over-smoothed, airbrushed, doll, uncanny, beauty filter, " \
  "heavy makeup, face morph, identity drift, CGI, illustration, anime"
ANTI_BEAUTIFICATION_NEGATIVE = "generic influencer face, overly young face, teenage face, symmetrical idealized " \
  "face, filler lips, filter smoothing"

# Cycled per batch index rather than sampled, so a requested batch fills its
# diversity quota deterministically instead of risking repeats by chance.
EXPRESSION_POOL = [
  "a calm neutral expression", "a slight natural smile", "a direct steady gaze",
  "mid-laugh candid expression", "a thoughtful downward glance"
].freeze
POSE_POOL = [
  "facing camera directly", "three-quarter turn", "profile turn",
  "looking over one shoulder", "leaning slightly forward"
].freeze
WARDROBE_POOL = ["wool coat", "simple knit sweater", "plain white shirt", "denim jacket", "dark turtleneck"].freeze
BACKGROUND_POOL = ["plain studio backdrop", "fjord shoreline", "Bergen street corner", "cafe window", "mountain road"].freeze

# What each Replicate model actually accepts. An unknown model falls back to
# the conservative default rather than failing closed.
MODEL_CAPABILITIES = {
  "black-forest-labs/flux-1.1-pro" => { input_keys: %w[prompt aspect_ratio output_format safety_tolerance seed], negative_prompt_key: nil },
  "black-forest-labs/flux-dev" => { input_keys: %w[prompt aspect_ratio output_format seed guidance num_inference_steps], negative_prompt_key: nil },
  "black-forest-labs/flux-schnell" => { input_keys: %w[prompt aspect_ratio output_format seed num_inference_steps], negative_prompt_key: nil },
  "stability-ai/stable-diffusion-3.5-large" => { input_keys: %w[prompt negative_prompt aspect_ratio output_format seed cfg_scale], negative_prompt_key: "negative_prompt" },
}.freeze
DEFAULT_CAPABILITY = { input_keys: %w[prompt aspect_ratio output_format seed], negative_prompt_key: nil }.freeze

PREVIEW_MODEL = "black-forest-labs/flux-schnell"

def capability_for(model_id)
  MODEL_CAPABILITIES[model_id] || DEFAULT_CAPABILITY
end

def compile_prompt(base_prompt, options)
  segments = [base_prompt]
  segments << STOCK_VOCAB[options[:stock]]
  segments << LENS_VOCAB[options[:lens]]
  segments << CAMERA_HEIGHT_VOCAB[options[:camera_height]]
  segments << DISTANCE_VOCAB[options[:distance]]
  segments << LIGHTING_VOCAB[options[:lighting]]
  segments << WEATHER_VOCAB[options[:weather]]
  segments << TIME_OF_DAY_VOCAB[options[:time_of_day]]
  segments.compact.join(", ")
end

def compile_negative_prompt(options)
  return options[:negative] if options[:negative]
  return if options[:no_negative]

  parts = [PLASTIC_SKIN_NEGATIVE]
  parts << ANTI_BEAUTIFICATION_NEGATIVE unless options[:allow_beautify]
  parts.join(", ")
end

def infer_aspect_ratio(prompt, explicit)
  return explicit if explicit

  case prompt
  when /\bportrait\b|\bheadshot\b|\bclose[- ]?up\b/i then "4:5"
  when /\blandscape\b|\bwide\b|\bpanoram/i then "16:9"
  when /\bsquare\b|\bavatar\b/i then "1:1"
  else "3:2" # editorial default
  end
end

def diversify(prompt, index, batch_size)
  return prompt if batch_size <= 1

  parts = [
    EXPRESSION_POOL[index % EXPRESSION_POOL.length],
    POSE_POOL[index % POSE_POOL.length],
    WARDROBE_POOL[index % WARDROBE_POOL.length],
    BACKGROUND_POOL[index % BACKGROUND_POOL.length],
  ]
  "#{prompt}, #{parts.join(', ')}"
end

def build_input(prompt, options, seed:, negative_prompt:)
  cap = capability_for(options[:model])
  full = {
    prompt:,
    aspect_ratio: options[:aspect_ratio],
    output_format: "webp",
    safety_tolerance: 2,
    seed:,
    negative_prompt:,
    guidance: options[:guidance],
    num_inference_steps: options[:steps],
    cfg_scale: options[:cfg_scale],
  }.compact
  if cap[:negative_prompt_key] && full.key?(:negative_prompt)
    full[cap[:negative_prompt_key].to_sym] = full.delete(:negative_prompt)
  end
  full.select { |key, _| cap[:input_keys].include?(key.to_s) }
end

def alt_text_for(prompt)
  prompt.gsub(/,\s*/, ", ").strip[0, 240]
end

# Content-addressed so repeated downloads of the same output collapse to one
# blob; the sidecar records everything needed to reproduce or audit the call.
def cache_blob(path, cache_dir)
  digest = Master::Io::ReplicateClient.checksum(path)
  FileUtils.mkdir_p(cache_dir)
  blob_path = File.join(cache_dir, "#{digest}#{File.extname(path)}")
  FileUtils.cp(path, blob_path) unless File.exist?(blob_path)
  [digest, blob_path]
end

def write_provenance(output, prompt, compiled_prompt, negative_prompt, options, seed, digest)
  sidecar = { output: }.merge(
    prompt:,
    compiled_prompt:,
    negative_prompt:,
    model: options[:model],
    aspect_ratio: options[:aspect_ratio],
    seed:,
    sha256: digest,
    generated_at: Time.now.utc.iso8601,
  )
  File.write("#{output}.json", JSON.pretty_generate(sidecar))
  sidecar
end

def append_gallery_manifest(sidecar, alt_text)
  manifest = File.join(MasterPaths.repo, ".master", "media", "gallery.jsonl")
  FileUtils.mkdir_p(File.dirname(manifest))
  File.open(manifest, "a") { |f| f.puts(sidecar.merge(alt_text:).to_json) }
end

def maybe_handoff_postpro(output, preset)
  return output unless preset

  result = Master::Io::ScriptDispatch.run(
    root: MasterPaths.root,
    tool: "postpro",
    arg: ["--input", output, "--output", output, "--preset", preset].map { |v| Shellwords.escape(v) }.join(" "),
  )
  result.ok? ? output : (abort "warn: postpro handoff failed: #{result.message}")
end

cache = File.expand_path(ENV.fetch("REPLIGEN_CATALOG", "~/.cache/repligen/models.json"))
blob_cache_dir = File.expand_path(ENV.fetch("REPLIGEN_BLOB_CACHE", "~/.cache/repligen/blobs"))
options = { model: ENV.fetch("REPLIGEN_MODEL", "black-forest-labs/flux-1.1-pro"), aspect_ratio: nil, limit: 100, dry_run: false, batch: 1 }
parser = OptionParser.new do |p|
  p.banner = "Usage: repligen.rb generate|search|sync|stats|capabilities [options]"
  p.on("--prompt TEXT") { |v| options[:prompt] = v }
  p.on("--model MODEL") { |v| options[:model] = v; options[:model_explicit] = true }
  p.on("--aspect-ratio RATIO") { |v| options[:aspect_ratio] = v }
  p.on("--output FILE") { |v| options[:output] = File.expand_path(v) }
  p.on("--limit N", Integer) { |v| options[:limit] = v.clamp(1, 1_000) }
  p.on("--dry-run") { options[:dry_run] = true }
  p.on("--stock NAME") { |v| options[:stock] = v }
  p.on("--lens NAME") { |v| options[:lens] = v }
  p.on("--camera-height NAME") { |v| options[:camera_height] = v }
  p.on("--distance NAME") { |v| options[:distance] = v }
  p.on("--lighting NAME") { |v| options[:lighting] = v }
  p.on("--weather NAME") { |v| options[:weather] = v }
  p.on("--time-of-day NAME") { |v| options[:time_of_day] = v }
  p.on("--negative TEXT") { |v| options[:negative] = v }
  p.on("--no-negative") { options[:no_negative] = true }
  p.on("--allow-beautify") { options[:allow_beautify] = true }
  p.on("--batch N", Integer) { |v| options[:batch] = v.clamp(1, 20) }
  p.on("--seed N", Integer) { |v| options[:seed] = v }
  p.on("--preview") { options[:preview] = true }
  p.on("--final") { options[:final] = true }
  p.on("--postpro PRESET") { |v| options[:postpro] = v }
end
command = ARGV.shift || "help"
parser.parse!(ARGV)
if command == "help"
  puts parser
  exit 0
end
case command
when "capabilities"
  puts Master::Io::AnalogCapabilities.report(:repligen)
when "generate"
  abort parser.to_s if options[:prompt].to_s.strip.empty?
  options[:model] = PREVIEW_MODEL if options[:preview] && !ENV.key?("REPLIGEN_MODEL") && !options[:model_explicit]
  options[:aspect_ratio] = infer_aspect_ratio(options[:prompt], options[:aspect_ratio])
  client = options[:dry_run] ? nil : Master::Io::ReplicateClient.new

  outputs = (0...options[:batch]).map do |index|
    compiled = compile_prompt(options[:prompt], options)
    varied = diversify(compiled, index, options[:batch])
    seed = options[:seed] ? options[:seed] + index : SecureRandom.random_number(2**31)
    negative_prompt = compile_negative_prompt(options)
    input = build_input(varied, options, seed:, negative_prompt:)

    if options[:dry_run]
      puts "ok: repligen dry-run model=#{options[:model]} input=#{input.inspect}"
      next nil
    end

    urls = Array(client.predict(options[:model], input)).flatten.compact
    abort "warn: repligen returned no output" if urls.empty?

    target = if options[:output]
               options[:batch] > 1 ? options[:output].sub(/(\.\w+)?\z/) { |ext| "-#{index}#{ext}" } : options[:output]
             end

    unless target
      puts "ok: repligen generated\n#{urls.join("\n")}"
      next nil
    end

    FileUtils.mkdir_p(File.dirname(target))
    client.download_url(urls.first, target)
    digest, = cache_blob(target, blob_cache_dir)
    sidecar = write_provenance(target, options[:prompt], varied, negative_prompt, options, seed, digest)
    append_gallery_manifest(sidecar, alt_text_for(varied))
    maybe_handoff_postpro(target, options[:postpro])
    puts "ok: repligen generated #{target}"
    target
  end.compact

  outputs
when "search"
  query = ARGV.join(" ").strip
  abort "usage: repligen.rb search QUERY [--limit N]" if query.empty?
  rows = Master::Io::ReplicateClient.new.models(limit: options[:limit], query:)
  puts rows.map { |row| "#{row['owner']}/#{row['name']}\t#{row['description'].to_s.gsub(/\s+/, ' ')[0, 120]}" }
when "sync"
  rows = Master::Io::ReplicateClient.new.models(limit: options[:limit])
  FileUtils.mkdir_p(File.dirname(cache))
  File.write(cache, JSON.pretty_generate({ synced_at: Time.now.utc.iso8601, models: rows }))
  puts "ok: repligen synced #{rows.length} models to #{cache}"
when "stats"
  data = File.file?(cache) ? JSON.parse(File.read(cache)) : { "models" => [] }
  models = Array(data["models"])
  owners = models.group_by { |row| row["owner"] }.sort_by { |_, rows| -rows.length }.first(10)
  puts "catalog: #{models.length} models (#{data['synced_at'] || 'not synced'})"
  owners.each { |owner, rows| puts "#{owner}: #{rows.length}" }
else
  abort parser.to_s
end
