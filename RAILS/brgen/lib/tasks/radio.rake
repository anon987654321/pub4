# frozen_string_literal: true

namespace :radio do
  desc "Download a Whyp collection with yt-dlp, build a seed manifest, and seed Radio"
  task import_whyp: :environment do
    collection = ENV["COLLECTION"].to_s.strip
    abort "radio: set COLLECTION=https://whyp.it/collections/..." if collection.empty?

    imported = Brgen::WhypRadioImporter.new(collection_url: collection).call
    cities = ENV.fetch("CITIES", Brgen::RadioWhypSeeder::DEFAULT_CITIES.join(",")).split(",")

    seeded = Brgen::RadioWhypSeeder.new(
      manifest_path: imported.manifest_path,
      cities: cities
    ).call

    puts "radio: imported tracks=#{imported.track_count} playlists=#{seeded.playlists} cities=#{seeded.cities.join(",")}"
    puts "radio: media=#{imported.audio_root}"
    puts "radio: manifest=#{imported.manifest_path}"
  end

# The operator's own whyp.it uploads, listed with their share tokens under
# external_reference.whyp in config/radio_bergen/tracks.yml: downloaded with
# yt-dlp (2026.08.19 or later; older builds cannot read whyp.it's pages),
# credited as that file names them, and seeded into each city's Radio.
desc "Download the operator's whyp.it tracks (tracks.yml) with yt-dlp and seed Radio"
task import_whyp_tracks: :environment do
  rows = Brgen::RadioBergenManifest.whyp_tracks
  abort "radio: tracks.yml lists no whyp tracks" if rows.empty?

  urls = rows.map { |row| "https://whyp.it/tracks/#{row[:whyp_id]}?token=#{row[:whyp_token]}" }
  credits = rows.to_h { |row| [ row[:whyp_id], row.slice(:title, :artist) ] }
  imported = Brgen::WhypRadioImporter.new(track_urls: urls, name: "radio-bergen-whyp", credits:).call
  cities = ENV.fetch("CITIES", Brgen::RadioWhypSeeder::DEFAULT_CITIES.join(",")).split(",")
  seeded = Brgen::RadioWhypSeeder.new(manifest_path: imported.manifest_path, cities:).call

  puts "radio: imported tracks=#{imported.track_count} playlists=#{seeded.playlists} cities=#{seeded.cities.join(",")}"
  puts "radio: missing on whyp.it (deleted or token changed): #{imported.missing.join(", ")}" if imported.missing.any?
  puts "radio: manifest=#{imported.manifest_path}"
end

  desc "Seed an existing generated Whyp manifest into Radio"
  task seed_whyp: :environment do
    manifest = ENV["MANIFEST"].to_s.strip
    abort "radio: set MANIFEST=RAILS/brgen/config/radio_whyp/<collection>.yml" if manifest.empty?

    cities = ENV.fetch("CITIES", Brgen::RadioWhypSeeder::DEFAULT_CITIES.join(",")).split(",")
    result = Brgen::RadioWhypSeeder.new(
      manifest_path: Rails.root.join(manifest),
      cities: cities
    ).call

    puts "radio: seeded tracks=#{result.tracks} playlists=#{result.playlists} cities=#{result.cities.join(",")}"
  end
end
