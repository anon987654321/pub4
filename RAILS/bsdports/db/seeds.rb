# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Uses ruby-faker + SEED_SCALE for fictive users + activity (reviews, watches, comments, reactions) to give
# "wildly popular" impression for demos. Real port data comes from import rake tasks.

require "faker"

# Platforms (reference)
Platform.find_or_create_by!(slug: "openbsd") do |platform|
  platform.name = "OpenBSD"
  platform.tree_path = "/usr/ports"
  platform.mirror_url = "ftp://ftp.openbsd.org/pub/OpenBSD"
end

Platform.find_or_create_by!(slug: "freebsd") do |platform|
  platform.name = "FreeBSD"
  platform.tree_path = "/usr/ports"
  platform.mirror_url = "ftp://ftp.freebsd.org/pub/FreeBSD"
  platform.active = false
end

Platform.find_or_create_by!(slug: "netbsd") do |platform|
  platform.name = "NetBSD"
  platform.tree_path = "/usr/pkgsrc"
  platform.mirror_url = "ftp://ftp.netbsd.org/pub/pkgsrc"
  platform.active = false
end

scale = (ENV["SEED_SCALE"] || 3).to_i.clamp(1, 20)

# In prod keep light; dev flood for demo
if Rails.env.production?
  puts "Production bsdports seed: platforms + light users only."
else
  if Rails.env.development? || Rails.env.test?
    # Light cleanup for repeatable demo seeds
    ActiveRecord::Base.connection.disable_referential_integrity do
      %w[Review Comment Watch Installation Reaction].each do |model_name|
        begin
          m = model_name.constantize
          m.delete_all if m.respond_to?(:table_exists?) && m.table_exists?
        rescue NameError, StandardError
        end
      end
      User.where("email_address LIKE 'portuser%' OR email_address LIKE '%@ports.example'").delete_all
    end
  end

  puts "Seeding bsdports with fictive popular activity (scale=#{scale})..."

  # High user count for "active community" feel
  num_users = (80 * scale).clamp(10, 1200)
  users = num_users.times.map do |i|
    User.find_or_create_by!(email_address: "portuser#{i}@ports.example") do |u|
      u.password = "password"
      u.password_confirmation = "password"
      u.username = Faker::Internet.unique.username(specifier: 5..12)
    end
  end
  admin = users.first

  puts "Seeded #{users.size} users."

  # Create fictive ports for demo volume (or attach to existing if import ran)
  platform = Platform.find_by(slug: "openbsd") || Platform.first
  cat = Category.first || Category.create!(name: "devel", slug: "devel") rescue nil

  existing_ports = Port.limit(30).to_a
  num_ports = [existing_ports.size, (15 * scale).clamp(5, 80)].max
  ports = if existing_ports.size >= 5
            existing_ports
          else
            num_ports.times.map do |i|
              pkg = "demo/port#{i}"
              Port.find_or_create_by!(pkgpath: pkg, platform: platform) do |p|
                p.name = Faker::App.name
                p.version = "#{rand(1..9)}.#{rand(0..9)}.#{rand(0..9)}"
                p.category = cat if cat
                p.description = Faker::Lorem.paragraph(sentence_count: 2)
              end
            end
          end

  puts "Using #{ports.size} ports for activity seeding."

  # Reviews with helpful_count (popularity signal)
  reviews_per = (2 * scale).clamp(1, 6)
  ports.each do |port|
    reviews_per.times do
      r = Review.create!(
        user: users.sample,
        port: port,
        rating: rand(3..5),
        content: Faker::Lorem.paragraph(sentence_count: rand(1..3)),
        helpful_count: rand(0, 80 * scale)
      )
      # occasional helpful boosts
      rand(0..3).times { r.helpful! } if rand < 0.4
    end
  end
  puts "Seeded reviews."

  # Watches (users following ports)
  ports.each do |port|
    rand(1..(8 * scale).clamp(2, 50)).times do
      Watch.find_or_create_by!(user: users.sample, port: port)
    end
  end

  # Comments on ports
  ports.each do |port|
    rand(0..(5 * scale)).times do
      Comment.create!(
        user: users.sample,
        port: port,
        body: Faker::Lorem.sentence(word_count: rand(5..12))
      )
    end
  end

  # Installations (usage signal)
  ports.sample(ports.size / 2).each do |port|
    rand(2..(12 * scale)).times do
      Installation.create!(user: users.sample, port: port, version: port.version) rescue nil
    end
  end

  # Reactions on ports (reactable)
  ports.each do |port|
    rand(4..(25 * scale).clamp(4, 150)).times do
      begin
        port.reactions.create!(user: users.sample, kind: %w[like star useful].sample)
      rescue StandardError
      end
    end
  end

  total_reviews = Review.count
  total_watches = Watch.count
  total_reactions = begin
    Reaction.count
  rescue StandardError
    0
  end

  puts "Bsdports popular seed complete: #{users.size} users, #{ports.size} ports, #{total_reviews} reviews, #{total_watches} watches, ~#{total_reactions} reactions."
  puts "For more: SEED_SCALE=10 bin/rails db:seed (then optionally run ports import rake)."
end

# Always ensure platforms
Platform.find_or_create_by!(slug: "openbsd") do |platform|
  platform.name = "OpenBSD"
  platform.tree_path = "/usr/ports"
  platform.mirror_url = "ftp://ftp.openbsd.org/pub/OpenBSD"
end

puts "Bsdports base platforms ready."
