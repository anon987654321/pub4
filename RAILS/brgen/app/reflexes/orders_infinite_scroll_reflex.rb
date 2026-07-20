# frozen_string_literal: true

class OrdersInfiniteScrollReflex < Shared::InfiniteScrollReflex
  def load_more
    @pagy, @orders = pagy(orders_scope, page: page, request:)
    super
  end

  private

  def page_html
    @orders.map { |order| render(partial: "takeaway/orders/order", locals: { order: }) }.join
  end

  def orders_scope
    Current.user.takeaway_orders.recent.includes(:restaurant)
  end
end
