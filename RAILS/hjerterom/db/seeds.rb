# frozen_string_literal: true

# Hjerterom seeds: ruby-faker + SEED_SCALE for credible high-volume community rescue data.
# Gives impression of active, popular local food/resource network (thousands of donations, volunteers, posts).
# Production: light only. Dev: full flood with reactions for "millions of users" vibe via volume + counts.

require "faker"

# Production guard: keep only reference data.
if Rails.env.production?
  puts "Production seed: keeping reference crisis/categories only."
  # Reference data below will still run (idempotent).
else
  scale = (ENV["SEED_SCALE"] || 5).to_i.clamp(1, 30)

  if Rails.env.development? || Rails.env.test?
    # Safe wipe for replanting demo data. Keep structure.
    ActiveRecord::Base.connection.disable_referential_integrity do
      %w[Reaction Comment FoodItem FoodRequest SupportRequest Shift Donation Volunteer Post Donor FoodListing User].each do |model_name|
        begin
          model = model_name.constantize
          model.delete_all if model.respond_to?(:table_exists?) && model.table_exists?
        rescue NameError, StandardError
        end
      end
    end
  end

  puts "Seeding hjerterom with fictive popular data (scale=#{scale})..."

  # Admin
  admin = User.find_or_create_by!(email_address: "admin@hjerterom.brgen.no") do |u|
    u.password = u.password_confirmation = "password123"
  end

  # Reference data (always)
  crisis_lines = [
    { title: "Mental Helse Hjelpelinjen", phone: "116 123", available_24h: true, languages: "Norsk", country: "NO" },
    { title: "Kirkens SOS", phone: "22 40 00 40", available_24h: true, languages: "Norsk", country: "NO" },
    { title: "Røde Kors Besøkstjeneste", phone: "800 33 321", available_24h: false, languages: "Norsk", country: "NO" },
  ]
  crisis_lines.each { |c| Crisis.find_or_create_by!(title: c[:title]) { |cr| cr.update(c) } }

  cats = [
    { name: "Angst", slug: "angst", type_of: "mental_health" },
    { name: "Depresjon", slug: "depresjon", type_of: "mental_health" },
    { name: "Ensomhet", slug: "ensomhet", type_of: "mental_health" },
    { name: "Mat", slug: "mat", type_of: "food" },
    { name: "Hjelp", slug: "hjelp", type_of: "support" },
  ]
  cats.each { |c| Category.find_or_create_by!(slug: c[:slug]) { |cat| cat.update(c) } }

  # Donors for credibility
  num_donors = (25 * scale).clamp(5, 400)
  donors = num_donors.times.map do |i|
    Donor.find_or_create_by!(name: "#{Faker::Name.name} #{i}") do |d|
      d.email = Faker::Internet.email
      d.phone = Faker::PhoneNumber.cell_phone
      d.notes = Faker::Lorem.sentence(word_count: 6)
    end
  end

  # High volume Donations (core signal of activity) + food items + reactions
  num_donations = (80 * scale).clamp(10, 2000)
  donations = num_donations.times.map do
    donor = donors.sample
    d = Donation.create!(
      donor: donor,
      source_name: [Faker::Company.name, Faker::Restaurant.name, "Husholdning"].sample,
      pickup_window: "#{rand(8..20)}:00-#{rand(18..22)}:00",
      status: Donation.statuses.keys.sample,
      notes: Faker::Lorem.sentence(word_count: 8)
    )
    # Attach food items
    rand(1..4).times do
      d.food_items.create!(
        name: Faker::Food.ingredient,
        quantity: rand(1..12),
        category: rand(0..8),
        quality_state: rand(0..2),
        best_before: rand(0..14).days.from_now.to_date,
        notes: Faker::Lorem.word
      )
    end
    d
  end
  puts "Created #{donations.size} donations with food items"

  # Create reactions on many donations for popularity (reactable)
  donations.sample([donations.size, 60 * scale].min).each do |don|
    rand(3..(12 * scale).clamp(3, 80)).times do
      liker = User.order("RANDOM()").first || admin
      begin
        don.reactions.create!(user: liker, kind: %w[like love thanks].sample)
      rescue StandardError
        # skip if reaction validation or FK issue in this seed context
      end
    end
  end

  # Volunteers + shifts (high for community feel)
  num_vols = (40 * scale).clamp(5, 600)
  volunteers = num_vols.times.map do
    Volunteer.create!(
      name: Faker::Name.name,
      email: Faker::Internet.email,
      phone: Faker::PhoneNumber.cell_phone,
      active: [true, true, false].sample,
      notes: Faker::Lorem.sentence
    )
  end
  puts "Created #{volunteers.size} volunteers"

  volunteers.sample(volunteers.size / 2).each do |vol|
    rand(1..3).times do
      vol.shifts.create!(
        starts_at: rand(1..14).days.from_now.change(hour: rand(8..17)),
        ends_at: rand(1..14).days.from_now.change(hour: rand(18..22)),
        kind: rand(0..2),
        state: rand(0..2),
        location: "#{Faker::Address.street_name} #{rand(1..50)}",
        notes: Faker::Lorem.sentence(word_count: 3)
      )
    end
  end

  # Posts + comments (community board activity)
  food_cat = Category.find_by(slug: "mat") || Category.first
  num_posts = (35 * scale).clamp(5, 800)
  posts = num_posts.times.map do
    u = (User.all.sample || admin)
    Post.create!(
      user: u,
      category: food_cat,
      title: Faker::Lorem.sentence(word_count: rand(4..8)),
      body: Faker::Lorem.paragraphs(number: 2).join("\n\n")
    )
  end
  puts "Created #{posts.size} posts"

  posts.each do |post|
    rand(0..(4 * scale).clamp(0, 30)).times do
      Comment.create!(post: post, user: (User.all.sample || admin), body: Faker::Lorem.sentence)
    end
  end

  # Food listings + requests for marketplace-like activity (high volume)
  num_listings = (20 * scale).clamp(3, 300)
  some_user = User.first || admin
  listings = num_listings.times.map do
    FoodListing.create!(
      user: some_user,
      title: Faker::Food.dish,
      description: Faker::Lorem.sentence,
      quantity: rand(1..20),
      unit: FoodListing::UNITS.sample,
      available_until: rand(2..21).days.from_now,
      status: "available",
      pickup_address: "#{Faker::Address.street_address}, #{Faker::Address.city}"
    )
  end

  listings.each do |listing|
    rand(0..(3 * scale)).times do
      req_user = User.all.sample || admin
      FoodRequest.create!(
        food_listing: listing,
        user: req_user,
        status: "pending",
        message: Faker::Lorem.sentence(word_count: 5)
      )
    end
  end
  puts "Created #{listings.size} food listings + requests"

  # Final reaction boost on posts for visible popularity
  posts.sample(posts.size / 3).each do |p|
    rand(5..(20 * scale).clamp(5, 120)).times do
      liker = User.all.sample || admin
      begin
        p.reactions.create!(user: liker, kind: "like")
      rescue StandardError
        # tolerate missing reaction support or dupes in seed
      end
    end
  end

  puts "\nHjerterom seeded with high-volume fictive data (scale=#{scale})."
  puts "Donations: #{Donation.count}, Volunteers: #{Volunteer.count}, Posts: #{Post.count}, Reactions approx high."
  puts "Use SEED_SCALE=20 bin/rails db:seed for even larger demo impression."
end

# Always ensure reference data exists (idempotent)
crisis_lines = [
  { title: "Mental Helse Hjelpelinjen", phone: "116 123", available_24h: true, languages: "Norsk", country: "NO" },
  { title: "Kirkens SOS", phone: "22 40 00 40", available_24h: true, languages: "Norsk", country: "NO" },
  { title: "Røde Kors Besøkstjeneste", phone: "800 33 321", available_24h: false, languages: "Norsk", country: "NO" },
]
crisis_lines.each { |c| Crisis.find_or_create_by!(title: c[:title]) { |cr| cr.update(c) } }

cats = [
  { name: "Angst", slug: "angst", type_of: "mental_health" },
  { name: "Depresjon", slug: "depresjon", type_of: "mental_health" },
  { name: "Ensomhet", slug: "ensomhet", type_of: "mental_health" },
  { name: "Mat", slug: "mat", type_of: "food" },
]
cats.each { |c| Category.find_or_create_by!(slug: c[:slug]) { |cat| cat.update(c) } }

admin = User.find_or_create_by!(email_address: "admin@hjerterom.brgen.no") do |u|
  u.password = u.password_confirmation = "password123"
end

puts "Hjerterom reference data ready (admin + crisis + cats)."
