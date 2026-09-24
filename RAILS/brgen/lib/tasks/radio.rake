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
