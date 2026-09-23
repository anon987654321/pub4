# frozen_string_literal: true

# law/rails.rb — semantic laws whose subject is the Rails application boundary.
#
# Rails is a domain here rather than a universal principle. Keeping these four
# questions together lets /fix load one Rails-specific semantic home without
# making the universal constitution carry framework vocabulary.

Law.define(:RAILS_THIN_CONTROLLER_SEMANTIC) do
  source "MASTER Rails architecture — thin controllers"
  severity :warning
  languages %i[ruby]
  ask "If this is a Rails controller, are actions owning business rules, multi-model orchestration, or heavy queries instead of delegating to models/services? Cite method names. If it is not a controller or is already thin, return CLEAN."
  fix "Move business rules and orchestration into focused models or services; keep controller actions responsible for boundary concerns."
  bad <<~X
    class OrdersController < ApplicationController
      def create
        customer = Customer.find(params[:customer_id])
        product = Product.find(params[:product_id])
        order = Order.create!(customer:, product:, total: product.price * 1.25)
        Mailer.order_created(order).deliver_later
        redirect_to order
      end
    end
  X
  good <<~X
    class OrdersController < ApplicationController
      def create
        order = Orders::Create.call(customer_id: params[:customer_id], product_id: params[:product_id])
        redirect_to order
      end
    end
  X
end

Law.define(:RAILS_VIEW_PURITY) do
  source "MASTER Rails architecture — view purity"
  severity :warning
  languages %i[html]
  ask "If this is a Rails view or partial, does it contain queries, persistence, or multi-step business condition trees that belong in helpers, models, or presenters? Prefer CLEAN when it only presents assigns."
  fix "Move business logic out of the view; pass prepared assigns and use focused presentation helpers or presenters."
  bad <<~X
    <% orders = Order.where(user_id: current_user.id).select { |o| o.total > 1000 } %>
    <% orders.each { |order| order.update!(reviewed: true) } %>
    <%= orders.count %>
  X
  good <<~X
    <% @orders.each do |order| %>
      <%= render order %>
    <% end %>
  X
end

Law.define(:AESTHETIC_FLAT_SEMANTIC) do
  source "MASTER UI aesthetic — flat 8px-rhythm surfaces"
  severity :info
  mode :opportunity
  languages %i[css scss html javascript]
  ask "Score the UI surface for flat, pixel-precise design: reject ornamental shadow, blur, or glow; uneven spacing off an 8px rhythm; weak hierarchy; and decorative particles. Propose concrete token, spacing, and type fixes. Return CLEAN when already flat and rhythmic."
  fix "Remove ornamental depth, normalize spacing onto the 8px rhythm, strengthen hierarchy, and make decoration earn its place."
  bad <<~X
    .card {
      margin: 13px;
      box-shadow: 0 18px 50px rgba(0, 0, 0, .35);
      filter: blur(2px);
    }
  X
  good <<~X
    .card {
      margin: 16px;
      box-shadow: none;
      filter: none;
    }
  X
end

Law.define(:AESTHETIC_RAMS_SEMANTIC) do
  source "Dieter Rams — useful, understandable, unobtrusive, honest, thorough"
  severity :info
  mode :opportunity
  languages %i[html css scss]
  ask "Apply useful, understandable, unobtrusive, honest, and thorough to this UI surface. Flag dishonest progress, missing empty or error states, or chrome that competes with content. Return CLEAN when the surface is solid."
  fix "Make the primary state useful and legible, represent progress and failure honestly, cover empty states, and remove chrome that competes with the content."
  bad <<~X
    <div class="dashboard">
      <div class="spinner">100%</div>
      <div class="content"></div>
    </div>
  X
  good <<~X
    <main class="dashboard">
      <h1>Orders</h1>
      <p>No orders yet.</p>
    </main>
  X
end
