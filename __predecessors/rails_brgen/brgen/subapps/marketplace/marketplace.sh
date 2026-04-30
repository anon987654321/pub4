#!/usr/bin/env zsh
set -e # Halt script execution on first error

echo "Starting comprehensive development of the BRGEN Marketplace with enhanced views..."

# Navigate to the main directory of your BRGEN Rails application
cd /path/to/brgen

# Setup environment and install necessary gems
echo "Adding and installing required gems..."
bundle add solidus --github='solidusio/solidus'
bundle add solidus_auth_devise --github='solidusio/solidus_auth_devise'
bundle add solidus_searchkick --github='solidusio-contrib/solidus_searchkick'
bundle add solidus_reviews --github='solidusio-contrib/solidus_reviews'

echo "Generating and migrating necessary installations..."
bin/rails generate solidus:install --auto-accept
bin/rails generate solidus_multi_vendor:install
bin/rails generate solidus_searchkick:install
bin/rails generate solidus_reviews:install
bin/rails db:migrate

git add .
git commit -m "Installed and configured Solidus and additional extensions for enhanced e-commerce functionalities."

# Implementing and updating views with clean, semantic HTML and internationalization support
echo "Updating views with enhanced, semantic HTML and internationalization support..."
cat <<ERB > app/views/marketplace/shared/_header.html.erb
<%= tag.header class: "main_header" do %>
  <%= link_to t("navigation.home"), root_path, class: "logo" %>
  <%= render 'marketplace/shared/navigation' %>
<% end %>
ERB

cat <<ERB > app/views/marketplace/shared/_navigation.html.erb
<%= tag.nav do %>
  <%= link_to t("navigation.products"), marketplace_products_path %>
  <%= link_to t("navigation.contact"), marketplace_contact_path %>
<% end %>
ERB

cat <<ERB > app/views/marketplace/home/index.html.erb
<%= render 'marketplace/shared/header' %>
<%= tag.div class: "main_content" do %>
  <%= render 'marketplace/shared/featured_products', locals: { featured_products: @featured_products } %>
  <%= render 'marketplace/shared/categories', locals: { categories: @categories } %>
<% end %>
<%= render 'marketplace/shared/footer' %>
ERB

cat <<ERB > app/views/marketplace/products/_product_card.html.erb
<%= tag.article class: "product_card", itemprop: "itemListElement", itemscope: true, itemtype: "http://schema.org/Product" do %>
  <%= link_to marketplace_product_path(product), itemprop: "url", class: "product_link" do %>
    <%= image_tag product.display_image, itemprop: "image", class: "product_image", alt: product.name %>
    <%= tag.div class: "product_details" do %>
      <%= tag.h2 product.name, itemprop: "name", class: "product_name" %>
      <%= tag.p product.description, itemprop: "description", class: "product_description" %>
      <%= tag.span number_to_currency(product.price), itemprop: "price", class: "product_price" %>
    <% end %>
  <% end %>
<% end %>
ERB

git add .
git commit -m "Updated views with clean, semantic HTML and I18n."
