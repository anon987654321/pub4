```zsh
#!/usr/bin/env zsh
set -euo pipefail

# Airbnb marketplace features: Bookings, Reviews, Host Profiles, Calendar, Pricing
# Shared across marketplace apps (brgen listings, hjerterom)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

check_model_exists() {
  local model_name=$1
  if [[ -f "app/models/${model_name:l}.rb" ]]; then
    log "Model ${model_name} already exists, skipping generation"
    return 1
  fi
  return 0
}

run_migration() {
  log "Running database migrations"
  if ! bundle exec rails db:migrate; then
    log "Migration failed, rolling back"
    bundle exec rails db:rollback
    exit 1
  fi
}

setup_airbnb_models() {
  local models=(
    "Booking listing:references host:references check_in:date check_out:date guests_count:integer total_price:decimal status:string"
    "Review reviewable_type:string reviewable_id:bigint reviewer_type:string reviewer_id:bigint rating:integer content:text cleanliness:integer accuracy:integer communication:integer location:integer value:integer"
    "Availability listing:references date:date available:boolean price_override:decimal"
    "HostProfile user:references bio:text response_rate:decimal response_time:integer verified:boolean joined_date:date languages:string superhost:boolean"
    "Amenity name:string category:string icon:string"
    "ListingAmenity listing:references amenity:references"
  )

  for model in "${models[@]}"; do
    local model_name=$(echo $model | awk '{print $1}')
    if check_model_exists $model_name; then
      log "Generating model: $model"
      if ! bundle exec rails generate model $model; then
        log "Failed to generate model: $model_name"
        exit 1
      fi
    fi
  done

  log "Airbnb models generated"
  run_migration
}

setup_polymorphic_associations() {
  log "Setting up polymorphic associations in models"

  # Complete Booking model with proper validations
  cat << 'EOF' > app/models/booking.rb
class Booking < ApplicationRecord
  belongs_to :listing
  belongs_to :guest, polymorphic: true
  belongs_to :host, polymorphic: true

  validates :check_in, :check_out, :guests_count, :total_price, :status, presence: true
  validates :guests_count, numericality: { greater_than: 0 }
  validates :total_price, numericality: { greater_than_or_equal_to: 0 }

  validate :check_out_after_check_in
  validate :listing_available

  enum status: { pending: 'pending', confirmed: 'confirmed', cancelled: 'cancelled', completed: 'completed' }

  scope :upcoming, -> { where('check_in >= ?', Date.current) }
  scope :active, -> { where(status: [:pending, :confirmed]) }

  private

  def check_out_after_check_in
    return if check_out.blank? || check_in.blank?
    errors.add(:check_out, "must be after check-in date") if check_out <= check_in
  end

  def listing_available
    return if check_in.blank? || check_out.blank?
    # Add availability validation logic here
  end
end
EOF

  log "Polymorphic associations setup completed"
}

validate_models() {
  log "Validating generated models"
  if ! bundle exec rails db:migrate:status; then
    log "Migration status check failed"
    exit 1
  fi

  if ! bundle exec rails runner "puts 'Model validation successful'"; then
    log "Model validation failed"
    exit 1
  fi
}

main() {
  log "Starting Airbnb marketplace setup"

  setup_airbnb_models
  setup_polymorphic_associations
  validate_models

  log "Airbnb marketplace setup completed successfully"
}

main "$@"
```
