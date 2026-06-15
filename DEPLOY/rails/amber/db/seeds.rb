# frozen_string_literal: true
# Fictive seed data for Amber using ruby-faker.
# Run with: bin/rails db:seed (or db:setup, db:seed:replant in test/ci)

require "faker"

puts "Seeding Amber with fictive data..."

# Clear existing for idempotency in dev (use find_or_create in prod-like)
User.destroy_all
Item.destroy_all
Outfit.destroy_all
Post.destroy_all

# Create users
users = 20.times.map do
  User.create!(
    email_address: Faker::Internet.unique.email,
    password: "password123",
    password_confirmation: "password123"
  )
end

puts "Created #{users.size} users"

# Create wardrobe items (clothing, accessories)
categories = %w[shirt pants jacket shoes dress coat sweater accessory hat]
colors = %w[black navy white gray beige olive burgundy teal mustard]
brands = %w[Acne Arket COS Uniqlo Zara H&M Everlane Patagonia]

items = users.flat_map do |user|
  8.times.map do
    Item.create!(
      user: user,
      title: "#{Faker::Commerce.product_name} #{Faker::Color.color_name}",
      category: categories.sample,
      color: colors.sample,
      brand: brands.sample,
      size: %w[XS S M L XL].sample,
      price_cents: rand(1500..15000),
      description: Faker::Lorem.sentence(word_count: 12),
      worn_count: rand(0..25),
      last_worn_at: rand(1..90).days.ago
    )
  end
end

puts "Created #{items.size} wardrobe items"

# Create outfits (capsules, looks)
outfits = users.flat_map do |user|
  3.times.map do
    outfit_items = user.items.sample(rand(3..6))
    Outfit.create!(
      user: user,
      name: Faker::Commerce.product_name + " Look",
      description: Faker::Lorem.paragraph(sentence_count: 2),
      context_label: %w[casual work date travel party].sample,
      items: outfit_items,
      estimated_value: outfit_items.sum(&:price_cents),
      total_wears: rand(0..15),
      last_worn_at: rand(1..60).days.ago
    )
  end
end

puts "Created #{outfits.size} outfits"

# Create social posts (style shares, declutter thoughts)
posts = users.flat_map do |user|
  5.times.map do
    Post.create!(
      user: user,
      body: Faker::Lorem.paragraph(sentence_count: 3) + " #style #wardrobe",
      outfit: user.outfits.sample,
      item: user.items.sample,
      likes_count: rand(0..42)
    )
  end
end

puts "Created #{posts.size} posts"

# Some reactions/likes on posts (using shared concern if wired)
posts.sample(30).each do |post|
  liker = users.sample
  # Simulate reaction (model may use shared Reactable)
  post.reactions.create!(user: liker, kind: %w[like love].sample) if post.respond_to?(:reactions)
end

puts "Seeded Amber fictive data successfully."
puts "Users: #{User.count}, Items: #{Item.count}, Outfits: #{Outfit.count}, Posts: #{Post.count}"

# Optional web-augmented fictive seeds using Ferrum (see lib/tasks/fashion.rake)
# Requires OPENROUTER_API_KEY. Supplements with real fashion inspiration from Reddit.
# Usage: SEED_FROM_WEB=1 OPENROUTER_API_KEY=... bin/rails db:seed
if ENV['SEED_FROM_WEB'] && ENV['OPENROUTER_API_KEY']
  puts "\nAugmenting Amber with web-scraped fashion data via Ferrum..."
  begin
    Rake::Task['scrape:fashion_seed'].invoke
  rescue => e
    puts "  fashion_seed skipped: #{e.message}"
  end
  puts "  (Creates Items, Outfits, Posts from Reddit fashion subs like malefashion, streetwear.)"
end