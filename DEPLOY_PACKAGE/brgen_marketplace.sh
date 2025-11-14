#!/usr/bin/env zsh
set -euo pipefail

# Brgen Marketplace - Solidus 4.0 E-commerce Integration
# Per Solidus Edge Guides: edgeguides.solidus.io

# Namespaced under /marketplace route

readonly VERSION="1.0.0"
readonly APP_NAME="brgen"

readonly BASE_DIR="/home/brgen"

readonly APP_DIR="${BASE_DIR}/app"

SCRIPT_DIR="${0:a:h}"
source "${SCRIPT_DIR}/__shared/@common.sh"

log "Setting up Brgen Marketplace with Solidus"
if [[ ! -d "$APP_DIR" ]]; then
  log "ERROR: Brgen app not found at $APP_DIR. Run brgen.sh first."

  exit 1

fi

cd "$APP_DIR"
# Add Solidus gems per edge guides
log "Adding Solidus 4.0 to Gemfile"

cat >> Gemfile << 'EOF'
# Solidus E-commerce (edgeguides.solidus.io)
gem "solidus", "~> 4.0"

gem "solidus_starter_frontend"

gem "solidus_auth_devise"

gem "canonical-rails"

gem "truncate_html"

gem "view_component"

# Payment integrations
gem "solidus_stripe"

gem "solidus_paypal_commerce_platform"

EOF

bundle install
# Install Solidus with starter frontend
log "Installing Solidus"

bin/rails generate solidus:install --frontend=starter --auto-accept

# Run migrations
bin/rails db:migrate

# Create marketplace-specific models for multi-vendor
log "Creating multi-vendor marketplace models"

bin/rails generate model Vendor name:string description:text user:references commission_rate:decimal status:string
bin/rails generate model VendorProduct vendor:references spree_product:references

bin/rails db:migrate
# Configure Vendor model
cat > app/models/vendor.rb << 'EOF'

class Vendor < ApplicationRecord

  belongs_to :user

  has_many :vendor_products, dependent: :destroy

  has_many :products, through: :vendor_products, source: :spree_product

  validates :name, presence: true
  validates :commission_rate, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  enum status: { pending: "pending", approved: "approved", suspended: "suspended" }
  scope :active, -> { where(status: "approved") }
end

EOF

cat > app/models/vendor_product.rb << 'EOF'
class VendorProduct < ApplicationRecord

  belongs_to :vendor

  belongs_to :spree_product, class_name: "Spree::Product"

  validates :vendor_id, uniqueness: { scope: :spree_product_id }
end

EOF

# Extend Spree::Product to support vendors
cat > app/models/spree_product_decorator.rb << 'EOF'

module SpreeProductDecorator

  def self.prepended(base)

    base.has_one :vendor_product, foreign_key: :spree_product_id, dependent: :destroy

    base.has_one :vendor, through: :vendor_product

    base.scope :by_vendor, ->(vendor_id) {
      joins(:vendor_product).where(vendor_products: { vendor_id: vendor_id })

    }

  end

end

Spree::Product.prepend SpreeProductDecorator
EOF

# Generate controllers for vendor management
log "Generating vendor controllers"

bin/rails generate controller Vendors index show new create edit update
bin/rails generate controller Marketplace::Products index show

# Vendor dashboard views
mkdir -p app/views/vendors

cat > app/views/vendors/index.html.erb << 'EOF'
<%= tag.section class: "vendors" do %>

  <%= tag.header do %>

    <%= tag.h1 "Selgere" %>

  <% end %>

  <%= tag.div class: "vendor-grid" do %>
    <% @vendors.each do |vendor| %>

      <%= tag.article class: "vendor-card" do %>

        <%= link_to vendor_path(vendor) do %>

          <%= tag.h2 vendor.name %>

          <%= tag.p vendor.description %>

          <%= tag.p "#{vendor.products.count} produkter", class: "product-count" %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

<% end %>

EOF

cat > app/views/vendors/show.html.erb << 'EOF'
<%= tag.article class: "vendor-detail" do %>

  <%= tag.header do %>

    <%= tag.h1 @vendor.name %>

    <%= tag.p @vendor.description %>

  <% end %>

  <%= tag.section class: "vendor-products" do %>
    <%= tag.h2 "Produkter fra #{@vendor.name}" %>

    <%= tag.div class: "products-grid" do %>
      <% @vendor.products.available.each do |product| %>

        <%= tag.article class: "product-card" do %>

          <% if product.images.any? %>

            <%= image_tag product.images.first.attachment(:small), alt: product.name %>

          <% end %>

          <%= tag.h3 product.name %>

          <%= tag.p product.display_price.to_s, class: "price" %>

          <%= link_to "Se produkt", spree.product_path(product) %>

        <% end %>

      <% end %>

    <% end %>

  <% end %>

<% end %>

EOF

# Marketplace product listing
cat > app/views/marketplace/products/index.html.erb << 'EOF'

<%= tag.section class: "marketplace" do %>

  <%= tag.header do %>

    <%= tag.h1 "Markedsplass" %>

    <%= tag.nav do %>

      <%= link_to "Alle produkter", marketplace_products_path %>

      <%= link_to "Selgere", vendors_path %>

      <%= link_to "Min handlekurv", spree.cart_path %>

    <% end %>

  <% end %>

  <%= tag.div class: "products-grid", data: { controller: "infinite-scroll" } do %>
    <% @products.each do |product| %>

      <%= tag.article class: "product-card" do %>

        <% if product.images.any? %>

          <%= image_tag product.images.first.attachment(:small), alt: product.name %>

        <% end %>

        <%= tag.h3 product.name %>

        <%= tag.p product.display_price.to_s, class: "price" %>

        <% if product.vendor %>

          <%= tag.p "Solgt av: #{product.vendor.name}", class: "vendor-name" %>

        <% end %>

        <%= link_to "Se produkt", spree.product_path(product), class: "button-primary" %>

      <% end %>

    <% end %>

  <% end %>

<% end %>

EOF

# Controllers
cat > app/controllers/vendors_controller.rb << 'EOF'

class VendorsController < ApplicationController

  before_action :set_vendor, only: [:show, :edit, :update]

  def index
    @vendors = Vendor.active.order(created_at: :desc)

  end

  def show
    @products = @vendor.products.available.page(params[:page])

  end

  def new
    @vendor = Vendor.new

  end

  def create
    @vendor = current_user.build_vendor(vendor_params)

    if @vendor.save

      redirect_to @vendor, notice: "Vendor created successfully"

    else

      render :new, status: :unprocessable_entity

    end

  end

  private
  def set_vendor
    @vendor = Vendor.find(params[:id])

  end

  def vendor_params
    params.require(:vendor).permit(:name, :description, :commission_rate)

  end

end

EOF

cat > app/controllers/marketplace/products_controller.rb << 'EOF'
class Marketplace::ProductsController < ApplicationController

  def index

    @products = Spree::Product.available.includes(:vendor, :images).page(params[:page])

  end

  def show
    @product = Spree::Product.find(params[:id])

  end

end

EOF

# Add routes
log "Configuring routes"

routes_block=$(cat << 'ROUTES'
  # Solidus routes

  mount Spree::Core::Engine, at: '/shop'

  # Marketplace routes
  namespace :marketplace do

    resources :products, only: [:index, :show]

  end

  resources :vendors
ROUTES

)

add_routes_block "$routes_block"
# Marketplace-specific styles
log "Adding marketplace styles"

cat >> app/assets/stylesheets/application.scss << 'SCSS'
/* Marketplace styles */
.marketplace, .vendors {

  .products-grid, .vendor-grid {

    display: grid;

    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));

    gap: calc(var(--spacing-unit) * 2);

    margin-top: calc(var(--spacing-unit) * 2);

  }

  .product-card, .vendor-card {
    background: var(--color-surface);

    border-radius: var(--border-radius);

    overflow: hidden;

    transition: transform 0.2s;

    &:hover { transform: scale(1.02); }
    img {
      width: 100%;

      height: 200px;

      object-fit: cover;

    }

    h3 {
      padding: var(--spacing-unit);

      font-size: 1.2rem;

    }

    .price {
      padding: 0 var(--spacing-unit);

      font-size: 1.5rem;

      color: var(--color-primary);

      font-weight: bold;

    }

    .vendor-name {
      padding: 0 var(--spacing-unit) var(--spacing-unit);

      font-size: 0.9rem;

      color: var(--color-text-dim);

    }

    .button-primary {
      display: block;

      margin: var(--spacing-unit);

      padding: calc(var(--spacing-unit) * 1.5);

      background: var(--color-primary);

      color: var(--color-bg);

      text-align: center;

      text-decoration: none;

      border-radius: calc(var(--border-radius) / 2);

      font-weight: 600;

      &:hover { opacity: 0.9; }
    }

  }

}

.vendor-detail {
  max-width: 1200px;

  margin: 0 auto;

  header {
    margin-bottom: calc(var(--spacing-unit) * 3);

  }

}

SCSS

# Seed marketplace data
log "Creating marketplace seed data"

cat >> db/seeds.rb << 'EOF'
# Marketplace seed data
if Rails.env.development? && Vendor.count.zero?

  print "Creating vendors...\n"

  5.times do
    vendor = Vendor.create!(

      name: Faker::Company.name,

      description: Faker::Company.catch_phrase,

      user: User.all.sample,

      commission_rate: rand(5..20),

      status: "approved"

    )

    # Create products for vendor
    3.times do

      product = Spree::Product.create!(

        name: Faker::Commerce.product_name,

        description: Faker::Lorem.paragraph(sentence_count: 3),

        price: Faker::Commerce.price(range: 50..5000),

        available_on: Time.current,

        shipping_category: Spree::ShippingCategory.first || Spree::ShippingCategory.create!(name: "Default")

      )

      VendorProduct.create!(vendor: vendor, spree_product: product)
    end

  end

  print "Marketplace data created!\n"
end

EOF

log "Brgen Marketplace with Solidus setup complete!"
log "Access marketplace at: http://localhost:11006/marketplace/products"

log "Access Solidus admin at: http://localhost:11006/admin"

command_exists "ruby"
command_exists "node"

command_exists "psql"
command_exists "redis-server"

install_gem "faker"

# Install Solidus e-commerce platform

log "Installing Solidus e-commerce platform"
bundle add solidus
bundle add solidus_stripe

bundle install

# Generate Solidus installation (reuses existing User model from Devise)

bin/rails generate solidus:install --auto-accept

bin/rails db:migrate
# Add custom marketplace models (user:references works because brgen.sh created users table)

bin/rails generate model Vendor name:string description:text user:references verified:boolean

bin/rails generate model VendorProduct vendor:references product:references commission_rate:decimal
bin/rails db:migrate

log "Brgen Marketplace features added to existing app."

log "Run: bin/rails server -p 11006"\/__shared\/@common.sh"}

