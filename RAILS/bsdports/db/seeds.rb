# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Uses ruby-faker + SEED_SCALE for fictive users, watches, and comments to give
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
      %w[Comment Watch].each do |model_name|
        begin
          m = model_name.constantize
          m.delete_all if m.respond_to?(:table_exists?) && m.table_exists?
        rescue NameError, StandardError => e
          begin
            Master::Ground::Swallow.log(e, context: __FILE__)
          rescue StandardError
            # logging must not mask seed cleanup
          end
        end
      end
      User.where("email_address LIKE 'portuser%' OR email_address LIKE '%@ports.example'").delete_all
    end
  end

  puts "Seeding BSDports demo activity (scale=#{scale})..."

  # High user count for "active community" feel
  num_users = (80 * scale).clamp(10, 1200)
  users = num_users.times.map do |i|
    User.find_or_create_by!(email_address: "portuser#{i}@ports.example") do |u|
      u.password = "password"
      u.password_confirmation = "password"
    end
  end
  admin = users.first

  puts "Seeded #{users.size} users."

  # Create fictive ports for demo volume (or attach to existing if import ran)
  platform = Platform.find_by!(slug: "openbsd")
  cat = Category.find_or_create_by!(platform: platform, slug: "devel") do |category|
    category.name = "devel"
  end

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
                p.category = cat
                p.description = Faker::Lorem.paragraph(sentence_count: 2)
              end
            end
          end

  puts "Using #{ports.size} ports for activity seeding."

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
        content: Faker::Lorem.sentence(word_count: rand(5..12))
      )
    end
  end

  total_watches = Watch.count

  puts "Bsdports demo seed complete: #{users.size} users, #{ports.size} ports, #{total_watches} watches, #{Comment.count} comments."
  puts "For more: SEED_SCALE=10 bin/rails db:seed (then optionally run ports import rake)."
end

# Always ensure platforms
Platform.find_or_create_by!(slug: "openbsd") do |platform|
  platform.name = "OpenBSD"
  platform.tree_path = "/usr/ports"
  platform.mirror_url = "ftp://ftp.openbsd.org/pub/OpenBSD"
end

puts "Bsdports base platforms ready."
