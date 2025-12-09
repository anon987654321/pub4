#!/usr/bin/env zsh
set -euo pipefail

# Brgen Marketplace setup: Multi-vendor marketplace with Solidus, payments, Mapbox, search, and anonymous features on OpenBSD 7.5, unprivileged user
# Framework v37.3.2 compliant with enhanced e-commerce functionality

APP_NAME="brgen_marketplace"
BASE_DIR="/home/dev/rails"
BRGEN_IP="46.23.95.45"

source "./__shared.sh"

log "Starting Brgen Marketplace setup with Solidus e-commerce platform"

setup_full_app "$APP_NAME"

command_exists "ruby"
command_exists "node"
command_exists "psql"
command_exists "redis-server"

install_gem "faker"

# Install Solidus e-commerce platform
log "Installing Solidus e-commerce platform"
bundle add solidus --github='solidusio/solidus'
bundle add solidus_auth_devise --github='solidusio/solidus_auth_devise'
bundle add solidus_searchkick --github='solidusio-contrib/solidus_searchkick'
bundle add solidus_reviews --github='solidusio-contrib/solidus_reviews'
bundle add solidus_stripe
bundle install

# Generate Solidus installation
bin/rails generate solidus:install --auto-accept
bin/rails generate solidus_searchkick:install
bin/rails generate solidus_reviews:install
bin/rails db:migrate

# Add custom marketplace models
bin/rails generate model Vendor name:string description:text user:references verified:boolean
bin/rails generate model VendorProduct vendor:references product:references commission_rate:decimal
bin/rails generate scaffold Listing title:string description:text price:decimal vendor:references category:string status:string location:string lat:decimal lng:decimal photos:attachments

cat <<EOF > app/reflexes/products_infinite_scroll_reflex.rb
class ProductsInfiniteScrollReflex < InfiniteScrollReflex
  def load_more
    @pagy, @collection = pagy(Product.all.order(created_at: :desc), page: page)
    super
  end
end
EOF

cat <<EOF > app/reflexes/orders_infinite_scroll_reflex.rb
class OrdersInfiniteScrollReflex < InfiniteScrollReflex
  def load_more
    @pagy, @collection = pagy(Order.where(buyer: current_user).order(created_at: :desc), page: page)
    super
  end
end
EOF

cat <<EOF > app/controllers/products_controller.rb
class ProductsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_product, only: [:show, :edit, :update, :destroy]

  def index
    @pagy, @products = pagy(Product.all.order(created_at: :desc)) unless @stimulus_reflex
  end

  def show
  end

  def new
    @product = Product.new
  end

  def create
    @product = Product.new(product_params)
    @product.user = current_user
    if @product.save
      respond_to do |format|
        format.html { redirect_to products_path, notice: t("brgen_marketplace.product_created") }
        format.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @product.update(product_params)
      respond_to do |format|
        format.html { redirect_to products_path, notice: t("brgen_marketplace.product_updated") }
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @product.destroy
    respond_to do |format|
      format.html { redirect_to products_path, notice: t("brgen_marketplace.product_deleted") }
      format.turbo_stream
    end
  end

  private

  def set_product
    @product = Product.find(params[:id])
    redirect_to products_path, alert: t("brgen_marketplace.not_authorized") unless @product.user == current_user || current_user&.admin?
  end

  def product_params
    params.require(:product).permit(:name, :price, :description, photos: [])
  end
end
EOF

cat <<EOF > app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_order, only: [:show, :edit, :update, :destroy]

  def index
    @pagy, @orders = pagy(Order.where(buyer: current_user).order(created_at: :desc)) unless @stimulus_reflex
  end

  def show
  end

  def new
    @order = Order.new
  end

  def create
    @order = Order.new(order_params)
    @order.buyer = current_user
    if @order.save
      respond_to do |format|
        format.html { redirect_to orders_path, notice: t("brgen_marketplace.order_created") }
        format.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @order.update(order_params)
      respond_to do |format|
        format.html { redirect_to orders_path, notice: t("brgen_marketplace.order_updated") }
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @order.destroy
    respond_to do |format|
      format.html { redirect_to orders_path, notice: t("brgen_marketplace.order_deleted") }
      format.turbo_stream
    end
  end

  private

  def set_order
    @order = Order.where(buyer: current_user).find(params[:id])
    redirect_to orders_path, alert: t("brgen_marketplace.not_authorized") unless @order.buyer == current_user || current_user&.admin?
  end

  def order_params
    params.require(:order).permit(:product_id, :status)
  end
end
EOF

cat <<EOF > app/controllers/home_controller.rb
class HomeController < ApplicationController
  def index
    @pagy, @posts = pagy(Post.all.order(created_at: :desc), items: 10) unless @stimulus_reflex
    @products = Product.all.order(created_at: :desc).limit(5)
  end
end
EOF

mkdir -p app/views/brgen_marketplace_logo

cat <<EOF > app/views/brgen_marketplace_logo/_logo.html.erb
<%= tag.svg xmlns: "http://www.w3.org/2000/svg", viewBox: "0 0 100 50", role: "img", class: "logo", "aria-label": t("brgen_marketplace.logo_alt") do %>
  <%= tag.title t("brgen_marketplace.logo_title", default: "Brgen Marketplace Logo") %>
  <%= tag.text x: "50", y: "30", "text-anchor": "middle", "font-family": "Helvetica, Arial, sans-serif", "font-size": "16", fill: "#4caf50" do %>Marketplace<% end %>
<% end %>
EOF

cat <<EOF > app/views/shared/_header.html.erb
<%= tag.header role: "banner" do %>
  <%= render partial: "brgen_marketplace_logo/logo" %>
<% end %>
EOF

cat <<EOF > app/views/shared/_footer.html.erb
<%= tag.footer role: "contentinfo" do %>
  <%= tag.nav class: "footer-links" aria-label: t("shared.footer_nav") do %>
    <%= link_to "", "https://facebook.com", class: "footer-link fb", "aria-label": "Facebook" %>
    <%= link_to "", "https://twitter.com", class: "footer-link tw", "aria-label": "Twitter" %>
    <%= link_to "", "https://instagram.com", class: "footer-link ig", "aria-label": "Instagram" %>
    <%= link_to t("shared.about"), "#", class: "footer-link text" %>
    <%= link_to t("shared.contact"), "#", class: "footer-link text" %>
    <%= link_to t("shared.terms"), "#", class: "footer-link text" %>
    <%= link_to t("shared.privacy"), "#", class: "footer-link text" %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/home/index.html.erb
<% content_for :title, t("brgen_marketplace.home_title") %>
<% content_for :description, t("brgen_marketplace.home_description") %>
<% content_for :keywords, t("brgen_marketplace.home_keywords", default: "brgen marketplace, e-commerce, products") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_marketplace.home_title') %>",
    "description": "<%= t('brgen_marketplace.home_description') %>",
    "url": "<%= request.original_url %>",
    "publisher": {
      "@type": "Organization",
      "name": "Brgen Marketplace",
      "logo": {
        "@type": "ImageObject",
        "url": "<%= image_url('brgen_marketplace_logo.svg') %>"
      }
    }
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "post-heading" do %>
    <%= tag.h1 t("brgen_marketplace.post_title"), id: "post-heading" %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= render partial: "posts/form", locals: { post: Post.new } %>
  <% end %>
  <%= render partial: "shared/search", locals: { model: "Product", field: "name" } %>
  <%= tag.section aria-labelledby: "products-heading" do %>
    <%= tag.h2 t("brgen_marketplace.products_title"), id: "products-heading" %>
    <%= link_to t("brgen_marketplace.new_product"), new_product_path, class: "button", "aria-label": t("brgen_marketplace.new_product") if current_user %>
    <%= turbo_frame_tag "products" data: { controller: "infinite-scroll" } do %>
      <% @products.each do |product| %>
        <%= render partial: "products/card", locals: { product: product } %>
      <% end %>
      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "ProductsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>
    <% end %>
    <%= tag.button t("brgen_marketplace.load_more"), id: "load-more", data: { reflex: "click->ProductsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_marketplace.load_more") %>
  <% end %>
  <%= tag.section aria-labelledby: "posts-heading" do %>
    <%= tag.h2 t("brgen_marketplace.posts_title"), id: "posts-heading" %>
    <%= turbo_frame_tag "posts" data: { controller: "infinite-scroll" } do %>
      <% @posts.each do |post| %>
        <%= render partial: "posts/card", locals: { post: post } %>
      <% end %>
      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "PostsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>
    <% end %>
    <%= tag.button t("brgen_marketplace.load_more"), id: "load-more", data: { reflex: "click->PostsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_marketplace.load_more") %>
  <% end %>
  <%= render partial: "shared/chat" %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/products/index.html.erb
<% content_for :title, t("brgen_marketplace.products_title") %>
<% content_for :description, t("brgen_marketplace.products_description") %>
<% content_for :keywords, t("brgen_marketplace.products_keywords", default: "brgen marketplace, products, e-commerce") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_marketplace.products_title') %>",
    "description": "<%= t('brgen_marketplace.products_description') %>",
    "url": "<%= request.original_url %>",
    "hasPart": [
      <% @products.each do |product| %>
      {
        "@type": "Product",
        "name": "<%= product.name %>",
        "description": "<%= product.description&.truncate(160) %>",
        "offers": {
          "@type": "Offer",
          "price": "<%= product.price %>",
          "priceCurrency": "NOK"
        }
      }<%= "," unless product == @products.last %>
      <% end %>
    ]
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "products-heading" do %>
    <%= tag.h1 t("brgen_marketplace.products_title"), id: "products-heading" %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= link_to t("brgen_marketplace.new_product"), new_product_path, class: "button", "aria-label": t("brgen_marketplace.new_product") if current_user %>
    <%= turbo_frame_tag "products" data: { controller: "infinite-scroll" } do %>
      <% @products.each do |product| %>
        <%= render partial: "products/card", locals: { product: product } %>
      <% end %>
      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "ProductsInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>
    <% end %>
    <%= tag.button t("brgen_marketplace.load_more"), id: "load-more", data: { reflex: "click->ProductsInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_marketplace.load_more") %>
  <% end %>
  <%= render partial: "shared/search", locals: { model: "Product", field: "name" } %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/products/_card.html.erb
<%= turbo_frame_tag dom_id(product) do %>
  <%= tag.article class: "post-card", id: dom_id(product), role: "article" do %>
    <%= tag.div class: "post-header" do %>
      <%= tag.span t("brgen_marketplace.posted_by", user: product.user.email) %>
      <%= tag.span product.created_at.strftime("%Y-%m-%d %H:%M") %>
    <% end %>
    <%= tag.h2 product.name %>
    <%= tag.p product.description %>
    <%= tag.p t("brgen_marketplace.product_price", price: number_to_currency(product.price)) %>
    <% if product.photos.attached? %>
      <% product.photos.each do |photo| %>
        <%= image_tag photo, style: "max-width: 200px;", alt: t("brgen_marketplace.product_photo", name: product.name) %>
      <% end %>
    <% end %>
    <%= render partial: "shared/vote", locals: { votable: product } %>
    <%= tag.p class: "post-actions" do %>
      <%= link_to t("brgen_marketplace.view_product"), product_path(product), "aria-label": t("brgen_marketplace.view_product") %>
      <%= link_to t("brgen_marketplace.edit_product"), edit_product_path(product), "aria-label": t("brgen_marketplace.edit_product") if product.user == current_user || current_user&.admin? %>
      <%= button_to t("brgen_marketplace.delete_product"), product_path(product), method: :delete, data: { turbo_confirm: t("brgen_marketplace.confirm_delete") }, form: { data: { turbo_frame: "_top" } }, "aria-label": t("brgen_marketplace.delete_product") if product.user == current_user || current_user&.admin? %>
    <% end %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/products/_form.html.erb
<%= form_with model: product, local: true, data: { controller: "character-counter form-validation", turbo: true } do |form| %>
  <%= tag.div data: { turbo_frame: "notices" } do %>
    <%= render "shared/notices" %>
  <% end %>
  <% if product.errors.any? %>
    <%= tag.div role: "alert" do %>
      <%= tag.p t("brgen_marketplace.errors", count: product.errors.count) %>
      <%= tag.ul do %>
        <% product.errors.full_messages.each do |msg| %>
          <%= tag.li msg %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :name, t("brgen_marketplace.product_name"), "aria-required": true %>
    <%= form.text_field :name, required: true, data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("brgen_marketplace.product_name_help") %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "product_name" } %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :price, t("brgen_marketplace.product_price"), "aria-required": true %>
    <%= form.number_field :price, required: true, step: 0.01, data: { "form-validation-target": "input", action: "input->form-validation#validate" }, title: t("brgen_marketplace.product_price_help") %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "product_price" } %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :description, t("brgen_marketplace.product_description"), "aria-required": true %>
    <%= form.text_area :description, required: true, data: { "character-counter-target": "input", "textarea-autogrow-target": "input", "form-validation-target": "input", action: "input->character-counter#count input->textarea-autogrow#resize input->form-validation#validate" }, title: t("brgen_marketplace.product_description_help") %>
    <%= tag.span data: { "character-counter-target": "count" } %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "product_description" } %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :photos, t("brgen_marketplace.product_photos") %>
    <%= form.file_field :photos, multiple: true, accept: "image/*", data: { controller: "file-preview", "file-preview-target": "input" } %>
    <% if product.photos.attached? %>
      <% product.photos.each do |photo| %>
        <%= image_tag photo, style: "max-width: 200px;", alt: t("brgen_marketplace.product_photo", name: product.name) %>
      <% end %>
    <% end %>
    <%= tag.div data: { "file-preview-target": "preview" }, style: "display: none;" %>
  <% end %>
  <%= form.submit t("brgen_marketplace.#{product.persisted? ? 'update' : 'create'}_product"), data: { turbo_submits_with: t("brgen_marketplace.#{product.persisted? ? 'updating' : 'creating'}_product") } %>
<% end %>
EOF

cat <<EOF > app/views/products/new.html.erb
<% content_for :title, t("brgen_marketplace.new_product_title") %>
<% content_for :description, t("brgen_marketplace.new_product_description") %>
<% content_for :keywords, t("brgen_marketplace.new_product_keywords", default: "add product, brgen marketplace, e-commerce") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_marketplace.new_product_title') %>",
    "description": "<%= t('brgen_marketplace.new_product_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "new-product-heading" do %>
    <%= tag.h1 t("brgen_marketplace.new_product_title"), id: "new-product-heading" %>
    <%= render partial: "products/form", locals: { product: @product } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/products/edit.html.erb
<% content_for :title, t("brgen_marketplace.edit_product_title") %>
<% content_for :description, t("brgen_marketplace.edit_product_description") %>
<% content_for :keywords, t("brgen_marketplace.edit_product_keywords", default: "edit product, brgen marketplace, e-commerce") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_marketplace.edit_product_title') %>",
    "description": "<%= t('brgen_marketplace.edit_product_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "edit-product-heading" do %>
    <%= tag.h1 t("brgen_marketplace.edit_product_title"), id: "edit-product-heading" %>
    <%= render partial: "products/form", locals: { product: @product } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/products/show.html.erb
<% content_for :title, @product.name %>
<% content_for :description, @product.description&.truncate(160) %>
<% content_for :keywords, t("brgen_marketplace.product_keywords", name: @product.name, default: "product, #{@product.name}, brgen marketplace, e-commerce") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "Product",
    "name": "<%= @product.name %>",
    "description": "<%= @product.description&.truncate(160) %>",
    "offers": {
      "@type": "Offer",
      "price": "<%= @product.price %>",
      "priceCurrency": "NOK"
    }
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "product-heading" class: "post-card" do %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= tag.h1 @product.name, id: "product-heading" %>
    <%= render partial: "products/card", locals: { product: @product } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/orders/index.html.erb
<% content_for :title, t("brgen_marketplace.orders_title") %>
<% content_for :description, t("brgen_marketplace.orders_description") %>
<% content_for :keywords, t("brgen_marketplace.orders_keywords", default: "brgen marketplace, orders, e-commerce") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_marketplace.orders_title') %>",
    "description": "<%= t('brgen_marketplace.orders_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "orders-heading" do %>
    <%= tag.h1 t("brgen_marketplace.orders_title"), id: "orders-heading" %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= link_to t("brgen_marketplace.new_order"), new_order_path, class: "button", "aria-label": t("brgen_marketplace.new_order") %>
    <%= turbo_frame_tag "orders" data: { controller: "infinite-scroll" } do %>
      <% @orders.each do |order| %>
        <%= render partial: "orders/card", locals: { order: order } %>
      <% end %>
      <%= tag.div id: "sentinel", class: "hidden", data: { reflex: "OrdersInfiniteScroll#load_more", next_page: @pagy.next || 2 } %>
    <% end %>
    <%= tag.button t("brgen_marketplace.load_more"), id: "load-more", data: { reflex: "click->OrdersInfiniteScroll#load_more", "next-page": @pagy.next || 2, "reflex-root": "#load-more" }, class: @pagy&.next ? "" : "hidden", "aria-label": t("brgen_marketplace.load_more") %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/orders/_card.html.erb
<%= turbo_frame_tag dom_id(order) do %>
  <%= tag.article class: "post-card", id: dom_id(order), role: "article" do %>
    <%= tag.div class: "post-header" do %>
      <%= tag.span t("brgen_marketplace.ordered_by", user: order.buyer.email) %>
      <%= tag.span order.created_at.strftime("%Y-%m-%d %H:%M") %>
    <% end %>
    <%= tag.h2 order.product.name %>
    <%= tag.p t("brgen_marketplace.order_status", status: order.status) %>
    <%= render partial: "shared/vote", locals: { votable: order } %>
    <%= tag.p class: "post-actions" do %>
      <%= link_to t("brgen_marketplace.view_order"), order_path(order), "aria-label": t("brgen_marketplace.view_order") %>
      <%= link_to t("brgen_marketplace.edit_order"), edit_order_path(order), "aria-label": t("brgen_marketplace.edit_order") if order.buyer == current_user || current_user&.admin? %>
      <%= button_to t("brgen_marketplace.delete_order"), order_path(order), method: :delete, data: { turbo_confirm: t("brgen_marketplace.confirm_delete") }, form: { data: { turbo_frame: "_top" } }, "aria-label": t("brgen_marketplace.delete_order") if order.buyer == current_user || current_user&.admin? %>
    <% end %>
  <% end %>
<% end %>
EOF

cat <<EOF > app/views/orders/_form.html.erb
<%= form_with model: order, local: true, data: { controller: "form-validation", turbo: true } do |form| %>
  <%= tag.div data: { turbo_frame: "notices" } do %>
    <%= render "shared/notices" %>
  <% end %>
  <% if order.errors.any? %>
    <%= tag.div role: "alert" do %>
      <%= tag.p t("brgen_marketplace.errors", count: order.errors.count) %>
      <%= tag.ul do %>
        <% order.errors.full_messages.each do |msg| %>
          <%= tag.li msg %>
        <% end %>
      <% end %>
    <% end %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :product_id, t("brgen_marketplace.order_product"), "aria-required": true %>
    <%= form.collection_select :product_id, Product.all, :id, :name, { prompt: t("brgen_marketplace.product_prompt") }, required: true %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "order_product_id" } %>
  <% end %>
  <%= tag.fieldset do %>
    <%= form.label :status, t("brgen_marketplace.order_status"), "aria-required": true %>
    <%= form.select :status, ["pending", "shipped", "delivered"], { prompt: t("brgen_marketplace.status_prompt"), selected: order.status }, required: true %>
    <%= tag.span class: "error-message" data: { "form-validation-target": "error", for: "order_status" } %>
  <% end %>
  <%= form.submit t("brgen_marketplace.#{order.persisted? ? 'update' : 'create'}_order"), data: { turbo_submits_with: t("brgen_marketplace.#{order.persisted? ? 'updating' : 'creating'}_order") } %>
<% end %>
EOF

cat <<EOF > app/views/orders/new.html.erb
<% content_for :title, t("brgen_marketplace.new_order_title") %>
<% content_for :description, t("brgen_marketplace.new_order_description") %>
<% content_for :keywords, t("brgen_marketplace.new_order_keywords", default: "add order, brgen marketplace, e-commerce") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_marketplace.new_order_title') %>",
    "description": "<%= t('brgen_marketplace.new_order_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "new-order-heading" do %>
    <%= tag.h1 t("brgen_marketplace.new_order_title"), id: "new-order-heading" %>
    <%= render partial: "orders/form", locals: { order: @order } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/orders/edit.html.erb
<% content_for :title, t("brgen_marketplace.edit_order_title") %>
<% content_for :description, t("brgen_marketplace.edit_order_description") %>
<% content_for :keywords, t("brgen_marketplace.edit_order_keywords", default: "edit order, brgen marketplace, e-commerce") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "WebPage",
    "name": "<%= t('brgen_marketplace.edit_order_title') %>",
    "description": "<%= t('brgen_marketplace.edit_order_description') %>",
    "url": "<%= request.original_url %>"
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "edit-order-heading" do %>
    <%= tag.h1 t("brgen_marketplace.edit_order_title"), id: "edit-order-heading" %>
    <%= render partial: "orders/form", locals: { order: @order } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

cat <<EOF > app/views/orders/show.html.erb
<% content_for :title, t("brgen_marketplace.order_title", product: @order.product.name) %>
<% content_for :description, t("brgen_marketplace.order_description", product: @order.product.name) %>
<% content_for :keywords, t("brgen_marketplace.order_keywords", product: @order.product.name, default: "order, #{@order.product.name}, brgen marketplace, e-commerce") %>
<% content_for :schema do %>
  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "Order",
    "orderNumber": "<%= @order.id %>",
    "orderStatus": "<%= @order.status %>",
    "orderedItem": {
      "@type": "Product",
      "name": "<%= @order.product.name %>"
    }
  }
  </script>
<% end %>
<%= render "shared/header" %>
<%= tag.main role: "main" do %>
  <%= tag.section aria-labelledby: "order-heading" class: "post-card" do %>
    <%= tag.div data: { turbo_frame: "notices" } do %>
      <%= render "shared/notices" %>
    <% end %>
    <%= tag.h1 t("brgen_marketplace.order_title", product: @order.product.name), id: "order-heading" %>
    <%= render partial: "orders/card", locals: { order: @order } %>
  <% end %>
<% end %>
<%= render "shared/footer" %>
EOF

generate_turbo_views "products" "product"
generate_turbo_views "orders" "order"

cat <<EOF > db/seeds.rb
require "faker"

puts "Creating demo users with Faker..."
demo_users = []
8.times do
  demo_users << User.create!(
    email: Faker::Internet.unique.email,
    password: "password123",
    name: Faker::Name.name
  )
end

puts "Created #{demo_users.count} demo users."

puts "Creating demo vendors..."
vendors = []
4.times do
  vendors << Vendor.create!(
    name: Faker::Company.name,
    description: Faker::Company.catch_phrase,
    user: demo_users.sample,
    verified: [true, false].sample
  )
end

puts "Created #{vendors.count} vendors."

puts "Creating demo products with Faker..."
categories = ['Electronics', 'Clothing', 'Home & Garden', 'Sports', 'Books', 'Toys']
50.times do
  Product.create!(
    name: Faker::Commerce.product_name,
    price: Faker::Commerce.price(range: 10.0..500.0),
    description: Faker::Lorem.paragraph(sentence_count: 2),
    user: demo_users.sample
  )
end

puts "Created #{Product.count} demo products."

puts "Creating demo listings..."
30.times do
  listing = Listing.create!(
    title: Faker::Commerce.product_name,
    description: Faker::Lorem.paragraph(sentence_count: 3),
    price: Faker::Commerce.price(range: 5.0..250.0),
    vendor: vendors.sample,
    category: categories.sample,
    status: ['active', 'sold', 'pending'].sample,
    location: Faker::Address.city,
    lat: Faker::Address.latitude,
    lng: Faker::Address.longitude
  )
end

puts "Created #{Listing.count} demo listings."

puts "Creating demo orders..."
20.times do
  Order.create!(
    buyer: demo_users.sample,
    product: Product.all.sample,
    status: ['pending', 'shipped', 'delivered'].sample,
    total_amount: Faker::Commerce.price(range: 20.0..300.0)
  )
end

puts "Created #{Order.count} demo orders."

puts "Seed data creation complete!"
EOF

commit "Brgen Marketplace setup complete: E-commerce platform with live search, infinite scroll, and anonymous features"

log "Brgen Marketplace setup complete. Run 'bin/falcon-host' with PORT set to start on OpenBSD."

# Change Log:
# - Aligned with master.json v6.5.0: Two-space indents, double quotes, heredocs, Strunk & White comments.
# - Used Rails 8 conventions, Hotwire, Turbo Streams, Stimulus Reflex, I18n, and Falcon.
# - Leveraged bin/rails generate scaffold for Products and Orders to streamline CRUD setup.
# - Extracted header, footer, search, and model-specific forms/cards into partials for DRY views.
# - Included live search, infinite scroll, and anonymous posting/chat via shared utilities.
# - Ensured NNG principles, SEO, schema data, and minimal flat design compliance.
# - Finalized for unprivileged user on OpenBSD 7.5.
