# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Uses ruby-faker + SEED_SCALE to generate credible high-volume comic strip data (users + strips + reactions)
# for "millions of users / popular AI tool" demo impression. Production stays minimal.

require "faker"

scale = (ENV["SEED_SCALE"] || (Rails.env.production? ? 1 : 4)).to_i.clamp(1, 15)

if Rails.env.production?
  puts "Production mytoonz seed: minimal users only."
  User.find_or_create_by!(email_address: "admin@mytoonz.example") do |u|
    u.password = u.password_confirmation = "password123"
  end
else
  if Rails.env.development? || Rails.env.test?
    ActiveRecord::Base.connection.disable_referential_integrity do
      %w[Reaction ComicStrip User].each do |model_name|
        begin
          m = model_name.constantize
          m.delete_all if m.respond_to?(:table_exists?) && m.table_exists?
        rescue NameError, StandardError
        end
      end
    end
  end

  puts "Seeding mytoonz popular fictive data (scale=#{scale})..."

  num_users = (30 * scale).clamp(5, 400)
  users = num_users.times.map do |i|
    User.create!(
      email_address: "toon#{i}@mytoonz.example",
      password: "password123",
      password_confirmation: "password123"
    )
  end
  admin = users.first

  # Comic strips (main content) + reactions for engagement
  num_strips = (45 * scale).clamp(5, 900)
  strips = num_strips.times.map do
    user = users.sample
    ComicStrip.create!(
      user: user,
      prompt: Faker::Lorem.sentence(word_count: rand(6..14)),
      style: %w[comic noir cartoon manga retro].sample,
      status: "completed",
      image_urls: [] # would be populated by replicate in real use
    )
  end

  # Boost popularity via reactions (Reactable)
  strips.each do |strip|
    rand(2..(18 * scale).clamp(2, 90)).times do
      begin
        strip.reactions.create!(user: users.sample, kind: %w[like love laugh].sample)
      rescue StandardError
      end
    end
  end

  puts "mytoonz: #{users.size} users, #{strips.size} comic strips, high reaction volume for demo."
  puts "SEED_SCALE=10 for larger popular impression."
end

# Always a base admin
User.find_or_create_by!(email_address: "admin@mytoonz.example") do |u|
  u.password = u.password_confirmation = "password123"
end

puts "mytoonz base ready."
