# frozen_string_literal: true

module Marketplace
  # The seller's side of the order list: orders placed on their listings,
  # newest first, narrowed to one status when asked. The buyer's side is
  # OrdersController#index's own query.
  module Sales
    STATUSES = Order::STATUSES

    module_function

    def for(seller, status: nil)
      orders = Order.joins(:listing).where(listing: { user_id: seller.id })
      orders = orders.where(status:) if STATUSES.include?(status)
      orders.includes(:buyer, listing: :category).order(created_at: :desc)
    end
  end
end
