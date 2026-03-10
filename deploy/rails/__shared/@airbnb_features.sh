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
    log "Migration failed, attempting rollback"
    if ! bundle exec rails db:rollback; then
      log "Rollback also failed, manual intervention required"
      exit 1
    fi
    log "Rollback successful, exiting"
    exit 1
  fi
}

setup_airbnb_models() {
  local models=(
    "Booking listing:references host:references check_in:date check_out:date guests_count:integer total_price:decimal status:string"
    "Review reviewable:references{polymorphic} reviewer:references{polymorphic} rating:integer content:text cleanliness:integer accuracy:integer communication:integer location:integer value:integer"
    "Availability listing:references date:date available:boolean price_override:decimal"
    "HostProfile user:references bio:text response_rate:decimal response_time:integer verified:boolean joined_date:date languages:string superhost:boolean"
    "Amenity name:string category:string icon:string"
    "ListingAmenity listing:references amenity:references"
  )

  for model in "${models[@]}"; do
    local model_name=$(echo $model | awk '{print $1}')
    local attributes=$(echo $model | cut -d' ' -f2-)
    if check_model_exists $model_name; then
      log "Generating model: $model_name with attributes: $attributes"
      if ! bundle exec rails generate model $model_name $attributes; then
        log "Failed to generate model: $model_name"
        exit 1
      fi
    fi
  done

  log "Airbnb models generated"
}

setup_polymorphic_associations() {
  log "Setting up polymorphic associations for Review model"

  local review_model="app/models/review.rb"
  if [[ ! -f "$review_model" ]]; then
    log "Review model not found, cannot set up polymorphic associations"
    exit 1
  fi

  if ! grep -q "belongs_to :reviewable, polymorphic: true" "$review_model"; then
    cat >> "$review_model" << 'EOF'

  belongs_to :reviewable, polymorphic: true
  belongs_to :reviewer, polymorphic: true
EOF
    log "Added polymorphic associations to Review model"
  else
    log "Polymorphic associations already present in Review model"
  fi
}

add_validations() {
  log "Adding validations to models"

  # Add validations to Booking model
  local booking_model="app/models/booking.rb"
  if [[ -f "$, :total_price, :status, presence: true" "$booking_model";check_in, :check_out, :guests_count, :total_price, :status, presence: true
  validates :guests_count, numericality: { only_integer: true, greater_than: 0 }
  validates :total_price, numericality: { greater_than_or_equal_to_in

  private

  def check_out_after_check_in
    validations to Booking model"
    fi
  fi

  # Add validations to Review model
  local review_model="app/models/review.rb"
  if [[ -f "$review_model" ]]; then
    if ! grep -q "validates :rating, numericality: { in: 1..5 }" "$review_model"; then
      cat >> "$review_model" << 'EOF'

  validates :rating, numericality: { in: 1..5 }
  validates :content, length: { maximum: 1000 }
EOF
      log "Added validations to Review model"
    fi
  fi
}

main() {
  log "Starting Airbnb marketplace features setup"

  setup_airbnb_models || exit 1
  run_migration || exit  add_validations || exit 1

  log "Airbnb marketplace features setup completed successfully"
}

main "$@"
```
