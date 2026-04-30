echo "Setting up Takeaway subapp..."
# Generate models for Takeaway items and orders
bin/rails generate model Takeaway::Item name:string description:text price:decimal
bin/rails generate model Takeaway::Order user:references status:string
bin/rails db:migrate

# Creating Takeaway controllers and views
mkdir -p app/controllers/takeaway
cat <<RUBY > app/controllers/takeaway/items_controller.rb
module Takeaway
  class ItemsController < ApplicationController
    def index
      @items = Item.all
    end

    def show
      @item = Item.find(params[:id])
    end
  end
end
RUBY

mkdir -p app/views/takeaway/items
cat <<ERB > app/views/takeaway/items/index.html.erb
<%= tag.div do %>
  <% @items.each do |item| %>
    <%= tag.div itemscope itemtype="http://schema.org/Product" do %>
      <%= link_to item.name, takeaway_item_path(item), itemprop: "name" %>
      <%= tag.p item.description, itemprop: "description" %>
      <%= tag.span number_to_currency(item.price), class: "price", itemprop: "price" %>
    <% end %>
  <% end %>
<% end %>
ERB

git add .
git commit -m "Setup Takeaway subapp with models, controllers, and views including schema.org microdata"
