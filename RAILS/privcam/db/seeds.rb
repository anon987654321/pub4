# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Uses ruby-faker + SEED_SCALE for credible popular private video sharing demo data (users, videos, comments, reactions).

require "faker"

scale = (ENV["SEED_SCALE"] || (Rails.env.production? ? 1 : 4)).to_i.clamp(1, 12)

if Rails.env.production?
  puts "Production privcam seed: minimal."
  User.find_or_create_by!(email_address: "admin@privcam.example") do |u|
    u.password = u.password_confirmation = "password123"
  end
else
  if Rails.env.development? || Rails.env.test?
    ActiveRecord::Base.connection.disable_referential_integrity do
      %w[Comment Reaction Video User].each do |model_name|
        begin
          m = model_name.constantize
          m.delete_all if m.respond_to?(:table_exists?) && m.table_exists?
        rescue NameError, StandardError
        end
      end
    end
  end

  puts "Seeding privcam fictive popular data (scale=#{scale})..."

  num_users = (25 * scale).clamp(5, 350)
  users = num_users.times.map do
    User.create!(
      email_address: Faker::Internet.unique.email(domain: "privcam.example"),
      password: "password123",
      password_confirmation: "password123"
    )
  end
  admin = users.first

  num_videos = (35 * scale).clamp(4, 600)
  videos = num_videos.times.map do
    Video.create!(
      user: users.sample,
      title: Faker::Movie.title + " " + Faker::Lorem.words(number: 2).join(" "),
      description: Faker::Lorem.sentence
    )
  end

  # Comments
  videos.each do |vid|
    rand(0..(6 * scale)).times do
      Comment.create!(video: vid, user: users.sample, body: Faker::Lorem.sentence(word_count: rand(4..10)))
    end
  end

  # Reactions for popularity (Reactable)
  videos.each do |vid|
    rand(5..(22 * scale).clamp(5, 110)).times do
      begin
        vid.reactions.create!(user: users.sample, kind: "like")
      rescue StandardError
      end
    end
  end

  puts "privcam: #{users.size} users, #{videos.size} videos + comments/reactions for active demo feel."
end

User.find_or_create_by!(email_address: "admin@privcam.example") do |u|
  u.password = u.password_confirmation = "password123"
end

puts "privcam base ready."
