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

users = 50.times.map do |_i|
  User.create!(
    email_address: Faker::Internet.unique.email(domain: "brgen.no"),
    password: "password123",
    password_confirmation: "password123",
    username: Faker::Internet.username(specifier: 5..12),
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

stores = 12.times.map do
  Marketplace::Store.create!(
    owner: users.sample,
    name: Faker::Company.name,
    description: Faker::Company.catch_phrase,
    address: Faker::Address.street_address,
    latitude: 60.39 + rand(-0.05..0.05),
    longitude: 5.33 + rand(-0.05..0.05)
  )
end

listings = stores.flat_map do |store|
  5.times.map do
    Marketplace::Listing.create!(
      user: store.owner,
      store: store,
      title: Faker::Commerce.product_name,
      description: Faker::Lorem.paragraph,
      price_cents: rand(1000..50000),
      category: Marketplace::Category.all.sample,
      latitude: store.latitude + rand(-0.01..0.01),
      longitude: store.longitude + rand(-0.01..0.01),
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
    quantity: rand(1..3),
    status: %w[pending accepted completed].sample,
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
    interests: Faker::Lorem.words(number: 5).join(", "),
    latitude: user.latitude,
    longitude: user.longitude,
    neighborhood: ["Sentrum", "Nordnes", "Sandviken", "Kalfaret"].sample
  )
end

# Likes and matches
dating_profiles.sample(25).each do |profile|
  liker_profile = dating_profiles.sample
  next if liker_profile == profile
  like = Dating::Like.create!(liker: liker_profile.user, likee: profile.user)
  like.record_activity!("DatingLike") if like.respond_to?(:record_activity!)
  # 30% chance of match
  if rand < 0.3
    match = Dating::Match.create!(
      initiator: liker_profile.user,
      receiver: profile.user,
      status: "matched"
    )
    match.record_activity!("DatingMatch") if match.respond_to?(:record_activity!)
  end
end

puts "Dating: #{dating_profiles.size} profiles, likes/matches seeded"

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
    title: Faker::Music.song_name,
    artist: Faker::Music.band,
    duration_formatted: "#{rand(2..5)}:#{rand(10..59).to_s.rjust(2,'0')}"
  )
end

playlists.each do |pl|
  tracks.sample(rand(4..8)).each do |track|
    pl.playlist_tracks.create!(track: track, user: users.sample)
  end
end

# Playlist sets
sets = playlists.sample(8).map do |pl|
  Playlist::Set.create!(
    user: pl.user,
    playlist: pl,
    name: "Set #{Faker::Number.number(digits: 2)}",
    privacy_level: %w[public private].sample
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

  # Order items
  rest.menu_items.sample(2).each do |item|
    order.order_items.create!(menu_item: item, quantity: rand(1..2), unit_price_cents: item.price_cents)
  end

  # Review
  Takeaway::Review.create!(
    user: buyer,
    restaurant: rest,
    order: order,
    rating: rand(3..5),
    comment: Faker::Restaurant.review
  ) if order.status == "delivered"
end

# Delivery drivers
5.times do
  Takeaway::DeliveryDriver.create!(
    user: users.sample,
    vehicle_type: %w[bike car scooter].sample,
    available: [true, false].sample,
    current_lat: 60.39 + rand(-0.03..0.03),
    current_lng: 5.33 + rand(-0.03..0.03)
  )
end

puts "Takeaway: #{restaurants.size} restaurants, menu items, orders, reviews, drivers"

# --- TV subapp ---
channels = 8.times.map do
  Tv::Channel.create!(
    user: users.sample,
    name: "#{Faker::Company.name} TV",
    slug: Faker::Internet.slug,
    description: Faker::Lorem.sentence
  )
end

shows = channels.flat_map do |ch|
  3.times.map do
    Tv::Show.create!(
      channel: ch,
      title: Faker::Movie.title,
      description: Faker::Lorem.paragraph,
      published: true
    )
  end
end

shows.each do |show|
  rand(3..8).times do |n|
    Tv::Episode.create!(
      show: show,
      title: "Episode #{n+1}: #{Faker::Lorem.words(number: 3).join(' ')}",
      number: n + 1,
      description: Faker::Lorem.sentence
    )
  end
end

# Videos and broadcasts
videos = shows.flat_map do |show|
  2.times.map do
    Tv::Video.create!(
      user: show.channel.user,
      channel: show.channel,
      title: "#{show.title} - Trailer",
      description: Faker::Lorem.sentence,
      status: "published",
      duration_seconds: rand(60..300)
    )
  end
end

channels.each do |ch|
  Tv::Broadcast.create!(
    channel: ch,
    title: "Live: #{Faker::Music.genre}",
    scheduled_at: rand(1..14).days.from_now
  )
end

puts "TV: #{channels.size} channels, #{shows.size} shows, episodes, videos, broadcasts"

# --- Maps subapp ---
places = 25.times.map do
  Place.create!(
    name: Faker::Company.name + " " + %w[Cafe Bar Shop Park].sample,
    kind: %w[cafe bar shop park restaurant].sample,
    address: Faker::Address.street_address,
    latitude: 60.39 + rand(-0.06..0.06),
    longitude: 5.33 + rand(-0.06..0.06),
    description: Faker::Lorem.sentence
  )
end

puts "Maps: #{places.size} places"

# --- Messages subapp ---
users.sample(12).each do |u1|
  u2 = users.sample
  next if u1 == u2
  conv = Conversation.create!
  [u1, u2].each { |u| conv.conversation_participants.create!(user: u) }
  3.times do
    Message.create!(
      conversation: conv,
      sender: [u1, u2].sample,
      content: Faker::Lorem.sentence(word_count: 7)
    )
  end
end

puts "Messages: conversations and messages seeded"

# --- Final activity/notifications for feed ---
users.sample(20).each do |u|
  u.activity_events.create!(
    action: "visited",
    subject_type: "Place",
    subject_id: places.sample.id,
    created_at: rand(1..10).hours.ago
  ) if u.respond_to?(:activity_events)
end

puts "\nBrgen + subapps fully seeded with fictive Faker data."
puts "Users: #{User.count}, Posts: #{Post.count}, Marketplace listings: #{Marketplace::Listing.count}"
puts "Dating profiles: #{Dating::Profile.count}, Takeaway restaurants: #{Takeaway::Restaurant.count}"
puts "TV channels: #{Tv::Channel.count}, Places: #{Place.count}"
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