#!/usr/bin/env zsh
# brgen_marketplace.sh — Brgen Marketplace (Amazon clone on Solidus)
# Usage: zsh brgen_marketplace.sh
set -euo pipefail

APP_NAME=brgen_marketplace
APP_DIR=/home/${APP_NAME}/app
APP_PORT=10009
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/spree/product.rb" && exit 0

log "Brgen Marketplace — Amazon-style e-commerce on Solidus"

# ── Create app ─────────────────────────────────────────────────────────────
mkdir -p "${APP_DIR:h}"
if [[ ! -f "${APP_DIR}/config/application.rb" ]]; then
  log "Creating Rails 8 app at $APP_DIR"
  rails new "$APP_DIR" \
    --database=sqlite3 \
    --asset-pipeline=propshaft \
    --javascript=importmap \
    --skip-git
fi
cd "$APP_DIR"
log_ok "Working in: $APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem solidus
add_gem solidus_auth_devise
add_gem solidus_starter_frontend
add_gem pagy
install_solid_stack
install_security_tools

# ── Solidus install ─────────────────────────────────────────────────────────
log "Installing Solidus"
bin/rails g solidus:install \
  --payment-method=none \
  --admin-email=admin@brgen.no \
  --admin-password=admin1234 \
  --auto-accept 2>/dev/null || true

log "Installing Solidus auth"
bin/rails g solidus:auth:install 2>/dev/null || true

log "Installing Solidus starter frontend"
bin/rails g solidus:starter:frontend:install 2>/dev/null || true

bin/rails db:migrate
log_ok "Solidus installed"

# ── Seller extension ─────────────────────────────────────────────────────────
# Add seller profile so multiple vendors can list products
bin/rails generate model SellerProfile \
  spree_user_id:integer:uniq \
  name:string bio:text \
  approved:boolean:default[false] \
  stripe_account_id:string \
  --no-test-framework

bin/rails generate model SellerProduct \
  seller_profile:references spree_product_id:integer \
  commission_rate:decimal \
  --no-test-framework

bin/rails db:migrate

cat > app/models/seller_profile.rb << 'RUBY'
class SellerProfile < ApplicationRecord
  belongs_to :user, class_name: "Spree::User", foreign_key: :spree_user_id
  has_many :seller_products, dependent: :destroy
  has_many :products, through: :seller_products, source_type: "Spree::Product"

  validates :name, presence: true, length: { maximum: 100 }
  validates :spree_user_id, uniqueness: true

  scope :approved, -> { where(approved: true) }
end
RUBY

# ── Solidus production config ─────────────────────────────────────────────────
cat >> config/initializers/spree.rb << 'RUBY' 2>/dev/null || cat > config/initializers/spree.rb << 'RUBY'
Spree.config do |config|
  config.site_name = "Brgen Marketplace"
  config.mails_from = "no-reply@brgen.no"
end
RUBY

# ── Pagy integration ─────────────────────────────────────────────────────────
mkdir -p config/initializers
cat > config/initializers/pagy.rb << 'RUBY'
require "pagy/extras/overflow"
Pagy::OPTIONS[:limit]    = 24
Pagy::OPTIONS[:overflow] = :last_page
RUBY

cat >> app/helpers/application_helper.rb << 'RUBY'

  include Pagy::Frontend
RUBY

# ── Custom storefront CSS ─────────────────────────────────────────────────────
mkdir -p app/assets/stylesheets
cat >> app/assets/stylesheets/application.css << 'CSS'
:root {
  --amazon-navy: #131921; --amazon-orange: #febd69; --amazon-btn: #f0c14b;
  --amazon-btn-border: #a88734; --text: #0f1111; --text-dim: #565959;
  --surface: #fff; --border: #ddd; --radius: 4px;
}
.topbar { background: var(--amazon-navy); color: #fff; padding: .5rem 1rem; display: flex; gap: 1rem; align-items: center; }
.topbar .logo { font-size: 1.4rem; font-weight: 700; color: var(--amazon-orange); }
.topbar a { color: #fff; font-size: .85rem; }
.search-bar { display: flex; flex: 1; max-width: 800px; margin: 0 auto; }
.search-bar input { flex: 1; padding: .5rem .75rem; border: none; border-radius: 4px 0 0 4px; font-size: 1rem; }
.search-bar button { background: var(--amazon-orange); border: none; padding: 0 1rem; border-radius: 0 4px 4px 0; cursor: pointer; font-size: 1.1rem; }
.product-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; padding: 1rem; }
.product-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); padding: 1rem; }
.product-card img { width: 100%; aspect-ratio: 1; object-fit: contain; margin-bottom: .5rem; }
.product-card .name { font-size: .9rem; color: var(--text); margin-bottom: .25rem; }
.product-card .price { font-size: 1.1rem; font-weight: 700; color: #b12704; }
.product-card .rating { color: #f0a500; font-size: .8rem; }
.btn-cart { background: var(--amazon-btn); border: 1px solid var(--amazon-btn-border); border-radius: var(--radius); padding: .4rem 1rem; cursor: pointer; font-size: .9rem; width: 100%; margin-top: .5rem; }
.btn-cart:hover { background: #e9b84a; }
.breadcrumb { padding: .5rem 1rem; font-size: .85rem; color: var(--text-dim); }
.sidebar { width: 220px; flex-shrink: 0; }
.sidebar h3 { font-size: .9rem; border-bottom: 1px solid var(--border); padding-bottom: .25rem; margin-bottom: .5rem; }
.layout-with-sidebar { display: flex; gap: 1rem; padding: 1rem; max-width: 1400px; margin: 0 auto; }
CSS

# ── Infrastructure ─────────────────────────────────────────────────────────
write_falcon_config "$APP_PORT"
configure_production

# Solidus sets force_ssl; ensure production.rb doesn't duplicate
grep -q 'force_ssl' config/environments/production.rb || \
  print '  config.force_ssl = false' >> config/environments/production.rb

install_rcd brgen_marketplace "$APP_DIR" "$APP_PORT" brgen_marketplace

# ── Admin seed ───────────────────────────────────────────────────────────────
cat > db/seeds.rb << 'RUBY'
# Solidus creates admin via install; add sample taxons and products
if Spree::Taxon.count.zero?
  taxonomy = Spree::Taxonomy.find_or_create_by!(name: "Categories")
  %w[Electronics Clothing Books Furniture Sports].each do |cat|
    taxonomy.taxons.find_or_create_by!(name: cat) { |t| t.taxonomy = taxonomy }
  end
end
puts "Seeded #{Spree::Taxon.count} taxons"
RUBY

bin/rails db:seed 2>/dev/null || true

log_ok "Brgen Marketplace setup complete — start: doas rcctl start brgen_marketplace"
