# frozen_string_literal: true

# A pending order is a line in the buyer's cart, and the buyer decides how many
# and whether it stays. OrdersController#update is the seller's side of the same
# row — accept or decline — which is why the cart does not post there.
class Marketplace::CartItemsController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_item

  def update
    quantity = params[:quantity].to_i
    available = @item.listing.available_quantity

    if @item.open_offer? && quantity.between?(1, available)
      @item.update!(quantity: quantity)
      redirect_to cart_path, notice: t("marketplace.cart_quantity_updated")
    else
      redirect_to cart_path, alert: t("marketplace.cart_quantity_refused", available: available)
    end
  end

  # Withdrawn, not deleted: the seller was told about the offer, and their list
  # of offers keeps the row with its answer.
  def destroy
    @item.update!(status: "declined") if @item.open_offer?
    redirect_to cart_path, notice: t("marketplace.cart_item_removed")
  end

  private

  def set_item
    @item = Current.user.marketplace_orders.includes(:listing).find(params[:id])
  end
end
