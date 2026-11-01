# frozen_string_literal: true

# The buyer's own order history. Named for the reader rather than the model,
# because OrdersInfiniteScrollReflex is takeaway's and these are two different
# lists in two different engines.
class BuyerOrdersInfiniteScrollReflex < Shared::InfiniteScrollReflex
  renders "marketplace/orders/order_row", as: :order, wrap_in: :li

  private

  def scope
    Marketplace::Order.where(buyer_id: Current.user.id)
                      .includes(:listing)
                      .order(created_at: :desc)
  end
end
