#!/usr/bin/env sh
set -euo pipefail

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

model_path() {
  printf 'app/models/%s.rb' "${1%:*}"
}

check_model_exists() {
  model_name=$1
  if [ -f "$(model_path "$model_name")" ]; then
    log "Model $model_name already exists, skipping generation"
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
      return 1
    fi
    log "Rollback successful"
    return 1
  fi
}

setup_airbnb_models() {
  # Define models as an array: "ModelName:attributes"
  models=(
    "Booking:listing:references host:references check_in:date check_out:date guests_count:integer total_price:decimal status:string"
    "Review:reviewable:references{polymorphic} reviewer:references{polymorphic} rating:integer content:text cleanliness:integer accuracy:integer communication:integer location:integer value:integer"
    "Availability:listing:references date:date available:boolean price_override:decimal"
    "HostProfile:user:references bio:text response_rate:decimal response_time:integer verified:boolean joined_date:date languages:string superhost:boolean"
    "Amenity:name:string category:string icon:string"
    "ListingAmenity:listing:references amenity:references"
  )

  for entry in "${models[@]}"; do
    model_name=${entry%%:*}
    attributes=${entry#*:}
    if [ -z "$model_name" ]; then
      continue
    fi
    if check_model_exists "$model_name"; then
      log "Generating model $model_name with attributes: $attributes"
      if ! bundle exec rails generate model "$model_name" $attributes; then
        log "Failed to generate model $model_name"
        return 1
      fi
    fi
  done
  log "Airbnb models generated"
}

setup_polymorphic_associations() {
  log "Setting up polymorphic associations for Review model"
  review_file=$(model_path Review)

  if [ ! -f "$review_file" ]; then
    log "Review model not found, cannot set up polymorphic associations"
    return 1
  fi

  snippet='  belongs_to :reviewable, polymorphic: true
  belongs_to :reviewer, polymorphic: true'

  if ! grep -q "belongs_to :reviewable, polymorphic: true" "$review_file"; then
    printf '\n%s\n' "$snippet" >> "$review_file"
    log "Added polymorphic associations to Review model"
  else
    log "Polymorphic associations already present in Review model"
  fi
}

add_validations() {
  log "Adding validations to models"

  booking_file=$(model_path Booking)
  if [ -f "$booking_file" ]; then
    if ! grep -q "validates :check_in, :check_out, :guests_count, :total_price, :status, presence: true" "$booking_file"; then
      cat >> "$booking_file" <<'EOF'

  validates :check_in, :check_out, :guests_count, :total_price, :status, presence: true
  validates :guests_count, numericality: { only_integer: true, greater_than: 0 }
  validates :total_price, numericality: { greater_than_or_equal_to: 0 }
  validate :check_out_after_check_in

  private

  def check_out_after_check_in
    return if check_in.blank? || check_out.blank?
    errors.add(:check_out, "must be after check-in") if check_out <= check_in
  end
EOF
      log "Added validations to Booking model"
    fi
  fi

  review_file=$(model_path Review)
  if [ -f "$review_file" ]; then
    if ! grep -q "validates :rating, numericality: { in: 1..5 }" "$review_file"; then
      cat >> "$review_file" <<'EOF'

  validates :rating, numericality: { in: 1..5 }
  validates :content, length: { maximum: 1000 }
EOF
      log "Added validations to Review model"
    fi
  fi
}

main() {
  log "Starting Airbnb marketplace features setup"

  setup_airbnb_models &&
    setup_polymorphic_associations &&
    run_migration &&
    add_validations

  log "Airbnb marketplace features setup completed successfully"
}

main "$@"