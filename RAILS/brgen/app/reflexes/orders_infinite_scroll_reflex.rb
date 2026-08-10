# frozen_string_literal: true

class OrdersInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "takeaway/orders/order", as: :order

  private

  def scope
    Current.user.takeaway_orders.recent.includes(:restaurant)
  end
end
