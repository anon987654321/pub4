# frozen_string_literal: true

namespace :brgen do
  desc "Seed credible Bergen demo content (idempotent; safe on production)"
  task demo_seed: :environment do
    bergen = City.find_by(domain: "brgen.no") or abort("brgen.no city missing")
    Brgen::BergenDemoSeeder.new(bergen).seed!
    ActsAsTenant.with_tenant(bergen) do
      playlist = Playlist::Playlist.find_by(city: bergen, name: Brgen::BergenDemoSeeder::RADIO_BERGEN_PLAYLIST)
      place_count = Place.table_exists? ? Place.where(city: bergen).count : 0
      puts "ok posts=#{Post.where(city: bergen).count} places=#{place_count} " \
           "restaurants=#{Takeaway::Restaurant.count} tv_channels=#{Tv::Channel.count} " \
           "playlist_tracks=#{playlist&.tracks&.count}"
    end
  end

  namespace :demo_media do
    desc "Verify Bergen demo media catalog URLs (HTTP 200)"
    task verify: :environment do
      require "yaml"
      require "open-uri"

      catalog = Brgen::DemoMedia::CATALOG
      abort("catalog missing: #{catalog}") unless catalog.file?

      data = YAML.safe_load_file(catalog, permitted_classes: [], aliases: true) || {}
      images = data.fetch("images", {})
      failures = []

      images.each do |seed, entry|
        url = entry.is_a?(Hash) ? entry["url"] : entry
        next if url.to_s.empty?

        begin
          sleep 0.35
          status = URI.open(
            url,
            read_timeout: 10,
            open_timeout: 10,
            "User-Agent" => ENV.fetch("DEMO_MEDIA_USER_AGENT", "BrgenDemoSeed/1.0 (+https://brgen.no; demo verify)")
          ) { |io| io.status[0] } # rubocop:disable Security/Open
          failures << "#{seed}: HTTP #{status}" unless status == "200"
        rescue StandardError => error
          failures << "#{seed}: #{error.class} #{error.message}"
        end
      end

      if failures.any?
        warn "demo_media verify: #{failures.size}/#{images.size} failed"
        failures.each { |line| warn "  #{line}" }
        abort("demo_media catalog has broken URLs")
      end

      puts "ok #{images.size} bergen demo images reachable"
    end
  end
end
