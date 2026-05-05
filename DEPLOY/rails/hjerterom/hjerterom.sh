#!/usr/bin/env zsh
# hjerterom.sh — Hjerterom mental health & food redistribution platform (Rails 8)
# Usage: zsh hjerterom.sh
set -euo pipefail

APP_NAME=hjerterom
APP_DIR=/home/${APP_NAME}/app
APP_PORT=38891
SCRIPT_DIR=${0:a:h}

. "${SCRIPT_DIR:h}/@shared_functions.sh"

need_cmd ruby34 bundle rails doas

already_done "${APP_DIR}/app/models/resource.rb" && exit 0

log "Hjerterom — Mental Health and Food Redistribution Platform"

# ── Create app ─────────────────────────────────────────────────────────────
create_rails_app "$APP_DIR"

# ── Gems ────────────────────────────────────────────────────────────────────
add_gem pagy
add_gem image_processing
add_gem geocoder
install_solid_stack
install_security_tools

# ── Auth ───────────────────────────────────────────────────────────────────
install_auth
install_active_storage
install_action_text

# ── Models ─────────────────────────────────────────────────────────────────
# Mental health resources
bin/rails generate model Category \
  name:string slug:string:uniq description:text type_of:string \
  --no-test-framework

bin/rails generate model Resource \
  user:references category:references \
  title:string description:text url:string \
  address:string city:string postal_code:string \
  latitude:float longitude:float phone:string email:string \
  verified:boolean:'default[false]' \
  resource_type:string \
  opening_hours:text \
  --no-test-framework

bin/rails generate model Crisis \
  title:string description:text \
  phone:string sms:string chat_url:string \
  available_24h:boolean:'default[false]' \
  languages:string \
  country:string \
  --no-test-framework

# Food redistribution
bin/rails generate model FoodListing \
  user:references \
  title:string description:text \
  quantity:integer unit:string \
  available_from:datetime available_until:datetime \
  pickup_address:string city:string \
  latitude:float longitude:float \
  status:string \
  dietary_info:string \
  --no-test-framework

bin/rails generate model FoodRequest \
  food_listing:references user:references \
  message:text status:string pickup_time:datetime \
  --no-test-framework

# Community
bin/rails generate model Post \
  user:references category:references \
  title:string anonymous:boolean:'default[false]' \
  pinned:boolean:'default[false]' views_count:integer:'default[0]' \
  --no-test-framework

bin/rails generate model Comment \
  user:references post:references parent_id:integer \
  content:text anonymous:boolean:'default[false]' \
  --no-test-framework

bin/rails generate model SupportRequest \
  user:references \
  subject:string status:string priority:string \
  resolved_at:datetime \
  --no-test-framework

bin/rails db:migrate

# ── Model logic ─────────────────────────────────────────────────────────────
cat > app/models/resource.rb << 'RUBY'
class Resource < ApplicationRecord
  belongs_to :user
  belongs_to :category

  RESOURCE_TYPES = %w[crisis_line support_group therapist hotline community_center other].freeze

  validates :title, presence: true
  validates :resource_type, inclusion: { in: RESOURCE_TYPES }

  geocoded_by :address
  after_validation :geocode, if: :address_changed?

  scope :verified,   -> { where(verified: true) }
  scope :nearby,     ->(lat, lng, km = 50) {
    where("((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) < ?",
      lat, lat, lng, lng, (km / 111.0)**2)
  }
  scope :by_type,    ->(t) { where(resource_type: t) }
end
RUBY

cat > app/models/food_listing.rb << 'RUBY'
class FoodListing < ApplicationRecord
  belongs_to :user
  has_many :food_requests, dependent: :destroy

  STATUSES = %w[available reserved taken expired].freeze
  UNITS    = %w[kg portions bags boxes items].freeze

  validates :title, :quantity, :available_until, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }
  validates :unit, inclusion: { in: UNITS }

  attribute :status, :string, default: "available"

  geocoded_by :pickup_address
  after_validation :geocode, if: :pickup_address_changed?

  scope :available, -> { where(status: "available").where("available_until > ?", Time.current) }
  scope :nearby, ->(lat, lng, km = 20) {
    where("((latitude - ?) * (latitude - ?) + (longitude - ?) * (longitude - ?)) < ?",
      lat, lat, lng, lng, (km / 111.0)**2)
  }

  before_save :expire_if_past_date

  private

  def expire_if_past_date
    self.status = "expired" if available_until < Time.current && status == "available"
  end
end
RUBY

cat > app/models/post.rb << 'RUBY'
class Post < ApplicationRecord
  include ActionText::RichText

  belongs_to :user
  belongs_to :category
  has_rich_text :body
  has_many :comments, dependent: :destroy

  validates :title, presence: true, length: { maximum: 200 }

  scope :pinned,  -> { where(pinned: true) }
  scope :recent,  -> { order(created_at: :desc) }

  def display_author
    anonymous? ? "Anonym" : user.email_address.split("@").first
  end
end
RUBY

cat > app/models/comment.rb << 'RUBY'
class Comment < ApplicationRecord
  belongs_to :user
  belongs_to :post
  belongs_to :parent, class_name: "Comment", optional: true
  has_many :replies, class_name: "Comment", foreign_key: :parent_id, dependent: :destroy

  validates :content, presence: true, length: { maximum: 3000 }

  scope :roots, -> { where(parent_id: nil).order(created_at: :asc) }

  after_create_commit -> { broadcast_append_to [post, "comments"] }

  def display_author
    anonymous? ? "Anonym" : user.email_address.split("@").first
  end
end
RUBY

# ── Controllers ─────────────────────────────────────────────────────────────
cat > app/controllers/application_controller.rb << 'RUBY'
class ApplicationController < ActionController::Base
  include Pagy::Method
  allow_browser versions: :modern
end
RUBY

cat > app/controllers/home_controller.rb << 'RUBY'
class HomeController < ApplicationController
  def index
    @crisis_lines  = Crisis.where(available_24h: true).limit(5)
    @food_listings = FoodListing.available.order(created_at: :desc).limit(6)
    @recent_posts  = Post.recent.includes(:user, :category).limit(5)
    @resources     = Resource.verified.limit(8)
  end
end
RUBY

cat > app/controllers/resources_controller.rb << 'RUBY'
class ResourcesController < ApplicationController
  before_action :require_authentication, only: %i[new create edit update destroy]
  before_action :set_resource, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    scope = Resource.includes(:category)
    scope = scope.by_type(params[:type]) if params[:type].present?
    scope = scope.where("title LIKE ?", "%#{params[:q]}%") if params[:q].present?
    @pagy, @resources = pagy(scope.verified.order(:title))
    @crisis_lines = Crisis.all
  end

  def show; end

  def new
    @resource = Current.user.resources.build
  end

  def create
    @resource = Current.user.resources.build(resource_params)
    @resource.save ? redirect_to(@resource, notice: "Resource submitted for review") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @resource.update(resource_params) ? redirect_to(@resource, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @resource.destroy
    redirect_to resources_path, notice: "Removed"
  end

  private

  def set_resource  = @resource = Resource.find(params[:id])
  def authorize!    = redirect_to(resources_path, alert: "Unauthorized") unless @resource.user == Current.user

  def resource_params
    params.require(:resource).permit(
      :title, :description, :url, :address, :city, :postal_code,
      :phone, :email, :resource_type, :opening_hours, :category_id
    )
  end
end
RUBY

cat > app/controllers/food_listings_controller.rb << 'RUBY'
class FoodListingsController < ApplicationController
  before_action :require_authentication, except: %i[index show]
  before_action :set_listing, only: %i[show edit update destroy]
  before_action :authorize!, only: %i[edit update destroy]

  def index
    @pagy, @listings = pagy(FoodListing.available.order(created_at: :desc))
  end

  def show
    @request = FoodRequest.new
  end

  def new
    @listing = Current.user.food_listings.build
  end

  def create
    @listing = Current.user.food_listings.build(listing_params)
    @listing.save ? redirect_to(@listing, notice: "Food listing created") : render(:new, status: :unprocessable_entity)
  end

  def edit; end

  def update
    @listing.update(listing_params) ? redirect_to(@listing, notice: "Updated") : render(:edit, status: :unprocessable_entity)
  end

  def destroy
    @listing.destroy
    redirect_to food_listings_path, notice: "Listing removed"
  end

  private

  def set_listing  = @listing = FoodListing.find(params[:id])
  def authorize!   = redirect_to(food_listings_path, alert: "Unauthorized") unless @listing.user == Current.user

  def listing_params
    params.require(:food_listing).permit(
      :title, :description, :quantity, :unit,
      :available_from, :available_until,
      :pickup_address, :city, :dietary_info
    )
  end
end
RUBY

cat > app/controllers/food_requests_controller.rb << 'RUBY'
class FoodRequestsController < ApplicationController
  before_action :require_authentication

  def create
    listing  = FoodListing.find(params[:food_listing_id])
    @request = listing.food_requests.build(request_params.merge(user: Current.user, status: "pending"))
    @request.save ? redirect_to(listing, notice: "Request sent") : render(:new, status: :unprocessable_entity)
  end

  def update
    @request = FoodRequest.find(params[:id])
    authorize_owner!
    @request.update!(status: params[:status]) if params[:status].in?(%w[approved declined])
    redirect_to @request.food_listing
  end

  private

  def authorize_owner! = redirect_to(root_path, alert: "Unauthorized") unless @request.food_listing.user == Current.user
  def request_params   = params.require(:food_request).permit(:message, :pickup_time)
end
RUBY

cat > app/controllers/community_controller.rb << 'RUBY'
class CommunityController < ApplicationController
  before_action :require_authentication, only: %i[new create]

  def index
    @categories = Category.order(:name)
    @pagy, @posts = pagy(Post.recent.includes(:user, :category))
  end

  def show
    @post     = Post.find(params[:id])
    @post.increment!(:views_count)
    @comments = @post.comments.roots.includes(:user, replies: :user)
    @comment  = Comment.new
  end

  def new
    @post = Post.new
  end

  def create
    @post = Current.user.posts.build(post_params)
    @post.save ? redirect_to(community_show_path(@post), notice: "Posted") : render(:new, status: :unprocessable_entity)
  end

  private

  def post_params
    params.require(:post).permit(:title, :body, :category_id, :anonymous)
  end
end
RUBY

# ── Routes ─────────────────────────────────────────────────────────────────
cat > config/routes.rb << 'RUBY'
Rails.application.routes.draw do
  resource  :session
  resources :passwords, param: :token

  root "home#index"

  resources :resources
  resources :food_listings do
    resources :food_requests, only: %i[create update]
  end

  scope :community do
    get  "/",       to: "community#index", as: :community
    get  "/:id",    to: "community#show",  as: :community_show
    get  "/new",    to: "community#new",   as: :new_community_post
    post "/",       to: "community#create"
    resources :comments, only: %i[create destroy]
  end

  resources :users, only: %i[show]

  get "up", to: "rails/health#show", as: :rails_health_check
end
RUBY

# ── Assets + Infrastructure ─────────────────────────────────────────────────
mkdir -p app/assets/stylesheets
cat > app/assets/stylesheets/application.css << 'CSS'
:root {
  --bg: #f0f4f8; --surface: #ffffff; --text: #1a202c;
  --text-dim: #718096; --primary: #48bb78; --primary-dark: #276749;
  --secondary: #f6ad55; --radius: 12px; --space: 8px;
  --shadow: 0 2px 8px rgba(0,0,0,.08);
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
main { max-width: 1100px; margin: 0 auto; padding: calc(var(--space)*2); }
a { color: var(--primary-dark); text-decoration: none; }
a:hover { text-decoration: underline; }
.card { background: var(--surface); border-radius: var(--radius); padding: 1.5rem; margin-bottom: 1rem; box-shadow: var(--shadow); }
.btn { display: inline-block; padding: .5rem 1.25rem; border-radius: var(--radius); border: none; cursor: pointer; font-size: .9rem; font-weight: 600; }
.btn-primary { background: var(--primary); color: #fff; }
.btn-secondary { background: var(--secondary); color: #000; }
.badge { display: inline-block; padding: .2rem .6rem; border-radius: 2em; font-size: .75rem; font-weight: 600; }
.badge-food { background: #fff3cd; color: #856404; }
.badge-mental { background: #d4edda; color: #155724; }
.crisis-banner { background: #dc3545; color: #fff; padding: 1rem 1.5rem; border-radius: var(--radius); margin-bottom: 1.5rem; }
.flash-notice { background: #d4edda; color: #155724; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
.flash-alert  { background: #f8d7da; color: #721c24; padding: .75rem 1rem; border-radius: var(--radius); margin-bottom: 1rem; }
CSS

# ── Views ───────────────────────────────────────────────────────────────────
mkdir -p app/views/home app/views/resources app/views/food_listings app/views/food_requests app/views/community

write_shared_partials
write_auth_views

cat > app/views/home/index.html.erb << 'ERB'
<% content_for :title, "Hjerterom" %>
<% if @crisis_lines.any? %>
  <aside class="crisis-banner">
    <strong>Crisis support:</strong>
    <% @crisis_lines.each do |c| %>
      <%= c.title %> <strong><%= c.phone %></strong><%= " · " unless c == @crisis_lines.last %>
    <% end %>
  </aside>
<% end %>
<div class="home-grid">
  <section>
    <h2>Food available</h2>
    <% @food_listings.each do |listing| %>
      <article class="card">
        <%= link_to listing.title, food_listing_path(listing) %>
        <p class="dim"><%= listing.city %> · available until <%= listing.available_until&.strftime("%b %-d") %></p>
      </article>
    <% end %>
    <%= link_to "All food listings →", food_listings_path %>
  </section>
  <section>
    <h2>Community</h2>
    <% @posts.each do |post| %>
      <article class="card">
        <%= link_to post.title, community_show_path(post) %>
      </article>
    <% end %>
    <%= link_to "All posts →", community_path %>
    <% if authenticated? %><%= link_to "New post", new_community_post_path, class: "btn btn-primary" %><% end %>
  </section>
  <section>
    <h2>Resources</h2>
    <% @resources.each do |resource| %>
      <article class="card">
        <%= link_to resource.title, resource_path(resource) %>
        <p class="dim"><%= resource.resource_type %><%= " · #{resource.city}" if resource.city.present? %></p>
      </article>
    <% end %>
    <%= link_to "All resources →", resources_path %>
  </section>
</div>
ERB

cat > app/views/resources/index.html.erb << 'ERB'
<% content_for :title, "Resources" %>
<header>
  <h1>Resources</h1>
  <% if authenticated? %><%= link_to "Add resource", new_resource_path, class: "btn btn-primary" %><% end %>
</header>
<div id="resources">
  <% @resources.each do |resource| %>
    <article class="card">
      <%= link_to resource.title, resource %>
      <span class="badge badge-<%= resource.resource_type %>"><%= resource.resource_type %></span>
      <p class="dim"><%= resource.description %></p>
      <p class="dim"><%= [resource.city, resource.phone].compact.join(" · ") %></p>
    </article>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/resources/show.html.erb << 'ERB'
<% content_for :title, @resource.title %>
<article class="card">
  <h1><%= @resource.title %></h1>
  <span class="badge badge-<%= @resource.resource_type %>"><%= @resource.resource_type %></span>
  <p><%= @resource.description %></p>
  <dl class="meta">
    <% if @resource.address.present? %><dt>Address</dt><dd><%= @resource.address %>, <%= @resource.city %></dd><% end %>
    <% if @resource.phone.present? %><dt>Phone</dt><dd><%= @resource.phone %></dd><% end %>
    <% if @resource.email.present? %><dt>Email</dt><dd><%= mail_to @resource.email %></dd><% end %>
    <% if @resource.url.present? %><dt>Website</dt><dd><%= link_to @resource.url, @resource.url %></dd><% end %>
    <% if @resource.opening_hours.present? %><dt>Hours</dt><dd><%= @resource.opening_hours %></dd><% end %>
  </dl>
  <% if @resource.user == Current.user %>
    <%= link_to "Edit", edit_resource_path(@resource), class: "btn" %>
    <%= button_to "Delete", @resource, method: :delete, data: { turbo_confirm: "Delete?" }, class: "btn btn-danger" %>
  <% end %>
</article>
ERB

cat > app/views/resources/new.html.erb << 'ERB'
<% content_for :title, "Add resource" %>
<h1>Add resource</h1>
<%= render "form", resource: @resource %>
ERB

cat > app/views/resources/edit.html.erb << 'ERB'
<% content_for :title, "Edit resource" %>
<h1>Edit resource</h1>
<%= render "form", resource: @resource %>
ERB

cat > app/views/resources/_form.html.erb << 'ERB'
<%= form_with model: resource, class: "form" do |f| %>
  <%= render "shared/errors", object: resource %>
  <div class="field"><%= f.label :title %><%= f.text_field :title, autofocus: true %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 3 %></div>
  <div class="field">
    <%= f.label :resource_type %>
    <%= f.select :resource_type, %w[mental_health food shelter legal medical], include_blank: "Select…" %>
  </div>
  <div class="field"><%= f.label :address %><%= f.text_field :address %></div>
  <div class="field"><%= f.label :city %><%= f.text_field :city %></div>
  <div class="field"><%= f.label :phone %><%= f.telephone_field :phone %></div>
  <div class="field"><%= f.label :email %><%= f.email_field :email %></div>
  <div class="field"><%= f.label :url, "Website" %><%= f.url_field :url %></div>
  <div class="field"><%= f.label :opening_hours %><%= f.text_field :opening_hours %></div>
  <div class="actions"><%= f.submit class: "btn btn-primary" %> <%= link_to "Cancel", resources_path %></div>
<% end %>
ERB

cat > app/views/food_listings/index.html.erb << 'ERB'
<% content_for :title, "Food" %>
<header>
  <h1>Available food</h1>
  <% if authenticated? %><%= link_to "List food", new_food_listing_path, class: "btn btn-primary" %><% end %>
</header>
<div id="food_listings">
  <% @food_listings.each do |listing| %>
    <article class="card">
      <%= link_to listing.title, food_listing_path(listing) %>
      <p class="dim"><%= listing.quantity %> <%= listing.unit %> · <%= listing.city %></p>
      <p class="dim">Until <%= listing.available_until&.strftime("%b %-d, %H:%M") %></p>
      <% if listing.dietary_info.present? %>
        <span class="badge badge-food"><%= listing.dietary_info %></span>
      <% end %>
    </article>
  <% end %>
</div>
<%= @pagy.series_nav if @pagy.pages > 1 %>
ERB

cat > app/views/food_listings/show.html.erb << 'ERB'
<% content_for :title, @listing.title %>
<article class="card">
  <h1><%= @listing.title %></h1>
  <p><%= @listing.description %></p>
  <dl class="meta">
    <dt>Quantity</dt><dd><%= @listing.quantity %> <%= @listing.unit %></dd>
    <dt>Pickup</dt><dd><%= @listing.pickup_address %>, <%= @listing.city %></dd>
    <dt>Available</dt><dd><%= @listing.available_from&.strftime("%b %-d, %H:%M") %> – <%= @listing.available_until&.strftime("%b %-d, %H:%M") %></dd>
    <% if @listing.dietary_info.present? %><dt>Dietary</dt><dd><%= @listing.dietary_info %></dd><% end %>
  </dl>
  <% if authenticated? && @listing.user != Current.user && @listing.status == "available" %>
    <%= form_with url: food_listing_food_requests_path(@listing), class: "form" do |f| %>
      <div class="field"><%= f.text_area :message, rows: 2, placeholder: "Message (optional)…" %></div>
      <div class="field"><%= f.datetime_local_field :pickup_time %></div>
      <%= f.submit "Request pickup", class: "btn btn-primary" %>
    <% end %>
  <% end %>
  <% if @listing.user == Current.user %>
    <%= link_to "Edit", edit_food_listing_path(@listing), class: "btn" %>
    <%= button_to "Delete", @listing, method: :delete, data: { turbo_confirm: "Delete?" }, class: "btn btn-danger" %>
  <% end %>
</article>
ERB

cat > app/views/food_listings/new.html.erb << 'ERB'
<% content_for :title, "List food" %>
<h1>List food</h1>
<%= render "form", listing: @listing %>
ERB

cat > app/views/food_listings/edit.html.erb << 'ERB'
<% content_for :title, "Edit listing" %>
<h1>Edit listing</h1>
<%= render "form", listing: @listing %>
ERB

cat > app/views/food_listings/_form.html.erb << 'ERB'
<%= form_with model: listing, url: listing.new_record? ? food_listings_path : food_listing_path(listing), class: "form" do |f| %>
  <%= render "shared/errors", object: listing %>
  <div class="field"><%= f.label :title %><%= f.text_field :title, autofocus: true %></div>
  <div class="field"><%= f.label :description %><%= f.text_area :description, rows: 2 %></div>
  <div class="field"><%= f.label :quantity %><%= f.number_field :quantity, min: 1 %></div>
  <div class="field"><%= f.label :unit %><%= f.text_field :unit, placeholder: "kg, portions, bags…" %></div>
  <div class="field"><%= f.label :pickup_address %><%= f.text_field :pickup_address %></div>
  <div class="field"><%= f.label :city %><%= f.text_field :city %></div>
  <div class="field"><%= f.label :available_from %><%= f.datetime_local_field :available_from %></div>
  <div class="field"><%= f.label :available_until %><%= f.datetime_local_field :available_until %></div>
  <div class="field"><%= f.label :dietary_info %><%= f.text_field :dietary_info, placeholder: "vegan, nut-free…" %></div>
  <div class="actions"><%= f.submit class: "btn btn-primary" %> <%= link_to "Cancel", food_listings_path %></div>
<% end %>
ERB

cat > app/views/community/index.html.erb << 'ERB'
<% content_for :title, "Community" %>
<header>
  <h1>Community</h1>
  <% if authenticated? %><%= link_to "New post", new_community_post_path, class: "btn btn-primary" %><% end %>
</header>
<div id="community_posts">
  <% @posts.each do |post| %>
    <article class="card">
      <%= link_to post.title, community_show_path(post) %>
      <span class="dim"><%= post.anonymous? ? "Anonymous" : post.user.email_address.split("@").first %></span>
    </article>
  <% end %>
</div>
ERB

cat > app/views/community/show.html.erb << 'ERB'
<% content_for :title, @post.title %>
<article class="card post">
  <h1><%= @post.title %></h1>
  <span class="dim"><%= @post.anonymous? ? "Anonymous" : @post.user.email_address.split("@").first %></span>
  <%= @post.body %>
</article>
<section id="comments">
  <h2>Comments</h2>
  <%= render @comments %>
  <% if authenticated? %>
    <%= form_with url: community_comments_path, class: "form" do |f| %>
      <%= f.hidden_field :post_id, value: @post.id %>
      <div class="field"><%= f.text_area :content, rows: 3, placeholder: "Comment…" %></div>
      <div class="actions"><%= f.submit "Comment", class: "btn btn-primary" %></div>
    <% end %>
  <% end %>
</section>
ERB

cat > app/views/community/new.html.erb << 'ERB'
<% content_for :title, "New post" %>
<h1>New post</h1>
<%= form_with url: community_path, class: "form" do |f| %>
  <div class="field"><%= f.label :title %><%= f.text_field :title, name: "post[title]", autofocus: true %></div>
  <div class="field"><%= f.label :body %><%= f.rich_text_area :body, name: "post[body]" %></div>
  <div class="field field--check">
    <%= label_tag :anonymous, "Post anonymously" %>
    <%= check_box_tag "post[anonymous]" %>
  </div>
  <div class="actions"><%= f.submit "Post", class: "btn btn-primary" %> <%= link_to "Cancel", community_path %></div>
<% end %>
ERB

# ── SCSS additions ───────────────────────────────────────────────────────────
cat >> app/assets/stylesheets/application.css << 'CSS'
.home-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; }
.meta { display: grid; grid-template-columns: max-content 1fr; gap: .3rem 1rem; margin: 1rem 0; }
.meta dt { font-weight: 600; }
.btn { display: inline-block; padding: .5rem 1.25rem; border-radius: 8px; border: none; cursor: pointer; font-size: .9rem; font-weight: 600; text-decoration: none; }
.btn-primary { background: var(--primary); color: #fff; }
.btn-danger { background: #dc3545; color: #fff; }
.dim { color: var(--text-dim); font-size: .85rem; }
.form { max-width: 560px; }
.form .field { display: flex; flex-direction: column; gap: .25rem; margin-bottom: .75rem; }
.form .field--check { flex-direction: row; align-items: center; gap: .5rem; }
.form input, .form select, .form textarea { border: 1px solid #cbd5e0; border-radius: 6px; padding: .45rem .6rem; font: inherit; }
.form .actions { display: flex; gap: .75rem; align-items: center; margin-top: 1rem; }
h1, h2 { margin-bottom: .5rem; }
CSS

write_layout "Hjerterom"
write_falcon_config "$APP_PORT"
configure_production
install_rcd hjerterom "$APP_DIR" "$APP_PORT" hjerterom

# ── Seed ───────────────────────────────────────────────────────────────────
cat > db/seeds.rb << 'RUBY'
admin = User.find_or_create_by!(email_address: "admin@hjerterom.no") do |u|
  u.password = u.password_confirmation = "password123"
end

crisis_lines = [
  { title: "Mental Helse Hjelpelinjen", phone: "116 123", available_24h: true, languages: "Norsk", country: "NO" },
  { title: "Kirkens SOS", phone: "22 40 00 40", available_24h: true, languages: "Norsk", country: "NO" },
  { title: "Røde Kors Besøkstjeneste", phone: "800 33 321", available_24h: false, languages: "Norsk", country: "NO" },
]
crisis_lines.each { |c| Crisis.find_or_create_by!(title: c[:title]) { |cr| cr.update(c) } }

cats = [
  { name: "Angst",     slug: "angst",    type_of: "mental_health" },
  { name: "Depresjon", slug: "depresjon", type_of: "mental_health" },
  { name: "Ensomhet",  slug: "ensomhet",  type_of: "mental_health" },
  { name: "Mat",       slug: "mat",       type_of: "food" },
]
cats.each { |c| Category.find_or_create_by!(slug: c[:slug]) { |cat| cat.update(c) } }

puts "Seeded crisis lines and categories"
RUBY

bin/rails db:seed

log_ok "Hjerterom setup complete — start: doas rcctl start hjerterom"
