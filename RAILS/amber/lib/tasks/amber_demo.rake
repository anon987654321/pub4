# frozen_string_literal: true

namespace :amber do
  desc "Seed credible demo capsule wardrobe (idempotent; safe on production)"
  task demo_seed: :environment do
    Amber::AmberDemoSeeder.new.seed!
    puts "ok items=#{Amber::DemoWardrobe.items.count} outfits=#{Amber::DemoWardrobe.outfits.count}"
  end
end