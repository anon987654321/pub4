# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Uses ruby-faker + SEED_SCALE for high-volume credible legal services demo (users, cases, documents, reactions).

require "faker"

scale = (ENV["SEED_SCALE"] || (Rails.env.production? ? 1 : 3)).to_i.clamp(1, 10)

if Rails.env.production?
  puts "Production pub_attorney seed: minimal."
  User.find_or_create_by!(email_address: "admin@pubattorney.example") do |u|
    u.password = u.password_confirmation = "password123"
  end
else
  if Rails.env.development? || Rails.env.test?
    ActiveRecord::Base.connection.disable_referential_integrity do
      %w[Document Reaction Case User].each do |model_name|
        begin
          m = model_name.constantize
          m.delete_all if m.respond_to?(:table_exists?) && m.table_exists?
        rescue NameError, StandardError
        end
      end
    end
  end

  puts "Seeding pub_attorney popular fictive data (scale=#{scale})..."

  num_users = (20 * scale).clamp(4, 250)
  users = num_users.times.map do
    User.create!(
      email_address: "legal#{Faker::Number.number(digits: 3)}@pubattorney.example",
      password: "password123",
      password_confirmation: "password123"
    )
  end
  admin = users.first

  # Lawyers (if model supports)
  lawyers = []
  if defined?(Lawyer)
    5.times { lawyers << Lawyer.create!(name: Faker::Name.name, email: Faker::Internet.email, specialty: Faker::Job.field) rescue nil }
  end

  num_cases = (28 * scale).clamp(4, 350)
  cases = num_cases.times.map do
    c = Case.create!(
      user: users.sample,
      title: Faker::Lorem.sentence(word_count: 5),
      description: Faker::Lorem.paragraph,
      status: %w[open closed pending review].sample
    )
    # documents
    rand(1..3).times do
      c.documents.create!(title: Faker::File.file_name(ext: "pdf"), content: Faker::Lorem.paragraph) rescue nil
    end
    c
  end

  # Reactions on cases (Reactable)
  cases.each do |kase|
    rand(3..(15 * scale).clamp(3, 70)).times do
      begin
        kase.reactions.create!(user: users.sample, kind: "like")
      rescue StandardError
      end
    end
  end

  puts "pub_attorney: #{users.size} users, #{cases.size} cases + docs/reactions."
  puts "SEED_SCALE higher for bigger popular impression."
end

User.find_or_create_by!(email_address: "admin@pubattorney.example") do |u|
  u.password = u.password_confirmation = "password123"
end

puts "pub_attorney base ready."
