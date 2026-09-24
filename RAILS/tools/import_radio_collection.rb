#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "pathname"
require "time"
require "yaml"

RAILS_ROOT = Pathname(__dir__).join("brgen").expand_path
AUDIO_ROOT = RAILS_ROOT.join("public/audio/radio")
MANIFEST_PATH = RAILS_ROOT.join("config/radio/imported_tracks.yml")

def run_command(*args)
  stdout, stderr, status = Open3.capture3(*args)
  return stdout if status.success?

  detail = stderr.to_s.strip
  abort "radio-import: #{args.first} failed: #{detail.empty? ? "exit #{status.exitstatus}" : detail}"
end

def present_string(value)
  text = value.to_s.strip
  text.empty? ? nil : text
end

def json_command(*args)
  JSON.parse(run_command(*args))
rescue JSON::ParserError => e
  abort "radio-import: invalid JSON from #{args.first}: #{e.message}"
end

def whyp_track_urls(collection_url)
  stdout, stderr, status = Open3.capture3(
    "yt-dlp",
    "--flat-playlist",
    "--dump-single-json",
    "--skip-download",
    "--add-header",
    "Referer: https://whyp.it/",
    collection_url
  )

  if status.success?
    data = JSON.parse(stdout)
    urls = Array(data["entries"]).filter_map do |entry|
      next unless entry.is_a?(Hash)

      present_string(entry["webpage_url"]) ||
        present_string(entry["original_url"]) ||
        (entry["id"].to_s.match?(/\A\d+\z/) ? "https://whyp.it/tracks/#{entry['id']}" : nil)
    end
    return urls.uniq if urls.any?
  end

  html = run_command("curl", "-fsSL", "--max-time", "30", collection_url)
  absolute = html.scan(%r{https?://(?:www\.)?whyp\.it/tracks/\d+(?:/[A-Za-z0-9._~-]+)?}).uniq
  relative = html.scan(%r{["'](/tracks/\d+(?:/[A-Za-z0-9._~-]+)?)["']}).flatten.map { |path| "https://whyp.it#{path}" }
  (absolute + relative).uniq
rescue SystemCallError => e
  abort "radio-import: cannot inspect Whyp collection: #{e.message}"
end

def slug(text)
  ascii = text.to_s.unicode_normalize(:nfkd).encode(
    "ASCII",
    invalid: :replace,
    undef: :replace,
    replace: ""
  )
  ascii.downcase.gsub(/[^a-z0-9]+/, "-").sub(/\A-|-\z/, "").then { |value| value.presence || "track" }
end

def track_metadata(url)
  json_command(
    "yt-dlp",
    "--no-playlist",
    "--dump-single-json",
    "--skip-download",
    "--add-header",
    "Referer: https://whyp.it/",
    url
  )
end

def download_track(url, target)
  return if target.file?

  FileUtils.mkdir_p(target.dirname)
  run_command(
    "yt-dlp",
    "--no-playlist",
    "--extract-audio",
    "--audio-format",
    "mp3",
    "--audio-quality",
    "0",
    "--add-header",
    "Referer: https://whyp.it/",
    "--output",
    target.to_s,
    url
  )
end

collection_url = ARGV.fetch(0) { abort "radio-import: usage: ruby RAILS/tools/import_radio_collection.rb COLLECTION_URL" }
abort "radio-import: expected a Whyp collection URL" unless collection_url.match?(%r{\Ahttps?://(?:www\.)?whyp\.it/collections/})

urls = whyp_track_urls(collection_url)
abort "radio-import: no Whyp track URLs found in #{collection_url}" if urls.empty?

collection_slug = collection_url.split("/").last.to_s.gsub(/[^a-zA-Z0-9_-]+/, "-")
target_root = AUDIO_ROOT.join(collection_slug)
FileUtils.mkdir_p(target_root)

tracks = urls.each_with_index.map do |url, index|
  info = track_metadata(url)
  id = info["id"].to_s.presence || index.to_s
  title = present_string(info["title"]) || "Track ##{id}"
  artist = present_string(info["uploader"]) || present_string(info["artist"]) || "Unknown artist"
  filename = "#{id}-#{slug(title)}.mp3"
  target = target_root.join(filename)
  download_track(url, target)

  {
    "id" => id,
    "title" => title,
    "artist" => artist,
    "duration_seconds" => info["duration"].to_f.positive? ? info["duration"].to_f.round : nil,
    "source_url" => url,
    "local_path" => target.relative_path_from(RAILS_ROOT).to_s,
    "source_provider" => "whyp",
    "downloaded_by" => "yt-dlp"
  }.compact
end

FileUtils.mkdir_p(MANIFEST_PATH.dirname)
tmp = MANIFEST_PATH.sub_ext(".tmp")
File.write(
  tmp,
  YAML.dump(
    "source_collection" => collection_url,
    "imported_at" => Time.now.utc.iso8601,
    "tracks" => tracks
  )
)
File.rename(tmp, MANIFEST_PATH)

puts "radio-import: #{tracks.size} tracks -> #{MANIFEST_PATH}"
puts "radio-import: audio -> #{target_root}"
