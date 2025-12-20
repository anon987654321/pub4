#!/usr/bin/env zsh
set -euo pipefail

# Database seeding patterns for Rails 8 apps
# Idempotent, realistic fake data with Faker

setup_seed_framework() {
  local app_name="${1:-App}"
  
  log "Setting up seed framework"
  
  install_gem "faker"
  
  cat <<'SEED' > db/seeds.rb
# Rails 8 Seeds - Idempotent with Faker
# Run: bin/rails db:seed (safe to run multiple times)

require 'faker'

puts "Seeding #{Rails.env} database..."

# Seed users (idempotent via find_or_create_by)
users = 10.times.map do |i|
  User.find_or_create_by!(email: "user#{i}@example.com") do |u|
    u.password = "password123"
    u.password_confirmation = "password123"
  end
end

puts "✓ Created #{users.count} users"

# Add your models here following this pattern:
# ModelName.find_or_create_by!(unique_field: value) do |record|
#   record.field = Faker::Lorem.sentence
# end

puts "Seeding complete! #{User.count} users total"
SEED
  
  log "✓ Seed framework ready"
}

generate_seed_for_model() {
  local model="${1}"
  local count="${2:-10}"
  
  cat <<SEED >> db/seeds.rb

# ${model} seeds
${count}.times do
  ${model}.find_or_create_by!(name: Faker::Lorem.word) do |record|
    record.description = Faker::Lorem.paragraph
    record.user = users.sample
  end
end

puts "✓ Created #{${model}.count} ${model} records"
SEED
  
  log "✓ Added ${model} seeds"
}
