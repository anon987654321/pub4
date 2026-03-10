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
  log "Setting up polymorphic associations in models"

  local booking_file="app/models/booking.rb"
  if [[ -f "$booking_file" ]] && ! grep -q "belongs_to :reviewable, polymorphic: true" "$booking_file"; then
    cat >> "$booking_file" << 'EOF'

  # Polymorphic associations for reviews
  has_many :reviews, as: :reviewable
EOF
    log "Added polymorphic associations to Booking model"
  fi
}

validate_models() {
  log "Validating models can be loaded correctly"
  if ! bundle exec rails runner 'puts "All models loaded successfully"'; then
    log "Model validation failed"
    exit 1
  fi
}

cleanup() {
  log "Cleaning up temporary files"
  local temp_file="tmp/migration_cleanup.txt"
  if [[ -f "$temp_file" ]]; then
    rm "$temp_file"
  fi
}

main() {
  log "Starting Airbnb model setup"
  setup_airbnb_models
  run_migration
  setup_polymorphic_associations
  validate_models
  cleanup
  log "Airbnb model setup completed successfully"
}

main "$@"
```
