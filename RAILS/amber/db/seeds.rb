# frozen_string_literal: true
# Production: credible demo capsule only. Dev/test: Faker flood for local work.

if Rails.env.production?
  Amber::AmberDemoSeeder.new.seed!
  puts "ok demo items=#{Amber::DemoWardrobe.items.count} outfits=#{Amber::DemoWardrobe.outfits.count}"
  exit 0
end

require "faker"

puts "Seeding Amber with female fashion fictive data..."

seed_job_adapter = ActiveJob::Base.queue_adapter
ActiveJob::Base.queue_adapter = :inline

was_strict = ApplicationRecord.strict_loading_by_default
ApplicationRecord.strict_loading_by_default = false

scale = (ENV['SEED_SCALE'] || (Rails.env.production? ? 1 : 5)).to_i.clamp(1, 50)

if Rails.env.development? || Rails.env.test?
  User.destroy_all
  Item.destroy_all
  Outfit.destroy_all
  Post.destroy_all
end

num_users = (20 * scale).clamp(5, 500)
users = num_users.times.map do
  User.strict_loading(false).create!(
    email_address: Amber::FashionFaker.user_email,
    password: "password123",
    password_confirmation: "password123"
  ).tap do |user|
    profile = user.profile || user.create_profile!
    profile.update!(display_name: Amber::FashionFaker.user_display_name) if profile.display_name.blank?
  end
end

puts "Created #{users.size} users"

items = users.flat_map do |user|
  (8 * scale).clamp(2, 20).times.map do
    attrs = Amber::FashionFaker.item_attributes
    Item.create!(attrs.merge(user: user))
  end
end

puts "Created #{items.size} wardrobe items"

outfits = users.flat_map do |user|
  (3 * scale).clamp(1, 10).times.map do
    outfit_items = user.items.sample(rand(3..5))
    outfit = Outfit.create!(
      user: user,
      name: Amber::FashionFaker.outfit_name,
      description: Amber::FashionFaker.outfit_description,
      occasion: Item::OCCASIONS.sample,
      season: Item::SEASONS.sample
    )
    outfit_items.each { |item| outfit.outfit_items.create!(item: item) }
    outfit
  end
end

puts "Created #{outfits.size} outfits"

posts = users.flat_map do |user|
  (5 * scale).clamp(1, 20).times.map do
    Post.create!(
      user: user,
      body: Amber::FashionFaker.post_body,
      outfit: user.outfits.sample,
      item: user.items.sample,
      likes_count: rand(10 * scale..5000 * scale)
    )
  end
end

puts "Created #{posts.size} posts"

posts.sample(30 * scale).each do |post|
  liker = users.sample
  post.reactions.create!(user: liker, kind: %w[like love].sample) if post.respond_to?(:reactions)
end

puts "Seeded Amber fictive data successfully."
puts "Users: #{User.count}, Items: #{Item.count}, Outfits: #{Outfit.count}, Posts: #{Post.count}"

ApplicationRecord.strict_loading_by_default = was_strict
ActiveJob::Base.queue_adapter = seed_job_adapter

if ENV["SEED_FROM_WEB"] && ENV["OPENROUTER_API_KEY"]
  puts "\nAugmenting Amber with web-scraped fashion data via Ferrum..."
  begin
    Rake::Task["scrape:fashion_seed"].invoke
  rescue => e
    puts "  fashion_seed skipped: #{e.message}"
  end
  puts "  (Creates Items, Outfits, Posts from Reddit fashion subs like femalefashionadvice.)"
end