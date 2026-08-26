# frozen_string_literal: true

# Comprehensive fictive seed data for Brgen + all subapps using ruby-faker.
# Seeds core + marketplace, dating, playlist, takeaway, tv, maps, messages.
# Idempotent with find_or_create_by! where possible. Run: bin/rails db:seed

require 'faker'

# Ensure Cities exist for automatic TLD/domain-based resolution (no city switcher).
# Each city domain is an isolated experience.
Brgen::CitySeed.sync! if defined?(Brgen::CitySeed) && ActiveRecord::Base.connection.table_exists?(:cities)

# Scale for "wildly popular" impression in dev/demo: SEED_SCALE=50 for thousands of users/posts
# with high engagement counters. Keep small for prod/demo.
SEED_SCALE = [1, (ENV['SEED_SCALE'] || (Rails.env.production? ? 1 : 10)).to_i].max

if Rails.env.production? && City.table_exists?
  puts "Production seed: Bergen demo only (skipping Faker flood)."
  User.find_or_create_by!(email_address: "admin@brgen.no") do |u|
    u.username = "admin"
    u.password = u.password_confirmation = ENV["ADMIN_SEED_PASSWORD"].to_s.tap { |p| raise "set ADMIN_SEED_PASSWORD" if p.empty? || p == "password123" }
  end
  if (bergen = City.find_by(domain: "brgen.no"))
    Brgen::BergenDemoSeeder.new(bergen).seed!
    puts "Bergen demo: #{Post.where(city: bergen).count} posts"
  end
  exit 0
end

if City.table_exists?
  puts 'Seeding flagship per-city content (brgen.no, lsangeles.com, amstrdam.nl, oshlo.no)...'
  City.where(domain: %w[brgen.no lsangeles.com amstrdam.nl oshlo.no]).find_each do |city|
    Brgen::PerCitySeeder.new(city, posts_per_city: 4).seed!
  end
end

puts 'Seeding Brgen (core + subapps) with rich fictive data...'

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
admin = User.find_or_create_by!(email_address: 'admin@brgen.no') do |u|
  u.username = 'admin'
  u.password = u.password_confirmation = 'password123'
end

num_users = (50 * SEED_SCALE).clamp(10, 5000)
# This file is the Bergen-anchored seed (it hardcodes 60.39/5.33 below), but it
# never set a Faker locale, so the bulk users came out English-named
# ("Jerrell Bernier") in a Norwegian city. PerCitySeeder handles the other
# domains with their own locales.
users = Brgen::CityContent.with_faker_locale('NO') do
  num_users.times.map do |i|
    # A real-sounding name (this app's display_name is just username), not the
    # old "seed0_xkq3f7" -- first_name+last_name directly (not Faker::Name.name)
    # avoids odd baked-in prefixes/suffixes ("Prof.", "Esq.", "III") in a
    # username. The numeric suffix stays for guaranteed uniqueness at up to
    # 5000 draws, where real-name collisions become plausible.
    name_slug = "#{Faker::Name.first_name} #{Faker::Name.last_name}".parameterize(separator: '_')
    User.create!(
      email_address: "seed#{i}@#{Faker::Internet.domain_name}",
      password: 'password123',
      password_confirmation: 'password123',
      username: "#{name_slug}_#{i}",
      latitude: 60.39 + rand(-0.1..0.1),
      longitude: 5.33 + rand(-0.1..0.1)
    )
  end
end

seed_city = City.find_by(domain: 'brgen.no') || City.first
ActsAsTenant.current_tenant = seed_city if seed_city

puts "Created #{users.size + 1} users (incl admin)"

communities = %w[news tech bergen norge kultur food music film].map do |slug|
  Community.find_or_create_by!(slug: slug) do |c|
    c.name = slug.capitalize
    c.description = "#{slug.capitalize} community for #{Faker::Address.city}"
    c.user = admin
  end
end

# Core posts + activity — scale for popular impression (high views/likes)
posts_per = (4 * SEED_SCALE).clamp(1, 20)
city_display_name = seed_city&.name.presence || 'Bergen'
posts = users.sample([30, users.size].min).flat_map do |user|
  posts_per.times.map do
    Post.create!(
      user: user,
      community: communities.sample,
      # Was Faker::Lorem — Latin filler in a Norwegian city feed is the single
      # most obvious tell that a feed is seeded. See Brgen::PlausibleContent.
      title: Brgen::PlausibleContent.post_title(city_display_name),
      content: Brgen::PlausibleContent.post_body,
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
  'electronics' => %w[phones computers audio gaming],
  'clothing' => %w[shirts trousers shoes outerwear],
  'furniture' => %w[sofas tables chairs storage],
  'vehicles' => %w[cars bikes motorcycles parts],
  'services' => %w[repair moving cleaning tutoring]
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

num_stores = (12 * SEED_SCALE).clamp(5, 200)
stores = num_stores.times.map do |i|
  # Faker::Company.name produces American agency names ("Stokes-Bernier") that
  # read as obviously foreign on a Bergen shopfront.
  Marketplace::Store.create!(
    owner: users.sample,
    name: Brgen::PlausibleContent.store_name,
    slug: "seed-store-#{i}-#{Faker::Internet.slug}",
    description: Faker::Company.catch_phrase,
    vertical: Marketplace::Store::VERTICALS.sample
  )
end

listings_per = (5 * SEED_SCALE).clamp(1, 10)
bergen_lat = seed_city&.latitude.to_f
bergen_lng = seed_city&.longitude.to_f
bergen_lat = 60.3913 if bergen_lat.zero?
bergen_lng = 5.3221 if bergen_lng.zero?
# Leaf categories only (a listing filed under the "electronics" root rather
# than "electronics-phones" can't have a title that matches it).
categories_by_slug = Marketplace::Category.where.not(parent_id: nil).index_by(&:slug)
leaf_slugs = categories_by_slug.keys
listings = stores.flat_map do |store|
  listings_per.times.map do
    # Product first, then the category it actually belongs in — the reverse
    # (category first, then any title from that root) shelved a 55" TV under
    # electronics-audio and winter boots under clothing-outerwear.
    title, leaf_slug = Brgen::PlausibleContent.listing_for(leaf_slugs)
    category = categories_by_slug[leaf_slug]
    bydel = Brgen::PlausibleContent::BERGEN_BYDELER.sample
    Marketplace::Listing.create!(
      user: store.owner,
      store: store,
      title: title,
      description: Brgen::PlausibleContent.listing_body(bydel: bydel),
      price_cents: rand(1000..50_000),
      category: category,
      # This was Faker::Address.city on a record carrying Bergen lat/lng, so
      # listings advertised a random world city while mapping to Bergen.
      location: bydel,
      latitude: bergen_lat + rand(-0.05..0.05),
      longitude: bergen_lng + rand(-0.06..0.06),
      status: 'active',
      created_at: rand(1..60).days.ago,
      views_count: rand((100 * SEED_SCALE)..(10000 * SEED_SCALE))
    )
  end
end

# Live hyperlocal notes (guest demo density on /live)
live_count = (12 * SEED_SCALE).clamp(8, 80)
live_count.times do |i|
  user = users.sample
  body = [
    "Noen i nærheten av #{Faker::Address.community}?",
    "Ledig plass på buss — #{Faker::Lorem.word}",
    "Gratis #{Faker::Food.dish} utenfor #{Faker::Address.street_name}",
    Faker::Lorem.sentence(word_count: 8),
  ].sample
  next if body.blank?

  post = Post.new(
    user: user,
    city: seed_city,
    content: body.truncate(Post::LIVE_CONTENT_MAX),
    title: body.truncate(80),
    created_at: rand(1..48).hours.ago
  )
  post.stamp_live_location!(
    lat: bergen_lat + rand(-0.03..0.03),
    lng: bergen_lng + rand(-0.04..0.04)
  )
  post.save!
end
puts "Live: #{Post.live.count} geo-stamped notes"

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
  order.record_activity!('MarketplaceOrder') if order.respond_to?(:record_activity!)
end

puts "Marketplace: #{stores.size} stores, #{listings.size} listings, some orders"

# --- Dating subapp ---
num_dating = (35 * SEED_SCALE).clamp(10, 1000)
# Visible is derived from the photo, not asserted alongside it, the same way
# Brgen::BergenDemoSeeder derives it. A profile may not be visible without one
# — a visible profile with no photo sits in the deck as a blank card — and
# Shared::DemoMedia.skip_attach? is true in the test environment, which is the
# environment CI seeds in. Asking for visible: true there produced a profile
# the validation had to refuse, and one refusal aborts the whole seed run.
dating_profiles = users.sample(num_dating).map do |user|
  profile = Dating::Profile.new(
    user: user,
    bio: Faker::Lorem.paragraph(sentence_count: 3),
    age: rand(22..45),
    gender: Dating::Profile::GENDERS.sample,
    looking_for: Dating::Profile::LOOKING_FOR.sample,
    latitude: user.latitude,
    longitude: user.longitude,
    bydel: %w[Sentrum Nordnes Sandviken Kalfaret].sample
  )
  Brgen::DemoMedia.attach_remote_postpro!(
    profile, :photos, seed: "dating-#{user.id}", preset: "portrait", width: 600, height: 900
  )
  profile.visible = profile.photos.attached?
  profile.save!
  profile
end

# Generate many likes for popular feel
dating_profiles.each_cons(3) do |a, b, c|
  Dating::Like.find_or_create_by!(liker: a.user, likee: b.user)
  Dating::Like.find_or_create_by!(liker: b.user, likee: c.user)
end

puts "Dating: #{dating_profiles.size} profiles, #{Dating::Like.count} likes, #{Dating::Match.count} matches"

# --- Playlist subapp ---
num_play = (15 * SEED_SCALE).clamp(5, 200)
playlists = users.sample(num_play).map do |user|
  Playlist::Playlist.create!(
    user: user,
    name: "#{Faker::Music.genre} #{Faker::Music.album}",
    description: Faker::Lorem.sentence,
    tracks_count: rand(5..25),
    plays_count: rand((100 * SEED_SCALE)..(100000 * SEED_SCALE)),
    collaborative: [true, false].sample
  )
end

tracks = 40.times.map do
  Playlist::Track.create!(
    title: "#{Faker::Music.genre} #{Faker::Lorem.words(number: 2).join(' ')}",
    artist: Faker::Music::RockBand.name,
    duration_seconds: rand(120..300),
    source_type: 'upload'
  )
end

playlists.each do |pl|
  tracks.sample(rand(4..8)).each do |track|
    pl.add_track!(track, user: users.sample)
  end
end

users.sample(8).map do |user|
  Playlist::Set.create!(
    user: user,
    name: "Set #{Faker::Number.number(digits: 2)}",
    privacy: %w[public private unlisted].sample
  )
end

puts "Playlist: #{playlists.size} playlists, tracks, sets"

# --- Takeaway subapp ---
# CityTenantable adds belongs_to :city; string column :city is display label only (not the association).
ActsAsTenant.current_tenant = seed_city if seed_city
city_label = seed_city&.name.presence || "Bergen"
# Cuisine now travels with the restaurant name (PlausibleContent.restaurant_for).
num_rest = (15 * SEED_SCALE).clamp(5, 100)
restaurants = num_rest.times.map do |i|
  # Faker::Restaurant.name is US-styled ("The Rusty Spoon") and the address was
  # a Faker street that doesn't exist in Bergen. Name and cuisine come from the
  # same pair so a place called "Ramen Bergen" isn't filed as Mexican.
  name, cuisine = Brgen::PlausibleContent.restaurant_for(i)
  Takeaway::Restaurant.create!(
    user: users.sample,
    name: name,
    cuisine_type: cuisine,
    address: Brgen::PlausibleContent.street_address,
    active: true,
    delivery_fee_cents: rand(2000..6000),
    min_order_cents: rand(8000..15_000),
    latitude: 60.39 + rand(-0.04..0.04),
    longitude: 5.33 + rand(-0.04..0.04)
  ).tap { |restaurant| restaurant.update_column(:city, city_label) }
end

restaurants.each do |rest|
  # Menu now matches the restaurant's own cuisine, in Norwegian, rather than
  # Faker::Food's English dishes served at a Bergen kebab house.
  dishes = Brgen::PlausibleContent.dishes_for(rest.cuisine_type)
  dishes.sample(rand(4..dishes.size)).each do |(name, description)|
    Takeaway::MenuItem.create!(
      restaurant: rest,
      name: name,
      description: description,
      price_cents: rand(6000..18_000),
      available: true
    )
  end
end

# Orders + reviews
#
# Build the line items before saving, the way Takeaway::OrdersController#create
# does. This used to create! the order bare and attach items afterwards, and
# Takeaway::Order#meets_minimum_order reads `order_items.target` -- so the
# subtotal was 0.00 at validation time and every restaurant with a
# min_order_cents rejected its own seed order:
#
#   ActiveRecord::RecordInvalid: Minimum order for Døner Ekspress Åsane is
#   122.76 NOK — your subtotal is 0.00 NOK.
#
# That took down `db:seed:replant`, which is a stage of vps_ci.sh, which is a
# stage of vps-deploy -- so brgen could not be deployed at all, while the
# validation itself is correct and the real checkout path was always fine.
# Enough menu items to clear any threshold the restaurant advertises.
restaurants.sample(10).each do |rest|
  buyer = users.sample
  # includes(:restaurant) is load-bearing, not decoration: ApplicationRecord sets
  # strict_loading_by_default in every environment, and building an OrderItem
  # reads menu_item.restaurant, so dropping the preload raises
  # StrictLoadingViolationError here rather than degrading to an extra SELECT.
  menu = Takeaway::MenuItem.available.includes(:restaurant)
                           .where(restaurant: rest).order(Arel.sql('RANDOM()')).to_a
  next if menu.empty?

  order = Takeaway::Order.new(
    user: buyer,
    restaurant: rest,
    status: %w[pending out_for_delivery delivered].sample,
    delivery_address: Faker::Address.street_address,
    special_instructions: [nil, Faker::Lorem.sentence].sample
  )

  subtotal = 0
  minimum = rest.min_order_cents.to_i
  menu.each do |item|
    break if order.order_items.size >= 2 && subtotal >= minimum

    quantity = rand(1..2)
    order.order_items.build(menu_item: item, quantity: quantity, unit_price_cents: item.price_cents)
    subtotal += item.price_cents.to_i * quantity
  end
  # A restaurant whose whole menu cannot reach its own minimum is bad seed data,
  # not a reason to abort the seed.
  next if subtotal < minimum

  order.save!
  order.calculate_totals!
  order.record_activity!('TakeawayOrder') if order.respond_to?(:record_activity!)

  # Review
  next unless order.status == 'delivered'

  Takeaway::Review.create!(
    user: buyer,
    restaurant: rest,
    order: order,
    rating: rand(3..5),
    body: Faker::Restaurant.review
  )
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
num_ch = (8 * SEED_SCALE).clamp(3, 50)
channel_names = Brgen::PlausibleContent::TV_CHANNEL_NAMES.shuffle
channels = num_ch.times.map do |i|
  Tv::Channel.create!(
    user: users.sample,
    # Was "#{Faker::Company.name} TV" — a US company name with TV bolted on.
    name: channel_names[i % channel_names.size] + (i >= channel_names.size ? " #{i}" : ''),
    slug: "seed-tv-#{i}-#{Faker::Internet.slug}",
    description: Brgen::PlausibleContent.post_body
  )
end

videos = channels.flat_map do |ch|
  # Faker::Movie.title put Hollywood features on a local city channel.
  Brgen::PlausibleContent::TV_VIDEO_TITLES.sample(3).map do |title|
    Tv::Video.create!(
      user: ch.user,
      channel: ch,
      title: title,
      description: Brgen::PlausibleContent.post_body,
      status: 'published',
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
    status: 'scheduled'
  )
end

puts "TV: #{channels.size} channels, #{videos.size} videos, broadcasts"

# --- Maps subapp ---
places = []
if ActiveRecord::Base.connection.table_exists?(:places)
  city = City.first
  num_places = (25 * SEED_SCALE).clamp(10, 500)
  places = num_places.times.map do
    kind = %w[cafe bar shop park restaurant].sample
    kind_label = { 'cafe' => 'Kafé', 'bar' => 'Bar', 'shop' => 'Butikk',
                   'park' => 'Park', 'restaurant' => 'Restaurant' }.fetch(kind)
    Place.create!(
      city: city,
      # Was "#{Faker::Company.name} Cafe". Anchoring to a real Bergen street or
      # bydel gives a name that could plausibly be on a sign there.
      name: "#{kind_label} #{[ Brgen::PlausibleContent::BERGEN_BYDELER,
                               Brgen::PlausibleContent::BERGEN_STREETS ].sample.sample}",
      kind: kind,
      latitude: 60.39 + rand(-0.06..0.06),
      longitude: 5.33 + rand(-0.06..0.06)
    )
  end
  puts "Maps: #{places.size} places"
else
  puts 'Maps: skipped (places table not migrated)'
end

# --- Messages subapp ---
users.sample(12).each do |u1|
  u2 = users.sample
  next if u1 == u2

  conv = Conversation.find_or_create_direct(u1, u2)
  # Short Norwegian DM openers instead of Faker::Lorem Latin — these are read
  # in the inbox and the corner chat widget, where Latin is glaring.
  openers = [
    'Hei! Er den fortsatt til salgs?', 'Går det bra å hente i morgen?',
    'Takk for sist!', 'Kan du sende et bilde av den?',
    'Jeg er interessert — når passer det?', 'Er prisen forhandlingsbar?',
    'Sees vi på lørdag?', 'Har du prøvd stedet i Marken?',
    'Beklager sent svar, hektisk uke.', 'Det passer fint for meg.'
  ]
  openers.sample(3).each do |body|
    Message.create!(
      conversation: conv,
      sender: [u1, u2].sample,
      content: body,
      message_type: 'text'
    )
  end
end

puts 'Messages: conversations and messages seeded'

# --- Affiliate inventory ---
# Real TradeDoubler products need an approved publisher account (see
# app/services/tradedoubler.rb). Until TRADEDOUBLER_TOKEN exists, seed flagged
# placeholders so the deals sidebar and the weekly_deals newsletter have
# something to render; `rake affiliate:import` replaces them with real rows and
# `rake affiliate:drop_placeholders` clears these out.
if defined?(Shared::AffiliateProduct) && Shared::AffiliateProduct.table_exists?
  if Shared::Tradedoubler.configured?
    imported = Shared::Tradedoubler.import!
    puts "Affiliate: imported #{imported} real TradeDoubler product(s)"
  else
    placed = Brgen::AffiliatePlaceholders.seed!
    puts "Shared::Affiliate: #{placed} placeholder product(s) (TRADEDOUBLER_TOKEN unset — flagged placeholder: true)"
  end
end

# --- Final activity/notifications for feed ---
if places.any?
  users.sample(20).each do |u|
    next unless u.respond_to?(:activity_events)

    place = places.sample
    ActivityEvent.create!(
      actor: u,
      event_name: 'visited',
      subject_type: place.class.name,
      subject_id: place.id,
      source_vertical: 'maps',
      locality: place.try(:locality),
      created_at: rand(1..10).hours.ago
    )
  end
end

puts "\nBrgen + subapps fully seeded with fictive Faker data (scale=#{SEED_SCALE})."
# User is tenant-scoped and a tenant is current by this point, so a bare
# User.count reported 0 right after "Created 101 users" — the bulk users carry
# no city_id. Count without the tenant scope so the summary matches reality.
total_users = ActsAsTenant.without_tenant { User.count }
puts "Users: #{total_users}, Posts: #{Post.count} (Live: #{Post.live.count}), Marketplace listings: #{Marketplace::Listing.count}"
puts "Dating profiles: #{Dating::Profile.count}, Takeaway restaurants: #{Takeaway::Restaurant.count}"
place_count = ActiveRecord::Base.connection.table_exists?(:places) ? Place.count : 0
puts "TV channels: #{Tv::Channel.count}, Places: #{place_count}"
puts 'Ready for demo / development. Use SEED_SCALE=20 for more "millions" impression via volume + counters.'

if (bergen = City.find_by(domain: 'brgen.no')) && !ENV['SKIP_BERGEN_DEMO']
  puts "\nSeeding Bergen demo content (Norwegian posts, users, media)..."
  Brgen::BergenDemoSeeder.new(bergen).seed!
  playlist = Playlist::Playlist.find_by(city: bergen, name: Brgen::BergenDemoSeeder::RADIO_BERGEN_PLAYLIST)
  track_count = playlist&.tracks&.count.to_i
  puts "Bergen demo: #{Post.where(city: bergen).count} posts, #{Dating::Profile.joins(:user).where(users: { city_id: bergen.id }).count} dating profiles, #{track_count} Radio Bergen tracks"
end

# Optional web-augmented fictive seeds using Ferrum + vision LLM (see lib/tasks/{reddit,x}.rake)
# Requires OPENROUTER_API_KEY. Per-city: rake scrape:reddit_seed[brgen.no] or scrape:reddit_seed[lsangeles.com]
# then fictivize/anonymize into Posts, Takeaway, Marketplace etc. for more "real" seed data.
# Usage: SEED_FROM_WEB=1 OPENROUTER_API_KEY=... bin/rails db:seed
# Or run standalone: rake scrape:reddit_seed scrape:x_seed
if ENV['SEED_FROM_WEB'] && ENV['OPENROUTER_API_KEY']
  puts "\nAugmenting with web-scraped fictive data via Ferrum (reddit + x)..."
  begin
    Rake::Task['scrape:reddit_seed'].invoke
  rescue StandardError => e
    puts "  reddit_seed skipped: #{e.message}"
  end
  begin
    Rake::Task['scrape:x_seed'].invoke
  rescue StandardError => e
    puts "  x_seed skipped: #{e.message}"
  end
  # Optional additional for maps/messages if not covered in rakes
  puts '  (Maps and messages can be augmented via local posts or additional rakes.)'
  puts 'Web-augmented seeding complete.'
end
