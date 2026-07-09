# frozen_string_literal: true

namespace :brgen do
  desc "Seed credible Bergen demo content (idempotent; safe on production)"
  task demo_seed: :environment do
    bergen = City.find_by(domain: "brgen.no") or abort("brgen.no city missing")
    Brgen::BergenDemoSeeder.new(bergen).seed!
    playlist = Playlist::Playlist.find_by(city: bergen, name: Brgen::BergenDemoSeeder::RADIO_BERGEN_PLAYLIST)
    puts "ok posts=#{Post.where(city: bergen).count} playlist_tracks=#{playlist&.tracks&.count}"
  end
end