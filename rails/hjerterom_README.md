# HJERTEROM - Food Redistribution Platform
## Overview

Hjerterom is a comprehensive food redistribution platform built with Rails 8, designed to combat food waste while supporting communities in need. The platform connects food donors (restaurants, stores, individuals) with recipients through a secure, location-based system integrated with Norwegian payment systems and analytics.
## Features

### Core Food Distribution Features

- **Food Donation Management**: Post and manage surplus food with expiration tracking

- **Location-based Discovery**: Find nearby food distributions using Mapbox integration

- **Real-time Availability**: Live updates on food quantities and pickup windows

- **Anonymous Donations**: Option to donate without revealing personal information
- **Distribution Centers**: Organized pickup locations with scheduling
### Norwegian Integration
- **Vipps Integration**: Secure payment processing for optional donations
- **Citizenship Verification**: Norwegian ID integration for eligibility
- **Language Support**: Full Norwegian (Bokmål) localization

- **Compliance**: Meets Norwegian food safety and data protection standards
- **Analytics**: Government-compliant reporting on food waste reduction
### Social Features
- **Community Ratings**: Rate and review food quality and donors
- **Distribution Scheduling**: Coordinate pickup times to prevent overcrowding
- **Impact Tracking**: Personal and community-wide impact metrics

- **Anonymous Feedback**: Provide feedback while maintaining privacy
- **Resource Sharing**: Share transportation and storage resources
## Technical Implementation
### Models & Database Schema
#### Giveaway Model
```ruby

class Giveaway < ApplicationRecord

  belongs_to :user, optional: true

  has_many :claims, dependent: :destroy
  has_many :claimants, through: :claims, source: :user
  has_one_attached :photo
  validates :title, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 1000 }
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :pickup_time, presence: true

  validates :location, presence: true
  enum status: { available: 0, claimed: 1, completed: 2, expired: 3 }
  geocoded_by :location
  after_validation :geocode, if: :location_changed?
  scope :available_now, -> { where(status: 'available').where('pickup_time > ?', Time.current) }

  scope :near_location, ->(lat, lng, radius) { near([lat, lng], radius) }

  scope :by_category, ->(category) { where(category: category) }
  def expired?

    pickup_time < Time.current
  end
  def time_remaining

    return 0 if expired?
    ((pickup_time - Time.current) / 1.hour).round(1)
  end

end
```
#### Distribution Model
```ruby
class Distribution < ApplicationRecord
  has_many :giveaways, dependent: :destroy

  has_many :volunteers, dependent: :destroy
  validates :location, presence: true
  validates :schedule, presence: true
  validates :capacity, presence: true, numericality: { greater_than: 0 }
  geocoded_by :location

  after_validation :geocode, if: :location_changed?
  enum status: { active: 0, inactive: 1, full: 2 }
  def current_load

    giveaways.available_now.sum(:quantity)
  end

  def available_capacity

    capacity - current_load
  end
  def next_distribution

    return nil if schedule.blank?
    # Parse recurring schedule and return next datetime
    next_scheduled_time = parse_schedule(schedule)

    next_scheduled_time if next_scheduled_time > Time.current
  end
  private
  def parse_schedule(schedule_string)
    # Implementation for parsing "daily 14:00", "weekly monday 10:00", etc.
    # Returns next occurrence as DateTime

  end

end
```
#### User Extensions for Vipps Integration
```ruby
class User < ApplicationRecord
  has_many :giveaways, dependent: :destroy

  has_many :claims, dependent: :destroy
  has_many :donations, class_name: 'VippsDonation', dependent: :destroy
  validates :vipps_id, uniqueness: { allow_blank: true }
  validates :citizenship_status, inclusion: { in: %w[citizen resident visitor] }
  enum citizenship_status: { citizen: 0, resident: 1, visitor: 2 }
  def can_claim?

    return false if claim_count >= monthly_limit
    return false unless verified_norwegian?

    true

  end
  def monthly_limit
    case citizenship_status
    when 'citizen' then 10
    when 'resident' then 8

    when 'visitor' then 3
    else 0
    end
  end
  def verified_norwegian?
    vipps_id.present? && citizenship_status.present?
  end
  def impact_score

    donated_items = giveaways.completed.sum(:quantity)
    claimed_items = claims.joins(:giveaway).where(giveaways: { status: 'completed' }).count
    (donated_items * 2) + claimed_items # Weighted towards donation

  end
end
```
### Vipps Integration
#### Payment Processing
```ruby
class VippsService

  include HTTParty

  base_uri 'https://api.vipps.no'
  def initialize
    @client_id = Rails.application.credentials.dig(:vipps, :client_id)
    @client_secret = Rails.application.credentials.dig(:vipps, :client_secret)
    @subscription_key = Rails.application.credentials.dig(:vipps, :subscription_key)

  end
  def create_payment(amount, phone_number, text)
    headers = {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{access_token}",

      'Ocp-Apim-Subscription-Key' => @subscription_key,
      'Vipps-System-Name' => 'Hjerterom',
      'Vipps-System-Version' => '1.0'
    }
    body = {
      customerInfo: { mobileNumber: phone_number },
      merchantInfo: {
        merchantSerialNumber: Rails.application.credentials.dig(:vipps, :merchant_serial),

        callbackPrefix: "#{Rails.application.config.base_url}/vipps/callback",
        fallBack: "#{Rails.application.config.base_url}/donations"
      },
      transaction: {
        orderId: SecureRandom.uuid,
        amount: amount * 100, # Convert to øre
        transactionText: text,
        timeStamp: Time.current.iso8601
      }
    }
    self.class.post('/ecomm/v2/payments', headers: headers, body: body.to_json)
  end
  private
  def access_token

    Rails.cache.fetch('vipps_access_token', expires_in: 1.hour) do
      response = self.class.post('/accesstoken/get', headers: {

        'client_id' => @client_id,

        'client_secret' => @client_secret,
        'Ocp-Apim-Subscription-Key' => @subscription_key
      })
      response.parsed_response['access_token']
    end
  end
end
```
### Analytics Integration
#### Food Waste Tracking
```ruby
class FoodWasteAnalytics

  def self.daily_stats(date = Date.current)

    {
      items_donated: Giveaway.where(created_at: date.beginning_of_day..date.end_of_day).sum(:quantity),
      items_claimed: Claim.joins(:giveaway).where(created_at: date.beginning_of_day..date.end_of_day, giveaways: { status: 'completed' }).count,
      waste_prevented_kg: calculate_waste_prevented(date),
      co2_saved_kg: calculate_co2_savings(date),
      active_users: User.joins(:giveaways, :claims).where(giveaways: { created_at: date.beginning_of_day..date.end_of_day }).distinct.count
    }
  end
  def self.impact_report(user)
    {
      lifetime_donations: user.giveaways.completed.sum(:quantity),
      lifetime_claims: user.claims.joins(:giveaway).where(giveaways: { status: 'completed' }).count,

      estimated_waste_prevented: user.giveaways.completed.sum(:quantity) * 0.5, # Average 500g per item
      community_rank: calculate_user_rank(user),
      carbon_footprint_reduced: calculate_user_carbon_savings(user)
    }
  end
  private
  def self.calculate_waste_prevented(date)
    # Average food item weight in kg multiplied by completed items
    completed_items = Giveaway.where(created_at: date.beginning_of_day..date.end_of_day, status: 'completed').sum(:quantity)

    completed_items * 0.5 # Assume 500g average per item

  end
  def self.calculate_co2_savings(date)
    # Food waste produces ~3.3kg CO2 per kg of food
    waste_prevented_kg = calculate_waste_prevented(date)
    waste_prevented_kg * 3.3

  end
end
```
### Location-based Features
#### Mapbox Integration
```javascript
// app/javascript/maps/food_distribution_map.js

class FoodDistributionMap {

  constructor(containerId) {
    this.map = new mapboxgl.Map({
      container: containerId,
      style: 'mapbox://styles/mapbox/streets-v11',
      center: [10.7522, 59.9139], // Oslo center
      zoom: 12
    });
    this.userLocation = null;
    this.markers = [];
    this.initializeMap();
  }

  initializeMap() {
    this.map.on('load', () => {

      this.getUserLocation();
      this.loadGiveaways();

      this.setupFilters();
    });
  }
  getUserLocation() {
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition((position) => {
        this.userLocation = [position.coords.longitude, position.coords.latitude];

        this.map.setCenter(this.userLocation);
        new mapboxgl.Marker({ color: 'blue' })
          .setLngLat(this.userLocation)
          .addTo(this.map);
      });

    }
  }
  loadGiveaways(filters = {}) {
    fetch('/api/v1/giveaways', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },

      body: JSON.stringify({ filters: filters, location: this.userLocation })
    })
    .then(response => response.json())
    .then(data => this.displayGiveaways(data.giveaways));
  }
  displayGiveaways(giveaways) {
    // Clear existing markers
    this.markers.forEach(marker => marker.remove());
    this.markers = [];

    giveaways.forEach(giveaway => {
      const popup = new mapboxgl.Popup()
        .setHTML(this.createPopupContent(giveaway));
      const marker = new mapboxgl.Marker({

        color: this.getMarkerColor(giveaway.category),
        scale: this.getMarkerSize(giveaway.quantity)
      })

        .setLngLat([giveaway.lng, giveaway.lat])
        .setPopup(popup)
        .addTo(this.map);
      this.markers.push(marker);
    });
  }
  createPopupContent(giveaway) {

    return `
      <div class="giveaway-popup">
        <h3>${giveaway.title}</h3>

        <p><strong>Mengde:</strong> ${giveaway.quantity} porter</p>
        <p><strong>Hentes innen:</strong> ${new Date(giveaway.pickup_time).toLocaleString('no-NO')}</p>
        <p><strong>Avstand:</strong> ${giveaway.distance.toFixed(1)} km</p>
        <a href="/giveaways/${giveaway.id}" class="btn btn-primary btn-sm">Vis detaljer</a>
      </div>
    `;
  }
  getMarkerColor(category) {
    const colors = {
      'vegetables': '#4CAF50',
      'fruit': '#FF9800',

      'bread': '#8BC34A',
      'dairy': '#2196F3',
      'meat': '#F44336',
      'other': '#9C27B0'
    };
    return colors[category] || colors['other'];
  }
  getMarkerSize(quantity) {
    if (quantity > 10) return 1.2;
    if (quantity > 5) return 1.0;
    return 0.8;

  }
}
```
## Installation & Setup
### Prerequisites
- Ruby 3.3.0+
- Rails 8.0.0+

- PostgreSQL 15+

- Redis 7.0+
- Node.js 18+ (for frontend assets)
- Vipps Developer Account (for payment integration)
### Setup Commands
```bash
# Install dependencies
bundle install

yarn install
# Setup database
bin/rails db:create db:migrate db:seed
# Configure credentials
EDITOR=vim bin/rails credentials:edit

# Add:
# vipps:

#   client_id: your_vipps_client_id
#   client_secret: your_vipps_client_secret
#   subscription_key: your_subscription_key
#   merchant_serial: your_merchant_serial
# Start services
bin/rails server
redis-server
```

### Environment Configuration
```bash
# Set environment variables
export MAPBOX_ACCESS_TOKEN=your_mapbox_token

export VIPPS_ENVIRONMENT=sandbox # or production
export DEFAULT_LOCATION_LAT=59.9139
export DEFAULT_LOCATION_LNG=10.7522
```
## Usage Examples
### Creating a Food Donation
```ruby
# Create a new giveaway

giveaway = current_user.giveaways.create!(

  title: "Fersk grønnsaker fra restaurant",
  description: "Overskudd av grønnsaker fra lunsjtilberedning",
  quantity: 5,
  pickup_time: 2.hours.from_now,
  location: "Karl Johans gate 1, Oslo",
  category: "vegetables",
  anonymous: false
)
```
### Processing a Vipps Donation
```ruby
# Create optional donation payment
vipps_service = VippsService.new

payment_response = vipps_service.create_payment(
  50, # 50 NOK
  '+4712345678',
  'Støtte til Hjerterom matdeling'
)
if payment_response['orderId']
  VippsDonation.create!(
    user: current_user,
    amount: 50,

    vipps_order_id: payment_response['orderId'],
    status: 'pending'
  )
end
```
## Architecture
### Food Distribution Workflow
1. **Donation**: Users post available food with location and pickup time
2. **Discovery**: Other users find nearby food through map or search

3. **Claiming**: Users claim food items with automatic scheduling

4. **Pickup**: Coordinate pickup with real-time updates
5. **Completion**: Track successful redistribution for analytics
### Privacy & Security
- **Anonymous Options**: Donate and claim food without revealing identity
- **Location Privacy**: Approximate locations to protect user privacy
- **Secure Payments**: Vipps integration for optional donations

- **Data Protection**: GDPR-compliant data handling
### Norwegian Compliance
- **Food Safety**: Adherence to Norwegian food handling regulations
- **Tax Reporting**: Integration with Norwegian tax authorities for donations
- **Language Support**: Full Norwegian localization with cultural context

## Performance Considerations
- **Location Indexing**: PostGIS for efficient geospatial queries
- **Real-time Updates**: WebSockets for live availability updates
- **Image Processing**: Background processing for food photos

- **Analytics Caching**: Redis caching for impact metrics

- **Mobile Optimization**: Progressive Web App for mobile users
## Framework Compliance
### Master.json v146.1.0 Alignment
- **Idempotency**: All food operations are safely repeatable
- **Reversibility**: Donations can be cancelled before pickup

- **Security_by_design**: Secure user verification and payment processing

- **Composability**: Modular components for donation, claiming, and analytics
### Code Style
- **Norwegian Naming**: Use Norwegian terms for domain concepts (giveaway = "utdeling", claim = "krav")
- **Cultural Sensitivity**: Respect Norwegian social norms around food sharing
- **Accessibility**: WCAG AAA compliance for inclusive design

- **Performance**: Optimized for Norwegian network conditions
---
*Bygget med Rails 8, Vipps, og Mapbox for OpenBSD 7.5 - Bekjemper matsvinn og styrker lokalsamfunn*
