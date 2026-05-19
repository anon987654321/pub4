# frozen_string_literal: true

admin = User.find_or_create_by!(email_address: "admin@brgen.no") do |u|
  u.username = "admin"
  u.password = u.password_confirmation = "password123"
end

["news", "tech", "bergen", "norge", "kultur"].each do |slug|
  Community.find_or_create_by!(slug: slug) do |c|
    c.name        = slug.capitalize
    c.description = "#{slug.capitalize} community"
    c.user        = admin
  end
end

puts "Seeded #{Community.count} communities, admin id #{admin.id}"
