```zsh
#!/usr/bin/env zsh
set -euo pipefail

# Airbnb marketplace features: Bookings, Reviews, Host Profiles, Calendar, Pricing
# Shared across marketplace apps (brgen listings, hjerterom)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

setup_airbnb_models() {
  log "Setting up Airbnb models: Booking, Review, Availability, HostProfile"

  # Generate models with correct polymorphic syntax
  rails generate model Booking listing:references guest:references host:references check_in:date check_out:date guests_count:integer total_price:decimal status:string
  rails generate model Review reviewable:references{polymorphic} reviewer:references{polymorphic} rating:integer content:text cleanliness:integer accuracy:integer communication:integer location:integer value:integer
  rails generate model Availability listing:references date:date available:boolean price_override:decimal
  rails generate model HostProfile user:references bio:text response_rate:decimal response_time:integer verified:boolean joined_date:date languages:string superhost:boolean
  rails generate model Amenity name:string category:string icon:string
  rails generate model ListingAmenity listing:references amenity:references

  log "Airbnb models generated"
}

setup_polymorphic_associations() {
  log "Setting up polymorphic associations in models"

  # Add polymorphic true to Booking model
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

  scope :upcoming, -> { where('check_in >= ?', Date.today) }

  private

  def check_out_after_check_in
    return if check_out.blank? || check_in.blank?
    errors.add(:check_out, "must be after check-in date") if check_out <= check_in
  end

  def listing_available
    # Availability validation logic
  end
end
EOF

  # Create foreign key migration
  cat << 'EOF' > db/migrate/$(date +%Y%m%d%H%M%S)_add_airbnb_foreign_keys.rb
class AddAirbnbForeignKeys < ActiveRecord::Migration[7.0]
  def change
    add_foreign_key :bookings, :listings
    add_foreign_key :bookings, :users, column: :guest_id
    add_foreign_key :bookings, :users, column: :host_id
    add_foreign_key :reviews, :users, column: :reviewer_id
    add_foreign_key :availabilities, :listings
    add_foreign_key :host_profiles, :users
    add_foreign_key :listing_amenities, :listings
    add_foreign_key :listing_amenities, :amenities
  end
end
EOF

  log "Polymorphic associations and foreign keys configured"
}
```
