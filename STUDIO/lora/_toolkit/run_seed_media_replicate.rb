#!/usr/bin/env ruby
# frozen_string_literal: true

# The paid lane for seed media: Replicate renders, postpro grades, and a
# manifest row records both.
#
#   ruby MASTER/tools/lora/_toolkit/run_seed_media_replicate.rb --out ~/seed_media
#   ruby MASTER/tools/lora/_toolkit/run_seed_media_replicate.rb --out ~/seed_media --only KEY,KEY --dry-run
#
# The Colab lane beside it is free and needs a GPU session and Drive; this one
# costs money per frame and needs only REPLICATE_API_TOKEN or REPLICATE_API_KEY
# (ReplicateClient also reads ~/.config/master/env). It reads seed_media.yml and
# writes the flat <key>.jpg layout install_seed_media.rb takes.
#
# No subject adapter is used. Every seeded person is a general-model stranger,
# because the seeds publish on public hosts.
#
# Every frame is asked for once. A render costs money and is never the same
# twice, so before a create this checks, in order: the file on disk, the
# manifest, and Replicate's own prediction list for the same model and prompt.
# A prediction found there is polled by id and downloaded, never resubmitted,
# and the create itself is one POST with no retry, because a retried POST that
# timed out on the way back is a second paid render.

require "digest"
require "fileutils"
require "json"
require "net/http"
require "optparse"
require "rbconfig"
require "time"
require "uri"
require "yaml"

ROOT = File.expand_path("../../..", __dir__)
require File.join(ROOT, "MASTER/lib/io/replicate_client")

SPEC = File.join(ROOT, "MASTER/tools/lora/seed_media.yml")
POSTPRO = File.join(ROOT, "MASTER/tools/postpro/postpro.rb")
BASE = Master::Io::ReplicateClient::BASE
# Published per-image prices, used only to state what a run cost. The
# prediction's own metrics carry time, not money, for these per-image models.
PRICE = { "black-forest-labs/flux-1.1-pro" => 0.04, "black-forest-labs/flux-schnell" => 0.003 }.freeze

options = { only: nil, limit: nil, dry_run: false, threads: 4, samples: nil }
OptionParser.new do |o|
  o.banner = "usage: run_seed_media_replicate.rb --out DIR [--only a,b] [--limit N] [--samples DIR] [--dry-run]"
  o.on("--out DIR") { |v| options[:out] = File.expand_path(v) }
  o.on("--only KEYS") { |v| options[:only] = v.split(",").map(&:strip) }
  o.on("--limit N", Integer) { |v| options[:limit] = v }
  o.on("--threads N", Integer) { |v| options[:threads] = v.clamp(1, 8) }
  o.on("--samples DIR", "Copy each graded frame here as it lands") { |v| options[:samples] = File.expand_path(v) }
  o.on("--dry-run") { options[:dry_run] = true }
end.parse!
abort "usage: --out DIR is required" unless options[:out]

spec = YAML.safe_load_file(SPEC)
model = spec.dig("meta", "replicate_model")

# One row per frame, whatever population it belongs to. The populations carry
# their preset and ratio at different depths, so they are flattened once here.
def rows_for(spec)
  meta, dating, amber = spec.values_at("meta", "dating", "amber")
  people = dating["profiles"].merge(dating["pool"] || {}).map do |key, prompt|
    { key:, prompt:, aspect_ratio: dating["aspect_ratio"], preset: dating["postpro"], group: "dating" }
  end
  scenes = spec["scenes"].map do |key, entry|
    { key:, prompt: entry["prompt"], aspect_ratio: entry["aspect_ratio"] || meta["aspect_ratio"],
      preset: entry["postpro"] || meta["postpro"], group: key.start_with?("listing-") ? "listing" : "scene" }
  end
  wardrobe = amber["garments"].merge(amber["outfits"] || {}).map do |key, garment|
    { key:, prompt: "#{garment}, #{spec['backdrop']}", aspect_ratio: amber["aspect_ratio"],
      preset: amber["postpro"], group: "amber" }
  end
  people + scenes + wardrobe
end

def preset_for(spec, key)
  return spec.dig("dating", "postpro") if key.start_with?("bergen-dating-", "dating-")
  return spec.dig("amber", "postpro") if key.start_with?("amber-")

  spec.dig("scenes", key, "postpro") || spec.dig("meta", "postpro")
end

def http(client, verb, path, body = nil)
  uri = URI(path.start_with?("http") ? path : "#{BASE}#{path}")
  req = verb == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  req["Authorization"] = "Token #{client.instance_variable_get(:@token)}"
  if body
    req["Content-Type"] = "application/json"
    req.body = body.to_json
  end
  client.send(:attempt_request, req, uri)
end

# Recent predictions keyed by model and prompt: the record of what was already
# paid for, whether or not this run's files survived.
def known_predictions(client, pages: 10)
  seen = {}
  url = "/predictions"
  pages.times do
    page = http(client, :get, url)
    Array(page["results"]).each do |pred|
      prompt = pred.dig("input", "prompt")
      next unless prompt
      next if %w[failed canceled].include?(pred["status"])

      seen[[pred["model"], prompt]] ||= pred
    end
    url = page["next"]
    break if url.to_s.empty?
  end
  seen
end

def await(client, pred)
  started = Time.now
  until %w[succeeded failed canceled].include?(pred["status"])
    raise "still #{pred['status']} after 600s: #{pred['id']}" if Time.now - started > 600

    sleep 2
    pred = http(client, :get, "/predictions/#{pred['id']}")
  end
  raise "#{pred['id']}: #{pred['status']} #{pred['error']}" unless pred["status"] == "succeeded"

  pred
end

# A throttled create is the one retry that cannot double-bill: a 429 means
# Replicate refused the request, so no prediction exists to duplicate. An
# account under five dollars of credit is held to one create at a time, and
# the refusal names the wait.
def create(client, version, input)
  8.times do
    return http(client, :post, "/predictions", { version:, input: })
  rescue StandardError => e
    raise unless e.message.include?("Replicate API 429") && e.message.include?("throttled")

    sleep(e.message[/"retry_after":(\d+)/, 1].to_i.clamp(2, 60) + 1)
  end
  raise "still throttled after eight waits"
end

def seed_for(key) = Digest::SHA256.hexdigest(key)[0, 8].to_i(16) % 2_000_000_000

rows = rows_for(spec).reject { |r| spec.fetch("adopted", {}).key?(r[:key]) }
adopted = spec.fetch("adopted", {}).map { |key, id| { key:, id:, preset: preset_for(spec, key), adopted: true } }
todo = adopted + rows
todo.select! { |r| options[:only].include?(r[:key]) } if options[:only]

raw_dir = File.join(options[:out], "raw")
graded_dir = File.join(options[:out], "graded")
manifest_path = File.join(options[:out], "manifest.yml")
manifest = File.file?(manifest_path) ? (YAML.safe_load_file(manifest_path) || {}) : {}
manifest["images"] ||= {}
todo.reject! { |r| File.exist?(File.join(raw_dir, "#{r[:key]}.jpg")) && manifest["images"].key?(r[:key]) }
todo = todo.first(options[:limit]) if options[:limit]

if options[:dry_run]
  todo.each { |r| puts format("%-36s %-9s %s", r[:key], r[:preset], r[:id] || r[:prompt][0, 70]) }
  fresh = todo.count { |r| !r[:adopted] }
  puts "#{todo.size} frame(s): #{fresh} new on #{model} (~$#{format('%.2f', fresh * PRICE.fetch(model, 0))}), " \
       "#{todo.size - fresh} adopted"
  exit 0
end

FileUtils.mkdir_p([raw_dir, graded_dir])
FileUtils.mkdir_p(options[:samples]) if options[:samples]
client = Master::Io::ReplicateClient.new
version = client.send(:latest_version, model)
known = known_predictions(client)
lock = Mutex.new
queue = Queue.new
todo.each { |r| queue << r }
failures = []
created = 0

workers = Array.new(options[:threads]) do
  Thread.new do
    while (row = begin queue.pop(true) rescue nil end)
      begin
        pred =
          if row[:adopted]
            http(client, :get, "/predictions/#{row[:id]}")
          elsif (found = lock.synchronize { known[[model, row[:prompt]]] })
            found
          elsif File.size?(File.join(raw_dir, "#{row[:key]}.jpg"))
            raise "on disk with no prediction on record; not rendering it again"
          else
            input = { prompt: row[:prompt], aspect_ratio: row[:aspect_ratio], seed: seed_for(row[:key]),
                      output_format: "jpg", output_quality: 95, safety_tolerance: 2, prompt_upsampling: false }
            made = create(client, version, input)
            lock.synchronize { known[[model, row[:prompt]]] = made; created += 1 }
            made
          end
        pred = await(client, pred)
        raw = File.join(raw_dir, "#{row[:key]}.jpg")
        client.download_url(Array(pred["output"]).first, raw) unless File.size?(raw)
        graded = File.join(graded_dir, "#{row[:key]}.jpg")
        ok = File.size?(graded) || (system(RbConfig.ruby, POSTPRO, "--input", raw, "--output", graded,
                                           "--preset", row[:preset], out: File::NULL, err: File::NULL) &&
                                    File.size?(graded))
        FileUtils.cp(graded, options[:samples]) if ok && options[:samples]
        lock.synchronize do
          manifest["images"][row[:key]] = {
            "group" => row[:group] || "adopted", "prompt" => pred.dig("input", "prompt"), "model" => pred["model"],
            "version" => pred["version"], "seed" => pred.dig("input", "seed"),
            "aspect_ratio" => pred.dig("input", "aspect_ratio"), "postpro" => ok ? row[:preset] : nil,
            "prediction" => pred["id"], "predict_time" => pred.dig("metrics", "predict_time"),
            "price_usd" => PRICE[pred["model"]], "created_at" => pred["created_at"],
          }
          File.write(manifest_path, manifest.to_yaml)
          puts format("ok %-36s %-30s %s", row[:key], pred["model"], ok ? row[:preset] : "UNGRADED")
        end
      rescue StandardError => e
        lock.synchronize { failures << row[:key]; warn "fail #{row[:key]}: #{e.message[0, 300]}" }
      end
    end
  end
end
workers.each(&:join)

spend = manifest["images"].values.sum { |m| m["price_usd"].to_f }
puts "#{todo.size - failures.size} done, #{created} created this run, #{failures.size} failed" \
     "#{failures.empty? ? '' : ": #{failures.join(', ')}"}"
puts "manifest: #{manifest['images'].size} images, $#{format('%.3f', spend)} at published prices"
exit(failures.empty? ? 0 : 1)
