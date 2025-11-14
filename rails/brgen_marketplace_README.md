# BRGEN Marketplace - Multi-vendor E-commerce Platform
## Overview

BRGEN Marketplace is a comprehensive multi-vendor e-commerce platform built on the Solidus e-commerce framework. It provides a complete solution for online marketplaces with vendor management, payment processing, inventory tracking, and advanced search capabilities.
## Features

### Core E-commerce Features

- **Multi-vendor Support**: Independent vendor stores with commission tracking

- **Product Management**: Comprehensive catalog with variants, options, and inventory

- **Order Processing**: Complete order lifecycle from cart to fulfillment

- **Payment Integration**: Multiple payment gateways including Stripe
- **Shipping Management**: Flexible shipping rules and carrier integration
- **Tax Calculation**: Automated tax computation based on location
### Vendor Features
- **Vendor Dashboard**: Complete store management interface
- **Product Listing**: Easy product creation and management
- **Order Management**: Track and fulfill customer orders

- **Analytics**: Sales reports and performance metrics
- **Commission Tracking**: Transparent revenue sharing
- **Verification System**: Trust badges and seller verification
### Customer Features
- **Advanced Search**: Full-text search with filters and facets
- **Product Reviews**: Customer reviews and ratings system
- **Wishlist**: Save products for later purchase

- **Order Tracking**: Real-time order status updates
- **Social Shopping**: Share products and reviews
- **Mobile Optimized**: Responsive design for all devices
## Technical Implementation
### Architecture
#### Solidus Integration
```ruby

# Gemfile additions for marketplace functionality

gem 'solidus', github: 'solidusio/solidus'

gem 'solidus_auth_devise', github: 'solidusio/solidus_auth_devise'
gem 'solidus_searchkick', github: 'solidusio-contrib/solidus_searchkick'
gem 'solidus_reviews', github: 'solidusio-contrib/solidus_reviews'
gem 'solidus_stripe'
gem 'solidus_multi_vendor'
```
#### Custom Models
##### Vendor Model
```ruby
class Vendor < ApplicationRecord

  belongs_to :user

  has_many :vendor_products, dependent: :destroy
  has_many :products, through: :vendor_products
  has_many :listings, dependent: :destroy
  has_one_attached :logo
  has_many_attached :verification_documents
  validates :name, presence: true, uniqueness: true
  validates :description, presence: true
  validates :commission_rate, presence: true, numericality: { in: 0..100 }
  enum status: { pending: 0, active: 1, suspended: 2, banned: 3 }

  enum verification_status: { unverified: 0, pending_verification: 1, verified: 2, rejected: 3 }
  scope :active, -> { where(status: :active) }
  scope :verified, -> { where(verification_status: :verified) }

  def revenue_for_period(start_date, end_date)
    orders = Spree::Order.joins(line_items: { product: :vendor_products })

                        .where(vendor_products: { vendor: self })
                        .where(completed_at: start_date..end_date)

                        .where(payment_state: 'paid')
    orders.sum do |order|
      order.line_items.joins(product: :vendor_products)
           .where(vendor_products: { vendor: self })
           .sum { |item| item.total * (commission_rate / 100.0) }

    end
  end
  def total_sales
    Spree::Order.joins(line_items: { product: :vendor_products })
                .where(vendor_products: { vendor: self })
                .where(payment_state: 'paid')

                .sum(:total)
  end
  def average_rating
    reviews = Spree::Review.joins(product: :vendor_products)
                          .where(vendor_products: { vendor: self })
    return 0 if reviews.empty?

    reviews.average(:rating).to_f.round(2)
  end
end

```
##### VendorProduct Model
```ruby
class VendorProduct < ApplicationRecord
  belongs_to :vendor

  belongs_to :product, class_name: 'Spree::Product'
  validates :commission_rate, presence: true, numericality: { in: 0..100 }
  validates :vendor_id, uniqueness: { scope: :product_id }
  delegate :name, :description, :price, :available?, to: :product
  def vendor_commission(order_total)

    order_total * (commission_rate / 100.0)
  end

  def marketplace_commission(order_total)

    order_total * ((100 - commission_rate) / 100.0)
  end
end

```
##### Enhanced Product Model
```ruby
# Extend Spree::Product with marketplace features
Spree::Product.class_eval do

  has_many :vendor_products, dependent: :destroy
  has_many :vendors, through: :vendor_products
  has_many :reviews, class_name: 'Spree::Review', dependent: :destroy
  scope :by_vendor, ->(vendor) { joins(:vendor_products).where(vendor_products: { vendor: vendor }) }
  scope :featured, -> { where(featured: true) }
  scope :on_sale, -> { joins(:prices).where('spree_prices.amount < spree_prices.compare_at_amount') }
  def primary_vendor

    vendors.first
  end
  def vendor_price(vendor)

    vendor_products.find_by(vendor: vendor)&.price || price
  end
  def in_stock?

    master.in_stock?
  end
  def average_rating

    reviews.average(:rating).to_f.round(2)
  end
  def review_count

    reviews.count
  end
end

```
### Controllers
#### Marketplace Controller
```ruby
class MarketplaceController < ApplicationController

  before_action :set_vendor, only: [:vendor_show, :vendor_products]

  def index
    @featured_products = Spree::Product.featured.available.limit(8)
    @categories = Spree::Taxon.roots
    @vendors = Vendor.active.verified.limit(6)

    # Analytics data for homepage
    @stats = {
      total_products: Spree::Product.available.count,
      total_vendors: Vendor.active.count,

      total_orders: Spree::Order.complete.count,
      happy_customers: Spree::User.joins(:orders).distinct.count
    }
  end
  def search
    @search_term = params[:q]
    @products = search_products(@search_term)
    @filters = build_search_filters

    respond_to do |format|
      format.html
      format.json { render json: serialize_search_results(@products) }
    end

  end
  def vendor_show
    @products = @vendor.products.available.page(params[:page])
    @reviews = @vendor.reviews.recent.limit(5)
  end

  def vendor_products
    @products = @vendor.products.available
    @products = filter_vendor_products(@products)
    @products = @products.page(params[:page])

    respond_to do |format|
      format.html
      format.json { render json: @products }
    end

  end
  private
  def set_vendor
    @vendor = Vendor.active.find(params[:vendor_id] || params[:id])
  end

  def search_products(query)

    return Spree::Product.none if query.blank?
    products = Spree::Product.available
    # Use Searchkick for full-text search

    if defined?(Searchkick)
      products = products.search(

        query,

        fields: [:name, :description, :keywords],
        match: :word_start,
        boost_by: [:popularity, :rating],
        boost_where: { available: true },
        page: params[:page],
        per_page: 20
      )
    else
      # Fallback to basic SQL search
      products = products.where(
        "name ILIKE ? OR description ILIKE ?",
        "%#{query}%", "%#{query}%"
      ).page(params[:page])
    end
    apply_search_filters(products)
  end
  def apply_search_filters(products)
    # Price range filter

    if params[:min_price].present? || params[:max_price].present?
      price_range = [params[:min_price].to_f, params[:max_price].to_f]

      products = products.joins(:master).where(
        spree_variants: { price: price_range[0]..price_range[1] }
      )
    end
    # Category filter
    if params[:category].present?
      products = products.joins(:taxons).where(
        spree_taxons: { name: params[:category] }

      )
    end
    # Vendor filter
    if params[:vendor].present?
      products = products.by_vendor(Vendor.find(params[:vendor]))
    end

    # Rating filter
    if params[:min_rating].present?
      min_rating = params[:min_rating].to_f
      products = products.joins(:reviews)

                        .group('spree_products.id')
                        .having('AVG(spree_reviews.rating) >= ?', min_rating)
    end
    # Availability filter
    products = products.in_stock if params[:in_stock] == 'true'
    products
  end

  def build_search_filters
    {

      categories: Spree::Taxon.roots.pluck(:name, :id),
      vendors: Vendor.active.pluck(:name, :id),

      price_ranges: [
        { label: "Under $25", min: 0, max: 25 },
        { label: "$25 - $50", min: 25, max: 50 },
        { label: "$50 - $100", min: 50, max: 100 },
        { label: "$100+", min: 100, max: nil }
      ]
    }
  end
  def filter_vendor_products(products)
    # Apply category filter
    if params[:category].present?
      products = products.joins(:taxons).where(

        spree_taxons: { name: params[:category] }
      )
    end
    # Apply sorting
    case params[:sort]
    when 'price_low'
      products.joins(:master).order('spree_variants.price ASC')

    when 'price_high'
      products.joins(:master).order('spree_variants.price DESC')
    when 'rating'
      products.joins(:reviews)
              .group('spree_products.id')
              .order('AVG(spree_reviews.rating) DESC')
    when 'newest'
      products.order(created_at: :desc)
    else
      products.order(:name)
    end
  end
  def serialize_search_results(products)
    products.map do |product|
      {
        id: product.id,

        name: product.name,
        description: truncate(product.description, length: 100),
        price: product.price.to_s,
        image_url: product.display_image.present? ? main_app.url_for(product.display_image) : nil,
        vendor: product.primary_vendor&.name,
        rating: product.average_rating,
        review_count: product.review_count,
        url: spree.product_path(product)
      }
    end
  end
end
```
#### Vendor Dashboard Controller
```ruby
class VendorDashboardController < ApplicationController
  before_action :authenticate_user!

  before_action :ensure_vendor_access
  before_action :set_vendor
  def index
    @stats = calculate_vendor_stats
    @recent_orders = recent_vendor_orders.limit(10)
    @top_products = top_selling_products.limit(5)

    @pending_reviews = pending_vendor_reviews.limit(5)
  end
  def products
    @products = @vendor.products.includes(:vendor_products, :reviews)
    @products = @products.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
    @products = @products.page(params[:page])

  end
  def orders
    @orders = vendor_orders
    @orders = filter_orders(@orders)
    @orders = @orders.page(params[:page])

  end
  def analytics
    @period = params[:period] || '30_days'
    @analytics_data = VendorAnalyticsService.new(@vendor, @period).call
  end

  def settings
    # Vendor settings and configuration
  end
  private

  def set_vendor
    @vendor = current_user.vendor || current_user.build_vendor
  end

  def ensure_vendor_access

    redirect_to new_vendor_application_path unless current_user.vendor&.active?
  end
  def calculate_vendor_stats

    {
      total_revenue: @vendor.revenue_for_period(30.days.ago, Time.current),
      total_orders: vendor_orders.count,

      total_products: @vendor.products.count,
      average_rating: @vendor.average_rating,
      pending_orders: vendor_orders.where(shipment_state: 'pending').count
    }
  end
  def recent_vendor_orders
    Spree::Order.joins(line_items: { product: :vendor_products })
                .where(vendor_products: { vendor: @vendor })
                .where(state: 'complete')

                .order(completed_at: :desc)
  end
  def vendor_orders
    Spree::Order.joins(line_items: { product: :vendor_products })
                .where(vendor_products: { vendor: @vendor })
                .distinct

  end
  def top_selling_products
    @vendor.products
           .joins(:line_items)
           .group('spree_products.id')

           .order('SUM(spree_line_items.quantity) DESC')
  end
  def pending_vendor_reviews
    Spree::Review.joins(product: :vendor_products)
                 .where(vendor_products: { vendor: @vendor })
                 .where(approved: false)

  end
  def filter_orders(orders)
    orders = orders.where(state: params[:status]) if params[:status].present?
    orders = orders.where("completed_at >= ?", params[:start_date]) if params[:start_date].present?
    orders = orders.where("completed_at <= ?", params[:end_date]) if params[:end_date].present?

    orders
  end
end
```
### Services
#### Vendor Analytics Service
```ruby
class VendorAnalyticsService

  def initialize(vendor, period = '30_days')

    @vendor = vendor
    @period = period
    @start_date = calculate_start_date
    @end_date = Time.current
  end
  def call
    {
      revenue_data: calculate_revenue_data,
      product_performance: calculate_product_performance,

      customer_metrics: calculate_customer_metrics,
      order_trends: calculate_order_trends,
      conversion_rates: calculate_conversion_rates
    }
  end
  private
  def calculate_start_date
    case @period
    when '7_days' then 7.days.ago

    when '30_days' then 30.days.ago

    when '90_days' then 90.days.ago
    when '1_year' then 1.year.ago
    else 30.days.ago
    end
  end
  def calculate_revenue_data
    orders = vendor_orders_in_period
    daily_revenue = orders.group_by_day(:completed_at, range: @start_date..@end_date)
                          .sum(:total)

    {
      total_revenue: orders.sum(:total),

      daily_revenue: daily_revenue,
      average_order_value: orders.average(:total).to_f.round(2),

      commission_earned: calculate_commission_earned(orders)
    }
  end
  def calculate_product_performance
    products = @vendor.products
                      .joins(:line_items)
                      .joins("JOIN spree_orders ON spree_line_items.order_id = spree_orders.id")

                      .where("spree_orders.completed_at >= ?", @start_date)
                      .group('spree_products.id, spree_products.name')
                      .select('spree_products.*, SUM(spree_line_items.quantity) as total_sold, SUM(spree_line_items.amount) as total_revenue')
                      .order('total_sold DESC')
                      .limit(10)
    products.map do |product|
      {
        name: product.name,
        units_sold: product.total_sold,

        revenue: product.total_revenue,
        views: calculate_product_views(product)
      }
    end
  end
  def calculate_customer_metrics
    orders = vendor_orders_in_period
    customers = Spree::User.joins(:orders)
                          .where(orders: { id: orders.pluck(:id) })

                          .distinct
    {
      total_customers: customers.count,
      new_customers: calculate_new_customers(orders),
      repeat_customers: calculate_repeat_customers(orders),

      customer_lifetime_value: calculate_clv(customers)
    }
  end
  def vendor_orders_in_period
    Spree::Order.joins(line_items: { product: :vendor_products })
                .where(vendor_products: { vendor: @vendor })
                .where(completed_at: @start_date..@end_date)

                .where(payment_state: 'paid')
  end
  def calculate_commission_earned(orders)
    total = 0
    orders.includes(line_items: { product: :vendor_products }).each do |order|
      order.line_items.each do |item|

        vendor_product = item.product.vendor_products.find_by(vendor: @vendor)
        if vendor_product
          total += item.total * (vendor_product.commission_rate / 100.0)
        end
      end
    end
    total
  end
  # Additional helper methods...
end
```
## Frontend Components

### Search Controller (Stimulus)
```javascript
import { Controller } from "@hotwired/stimulus"

import debounce from "stimulus-debounce"

export default class extends Controller {
  static targets = ["input", "results", "filters"]
  static values = {
    url: String,

    minLength: { type: Number, default: 2 }
  }
  connect() {
    this.search = debounce(this.search, 300).bind(this)
  }
  search() {

    const query = this.inputTarget.value.trim()
    if (query.length < this.minLengthValue) {
      this.clearResults()

      return
    }

    this.showLoading()
    const params = new URLSearchParams({
      q: query,
      ...this.getActiveFilters()

    })

    fetch(`${this.urlValue}?${params}`, {
      headers: { 'Accept': 'application/json' }
    })
    .then(response => response.json())

    .then(data => this.displayResults(data))
    .catch(error => this.showError(error))
  }
  displayResults(products) {
    if (products.length === 0) {
      this.resultsTarget.innerHTML = '<p class="no-results">No products found</p>'
      return

    }
    const html = products.map(product => `
      <div class="search-result-item">
        <img src="${product.image_url}" alt="${product.name}" loading="lazy">
        <div class="product-info">

          <h3><a href="${product.url}">${product.name}</a></h3>
          <p class="vendor">by ${product.vendor}</p>
          <p class="description">${product.description}</p>
          <div class="price-rating">
            <span class="price">$${product.price}</span>
            <span class="rating">★ ${product.rating} (${product.review_count})</span>
          </div>
        </div>
      </div>
    `).join('')
    this.resultsTarget.innerHTML = html
  }
  filter(event) {
    const filterType = event.target.dataset.filterType

    const filterValue = event.target.value
    // Update active filters

    this.updateFilter(filterType, filterValue)
    // Re-run search with new filters
    this.search()

  }
  getActiveFilters() {

    const filters = {}
    this.filtersTarget.querySelectorAll('input:checked, select').forEach(input => {
      if (input.value) {

        filters[input.name] = input.value
      }

    })
    return filters
  }
  showLoading() {
    this.resultsTarget.innerHTML = '<div class="loading">Searching...</div>'

  }
  clearResults() {

    this.resultsTarget.innerHTML = ''
  }
  showError(error) {

    this.resultsTarget.innerHTML = '<p class="error">Search failed. Please try again.</p>'
    console.error('Search error:', error)
  }

}
```
## Installation & Setup
### Requirements
- Rails 8.0+
- PostgreSQL 12+

- Redis 6+

- Node.js 18+
- ImageMagick (for image processing)
### Installation Steps
```bash
# Run the marketplace setup script
./rails/brgen/marketplace.sh

# Install Solidus and extensions
bundle exec rails generate solidus:install --auto-accept
bundle exec rails generate solidus_searchkick:install
bundle exec rails generate solidus_reviews:install

# Configure payment methods
bundle exec rails generate solidus_stripe:install
# Set up sample data
bundle exec rails runner "Spree::Core::Engine.load_seed"

bundle exec rake db:seed:marketplace
# Start the application

bundle exec rails server
```
### Configuration

#### Payment Configuration
```ruby
# config/initializers/spree.rb

Spree.config do |config|

  config.currency = "USD"
  config.default_country_iso = "US"
  config.checkout_zone = "North America"
  config.track_inventory_levels = true
end
# Stripe configuration
Spree::Config.set({
  stripe_publishable_key: ENV['STRIPE_PUBLISHABLE_KEY'],
  stripe_secret_key: ENV['STRIPE_SECRET_KEY']

})
```
#### Search Configuration
```ruby
# config/initializers/searchkick.rb
Searchkick.configure do |config|

  config.search_timeout = 15
  config.timeout = 5
  config.models = [Spree::Product]
end
# Enable search for products
Spree::Product.class_eval do
  searchkick word_start: [:name, :description]
  def search_data

    {
      name: name,
      description: description,

      price: price,
      available: available?,
      vendor: primary_vendor&.name,
      category: taxons.pluck(:name),
      rating: average_rating,
      popularity: popularity_score
    }
  end
end
```
## API Documentation
### Product Search API
```
GET /api/v1/products/search?q=keyword&category=electronics&min_price=10&max_price=100

```

### Vendor API
```
GET /api/v1/vendors/:id/products
POST /api/v1/vendors/:id/products

PUT /api/v1/vendors/:id/products/:product_id
DELETE /api/v1/vendors/:id/products/:product_id
```
### Order Management API
```
GET /api/v1/vendors/:id/orders
PUT /api/v1/vendors/:id/orders/:order_id/ship

POST /api/v1/vendors/:id/orders/:order_id/refund
```
## Testing
### Test Suite
```bash
# Run marketplace tests

bin/rails test test/models/vendor_test.rb

bin/rails test test/controllers/marketplace_controller_test.rb
bin/rails test test/services/vendor_analytics_service_test.rb
# Integration tests
bin/rails test:system test/system/marketplace_test.rb
```
### Performance Testing

```bash
# Search performance
ab -n 100 -c 10 "http://localhost:3000/marketplace/search?q=laptop"

# Vendor dashboard load test
ab -n 50 -c 5 "http://localhost:3000/vendor/dashboard"
```
## Deployment

### Production Configuration
```yaml
# docker-compose.yml

version: '3.8'

services:
  app:
    build: .
    environment:
      - RAILS_ENV=production
      - DATABASE_URL=postgresql://user:pass@db:5432/marketplace_production
      - REDIS_URL=redis://redis:6379/0
      - STRIPE_SECRET_KEY=sk_live_...
    depends_on:
      - db
      - redis
      - elasticsearch
  db:
    image: postgres:14
  redis:
    image: redis:7-alpine

  elasticsearch:
    image: elasticsearch:8.5.0

```
### Monitoring & Analytics

#### Business Metrics
- **Gross Merchandise Value (GMV)**: Total sales volume
- **Take Rate**: Platform commission percentage

- **Active Vendors**: Number of selling vendors

- **Customer Acquisition Cost**: Marketing spend efficiency
- **Vendor Satisfaction**: Retention and feedback scores
#### Technical Metrics
- **Search Performance**: Query response times
- **Conversion Rates**: Search to purchase ratios
- **Error Rates**: Failed transactions and API calls

- **Uptime**: Service availability monitoring
## Security Considerations
### Data Protection
- **PCI DSS Compliance**: Secure payment processing
- **GDPR Compliance**: Data privacy and user rights

- **Input Validation**: XSS and injection prevention

- **API Rate Limiting**: Abuse prevention
### Vendor Security
- **Identity Verification**: Know Your Business Customer (KYBC)
- **Product Approval**: Content moderation workflow
- **Financial Controls**: Payout verification and fraud detection

- **Performance Monitoring**: Quality score tracking
## Future Enhancements
### Planned Features
- **AI-powered Recommendations**: Machine learning product suggestions
- **Advanced Analytics**: Predictive analytics for vendors

- **Mobile App**: Native iOS and Android applications

- **International Expansion**: Multi-currency and localization
- **B2B Marketplace**: Wholesale and bulk ordering features
