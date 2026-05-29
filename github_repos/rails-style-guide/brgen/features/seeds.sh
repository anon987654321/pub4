#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

# Absolute path to the Rails application
readonly APP_DIR="/home/brgen/app"

# Verify the application directory exists
if [[ ! -d "${APP_DIR}" ]]; then
  echo "Error: APP_DIR '${APP_DIR}' does not exist" >&2
  exit 1
fi
cd "${APP_DIR}"

# Create a temporary seed file; ensure it is removed on exit or interrupt
SEED_FILE="$(mktemp db/seeds_tmp.XXXXXX.rb)"
trap 'rm -f "${SEED_FILE}"' EXIT TERM INT

cat > "${SEED_FILE}" <<'RUBY'
return unless Rails.env.development?

puts "Creating communities..."
%w[Oslo Bergen Trondheim Stavanger Tromsø].each do |city|
  Community.find_or_create_by!(subdomain: city.downcase) do |c|
    c.name        = "#{city} Community"
    c.slug        = city.parameterize
    c.description = "Local community for #{city}"
  end
end

puts "Creating users..."
Faker::UniqueGenerator.clear
10.times do
  email = Faker::Internet.unique.email
  User.find_or_create_by!(email: email) do |u|
    u.password              = "password123"
    u.password_confirmation = "password123"
    u.username              = Faker::Internet.unique.username
    u.karma                 = rand(0..1_000)
  end
end

puts "Creating posts..."
Community.find_each do |community|
  20.times do
    post = community.posts.find_or_initialize_by(
      title:   Faker::Lorem.sentence(word_count: 5),
      content: Faker::Lorem.paragraphs(number: 3).join("\n\n"),
      user:    User.order("RANDOM()").first
    )
    post.karma = rand(-50..500)
    post.save!

    voters = User.order("RANDOM()").limit(rand(3..15))
    voters.each do |v|
      post.votes.find_or_create_by!(user: v) do |vote|
        vote.value = [-1, 1].sample
      end
    end
  end
end

puts "Seed complete."
RUBY

# Execute the temporary seed file within the Rails environment using the binstub
bin/rails runner "${SEED_FILE}"

echo "==> [seeds] done"
