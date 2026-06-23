# frozen_string_literal: true
# Comprehensive fictive seed data for Brgen + all subapps using ruby-faker.
# Seeds core + marketplace, dating, playlist, takeaway, tv, maps, messages.
# Idempotent with find_or_create_by! where possible. Run: bin/rails db:seed

require "faker"

# Ensure Cities exist for automatic TLD/domain-based resolution (no city switcher).
# Each city domain is an isolated experience.
if defined?(Brgen::CitySeed) && ActiveRecord::Base.connection.table_exists?(:cities)
  Brgen::CitySeed.sync!
end

puts "Seeding Brgen (core + subapps) with rich fictive data..."

if Rails.env.development? || Rails.env.test?
  # Cleanup for dev replant only — never wipe production data.
  Faker::UniqueGenerator.clear
  keep = %w[schema_migrations ar_internal_metadata cities]
  conn = ActiveRecord::Base.connection
  conn.disable_referential_integrity do
    conn.tables.each do |table|
      next if keep.include?(table)
      conn.execute("DELETE FROM #{conn.quote_table_name(table)}")
    end
  end
end

# --- Core: Users, Communities, Posts ---
admin = User.find_or_create_by!(email_address: "admin@brgen.no") do |u|
  u.username = "admin"
  u.password = u.password_confirmation = "password123"
end

users = 50.times.map do |i|
  User.create!(
    email_address: "seed#{i}@#{Faker::Internet.domain_name}",
    password: "password123",
    password_confirmation: "password123",
    username: "seed#{i}_#{Faker::Internet.username(specifier: 3..8)}",
    latitude: 60.39 + rand(-0.1..0.1),
    longitude: 5.33 + rand(-0.1..0.1)
  )
end

puts "Created #{users.size + 1} users (incl admin)"

communities = %w[news tech bergen norge kultur food music film].map do |slug|
  Community.find_or_create_by!(slug: slug) do |c|
    c.name = slug.capitalize
    c.description = "#{slug.capitalize} community for #{Faker::Address.city}"
    c.user = admin
  end
end

# Core posts + activity
posts = users.sample(30).flat_map do |user|
  4.times.map do
    Post.create!(
      user: user,
      community: communities.sample,
      title: Faker::Lorem.sentence(word_count: 5),
      content: Faker::Lorem.paragraph(sentence_count: 4),
      created_at: rand(1..90).days.ago
    )
  end
end

posts.each do |post|
  voter = users.sample
  post.reactions.find_or_create_by!(user: voter, kind: %w[like love].sample)
  post.votes.find_or_create_by!(user: users.sample) { |v| v.value = [1, -1].sample }
end

puts "Created #{posts.size} posts + reactions"

# --- Marketplace subapp ---
categories = {
  "electronics" => %w[phones computers audio gaming],
  "clothing" => %w[shirts trousers shoes outerwear],
  "furniture" => %w[sofas tables chairs storage],
  "vehicles" => %w[cars bikes motorcycles parts],
  "services" => %w[repair moving cleaning tutoring]
}

categories.each do |root_name, children|
  root = Marketplace::Category.find_or_create_by!(name: root_name.titleize, slug: root_name)
  children.each do |child_name|
    Marketplace::Category.find_or_create_by!(
      name: child_name.titleize,
      slug: "#{root_name}-#{child_name}",
      parent: root
    )
  end
end

stores = 12.times.map do |i|
  name = Faker::Company.name
  Marketplace::Store.create!(
    owner: users.sample,
    name: name,
    slug: "seed-store-#{i}-#{Faker::Internet.slug}",
    description: Faker::Company.catch_phrase,
    vertical: Marketplace::Store::VERTICALS.sample
  )
end

listings = stores.flat_map do |store|
  5.times.map do
    Marketplace::Listing.create!(
      user: store.owner,
      store: store,
      title: Faker::Commerce.product_name,
      description: Faker::Lorem.paragraph,
      price_cents: rand(1000..50_000),
      category: Marketplace::Category.all.sample,
      location: Faker::Address.city,
      status: "active",
      created_at: rand(1..60).days.ago
    )
  end
end

# Some orders
listings.sample(20).each do |listing|
  buyer = users.sample
  order = Marketplace::Order.create!(
    buyer: buyer,
    listing: listing,
    status: %w[pending accepted completed].sample,
    message: Faker::Lorem.sentence,
    created_at: rand(1..30).days.ago
  )
  order.record_activity!("MarketplaceOrder") if order.respond_to?(:record_activity!)
end

puts "Marketplace: #{stores.size} stores, #{listings.size} listings, some orders"

# --- Dating subapp ---
dating_profiles = users.sample(35).map do |user|
  Dating::Profile.create!(
    user: user,
    bio: Faker::Lorem.paragraph(sentence_count: 3),
    age: rand(22..45),
    gender: Dating::Profile::GENDERS.sample,
    looking_for: Dating::Profile::LOOKING_FOR.sample,
    latitude: user.latitude,
    longitude: user.longitude,
    bydel: %w[Sentrum Nordnes Sandviken Kalfaret].sample,
    visible: true
  )
end

dating_profiles.each_cons(2) do |a, b|
  Dating::Like.find_or_create_by!(liker: a.user, likee: b.user)
end

puts "Dating: #{dating_profiles.size} profiles, #{Dating::Like.count} likes, #{Dating::Match.count} matches"

# --- Playlist subapp ---
playlists = users.sample(15).map do |user|
  Playlist::Playlist.create!(
    user: user,
    name: "#{Faker::Music.genre} #{Faker::Music.album}",
    description: Faker::Lorem.sentence,
    tracks_count: rand(5..25),
    plays_count: rand(10..500),
    collaborative: [true, false].sample
  )
end

tracks = 40.times.map do
  Playlist::Track.create!(
    title: "#{Faker::Music.genre} #{Faker::Lorem.words(number: 2).join(' ')}",
    artist: Faker::Music::RockBand.name,
    duration_seconds: rand(120..300),
    source_type: "upload"
  )
end

playlists.each do |pl|
  tracks.sample(rand(4..8)).each do |track|
    pl.add_track!(track, user: users.sample)
  end
end

sets = users.sample(8).map do |user|
  Playlist::Set.create!(
    user: user,
    name: "Set #{Faker::Number.number(digits: 2)}",
    privacy: %w[public private unlisted].sample
  )
end

puts "Playlist: #{playlists.size} playlists, tracks, sets"

# --- Takeaway subapp ---
cuisines = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza Burger Kebab]
restaurants = 15.times.map do
  Takeaway::Restaurant.create!(
    user: users.sample,
    name: Faker::Restaurant.name,
    cuisine_type: cuisines.sample,
    address: Faker::Address.street_address,
    city: "Bergen",
    delivery_fee_cents: rand(2000..6000),
    min_order_cents: rand(8000..15000),
    latitude: 60.39 + rand(-0.04..0.04),
    longitude: 5.33 + rand(-0.04..0.04)
  )
end

restaurants.each do |rest|
  rand(6..12).times do
    Takeaway::MenuItem.create!(
      restaurant: rest,
      name: Faker::Food.dish,
      description: Faker::Food.description,
      price_cents: rand(6000..18000)
    )
  end
end

# Orders + reviews
restaurants.sample(10).each do |rest|
  buyer = users.sample
  order = Takeaway::Order.create!(
    user: buyer,
    restaurant: rest,
    status: %w[pending out_for_delivery delivered].sample,
    delivery_address: Faker::Address.street_address,
    special_instructions: [nil, Faker::Lorem.sentence].sample
  )
  order.record_activity!("TakeawayOrder") if order.respond_to?(:record_activity!)

  items = Takeaway::MenuItem.where(restaurant: rest).order(Arel.sql("RANDOM()")).limit(2)
  items.each do |item|
    order.order_items.create!(menu_item: item, quantity: rand(1..2), unit_price_cents: item.price_cents)
  end

  # Review
  Takeaway::Review.create!(
    user: buyer,
    restaurant: rest,
    order: order,
    rating: rand(3..5),
    body: Faker::Restaurant.review
  ) if order.status == "delivered"
end

# Delivery drivers
5.times do
  Takeaway::DeliveryDriver.create!(
    user: users.sample,
    vehicle_type: Takeaway::DeliveryDriver::VEHICLE_TYPES.sample,
    available: [true, false].sample,
    current_lat: 60.39 + rand(-0.03..0.03),
    current_lng: 5.33 + rand(-0.03..0.03)
  )
end

puts "Takeaway: #{restaurants.size} restaurants, menu items, orders, reviews, drivers"

# --- TV subapp ---
channels = 8.times.map do |i|
  Tv::Channel.create!(
    user: users.sample,
    name: "#{Faker::Company.name} TV",
    slug: "seed-tv-#{i}-#{Faker::Internet.slug}",
    description: Faker::Lorem.sentence
  )
end

videos = channels.flat_map do |ch|
  3.times.map do
    Tv::Video.create!(
      user: ch.user,
      channel: ch,
      title: Faker::Movie.title,
      description: Faker::Lorem.sentence,
      status: "published",
      duration_seconds: rand(60..300),
      published_at: rand(1..30).days.ago
    )
  end
end

channels.each do |ch|
  Tv::Broadcast.create!(
    channel: ch,
    user: ch.user,
    title: "Live: #{Faker::Music.genre}",
    status: "scheduled"
  )
end

puts "TV: #{channels.size} channels, #{videos.size} videos, broadcasts"

# --- Maps subapp ---
places = []
if ActiveRecord::Base.connection.table_exists?(:places)
  city = City.first
  places = 25.times.map do
    Place.create!(
      city: city,
      name: "#{Faker::Company.name} #{ %w[Cafe Bar Shop Park].sample }",
      kind: %w[cafe bar shop park restaurant].sample,
      latitude: 60.39 + rand(-0.06..0.06),
      longitude: 5.33 + rand(-0.06..0.06)
    )
  end
  puts "Maps: #{places.size} places"
else
  puts "Maps: skipped (places table not migrated)"
end

# --- Messages subapp ---
users.sample(12).each do |u1|
  u2 = users.sample
  next if u1 == u2
  conv = Conversation.find_or_create_direct(u1, u2)
  3.times do
    Message.create!(
      conversation: conv,
      sender: [u1, u2].sample,
      content: Faker::Lorem.sentence(word_count: 7),
      message_type: "text"
    )
  end
end

puts "Messages: conversations and messages seeded"

# --- Final activity/notifications for feed ---
if places.any?
  users.sample(20).each do |u|
    next unless u.respond_to?(:activity_events)
    u.activity_events.create!(
      action: "visited",
      subject_type: "Place",
      subject_id: places.sample.id,
      created_at: rand(1..10).hours.ago
    )
  end
end

puts "\nBrgen + subapps fully seeded with fictive Faker data."
puts "Users: #{User.count}, Posts: #{Post.count}, Marketplace listings: #{Marketplace::Listing.count}"
puts "Dating profiles: #{Dating::Profile.count}, Takeaway restaurants: #{Takeaway::Restaurant.count}"
place_count = ActiveRecord::Base.connection.table_exists?(:places) ? Place.count : 0
puts "TV channels: #{Tv::Channel.count}, Places: #{place_count}"
puts "Ready for demo / development."

# Optional web-augmented fictive seeds using Ferrum + vision LLM (see lib/tasks/{reddit,x}.rake)
# Requires OPENROUTER_API_KEY. These pull live public content (e.g. r/bergen, X searches for "bergen")
# then fictivize/anonymize into Posts, Takeaway, Marketplace etc. for more "real" seed data.
# Usage: SEED_FROM_WEB=1 OPENROUTER_API_KEY=... bin/rails db:seed
# Or run standalone: rake scrape:reddit_seed scrape:x_seed
if ENV['SEED_FROM_WEB'] && ENV['OPENROUTER_API_KEY']
  puts "\nAugmenting with web-scraped fictive data via Ferrum (reddit + x)..."
  begin
    Rake::Task['scrape:reddit_seed'].invoke
  rescue => e
    puts "  reddit_seed skipped: #{e.message}"
  end
  begin
    Rake::Task['scrape:x_seed'].invoke
  rescue => e
    puts "  x_seed skipped: #{e.message}"
  end
  # Optional additional for maps/messages if not covered in rakes
  puts "  (Maps and messages can be augmented via local posts or additional rakes.)"
  puts "Web-augmented seeding complete."
end