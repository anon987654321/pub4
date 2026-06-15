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

{
  "electronics" => %w[phones computers audio gaming],
  "clothing" => %w[shirts trousers shoes outerwear],
  "furniture" => %w[sofas tables chairs storage],
  "vehicles" => %w[cars bikes motorcycles parts],
  "services" => %w[repair moving cleaning tutoring]
}.each do |root_name, children|
  root = Marketplace::Category.find_or_create_by!(name: root_name.titleize, slug: root_name)
  children.each do |child_name|
    Marketplace::Category.find_or_create_by!(
      name: child_name.titleize,
      slug: "#{root_name}-#{child_name}",
      parent: root
    )
  end
end

puts "Seeded #{Community.count} communities, admin id #{admin.id}"
