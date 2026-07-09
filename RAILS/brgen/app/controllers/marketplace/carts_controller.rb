# frozen_string_literal: true

class Marketplace::CartsController < Marketplace::BaseController
  before_action :authenticate_user!

  def show
    @cart_items = Current.user.marketplace_orders
                         .where(status: "pending")
                         .includes(:listing)
                         .order(created_at: :desc)

    @cart_total = @cart_items.sum(&:total_cents)
  end
end
