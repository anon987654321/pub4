# frozen_string_literal: true

namespace :brgen do
  desc "Seed simulated Bergen content in development/test or a disclosed demo host"
  task demo_seed: :environment do
    unless Brgen::DemoMode.seed_allowed?
      abort "Refusing synthetic seed: use development/test or an explicitly disclosed demo deployment"
    end

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

  desc "Read-only audit of historical synthetic seed accounts and linked content"
  task demo_audit: :environment do
    handles = Brgen::BergenDemoSeeder::USERS.map(&:last)
    candidates = User.where(username: handles)
                     .or(User.where("LOWER(email_address) LIKE ?", "seed%@%"))
    user_ids = candidates.distinct.pluck(:id)

    puts "candidate synthetic identities: #{user_ids.size}"
    puts "candidate usernames: #{candidates.order(:username).distinct.pluck(:username).join(', ')}"
    puts "posts: #{Post.where(user_id: user_ids).count}"
    puts "comments: #{Comment.where(user_id: user_ids).count}"

    if defined?(Dating::Profile) && Dating::Profile.table_exists?
      puts "dating profiles: #{Dating::Profile.where(user_id: user_ids).count}"
    end

    if defined?(Marketplace::Listing) && Marketplace::Listing.table_exists?
      listings = Marketplace::Listing.where(user_id: user_ids)
      puts "listings: #{listings.count}"
      if listings.column_names.include?("views_count")
        puts "listings with nonzero view counts: #{listings.where.not(views_count: 0).count}"
      end
    end

    if defined?(Playlist::Playlist) && Playlist::Playlist.table_exists?
      playlists = Playlist::Playlist.where(user_id: user_ids)
      puts "playlists: #{playlists.count}"
      puts "playlists with historical 428 play count: #{playlists.where(plays_count: 428).count}"
    end

    puts "READ ONLY: matches are candidates, not proof. No records were changed."
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
