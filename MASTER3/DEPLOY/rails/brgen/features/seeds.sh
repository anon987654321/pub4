#!/usr/bin/env zsh
emulate -L zsh
setopt err_return no_unset pipe_fail extended_glob warn_create_global

typeset -r APP_DIR="/home/brgen/app"
typeset -r MAX_KARMA_SEED=1000

echo "==> [seeds] Development seed data"
cd "$APP_DIR"

cat > db/seeds.rb << 'RUBY'
return unless Rails.env.development?

puts "Creating communities..."
%w[Oslo Bergen Trondheim Stavanger Tromsø].each do |city|
  Community.find_or_create_by!(
    name: "#{city} Community",
    subdomain: city.downcase,
    slug: city.parameterize
  ) { |c| c.description = "Local community for #{city}" }
end

puts "Creating users..."
10.times do
  User.create!(
    email: Faker::Internet.email,
    password: "password123",
    password_confirmation: "password123",
    username: Faker::Internet.unique.username,
    karma: rand(0..1000)
  )
end

puts "Creating posts..."
Community.all.each do |community|
  20.times do
    post = community.posts.create!(
      title:   Faker::Lorem.sentence(word_count: 5),
      content: Faker::Lorem.paragraphs(number: 3).join("\n\n"),
      user:    User.all.sample,
      karma:   rand(-50..500)
    )
    User.all.sample(rand(3..15)).each { |u| post.votes.create!(user: u, value: [-1, 1].sample) }
  end
end

puts "Seed complete."
RUBY

bin/rails db:seed
echo "==> [seeds] done"
