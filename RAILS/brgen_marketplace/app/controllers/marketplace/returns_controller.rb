# frozen_string_literal: true

# Asking to send it back, and the seller answering.
class Marketplace::ReturnsController < Marketplace::BaseController
  before_action :require_user_session
  before_action :set_order

  def create
    unless @order.returnable_by?(Current.user)
      redirect_to order_path(@order), alert: t("flash.marketplace.return_not_available")
      return
    end

    marketplace_return = @order.returns.new(reason: params.require(:return)[:reason])
    if marketplace_return.save
      marketplace_return.deliver_notification(@order.seller, title: t("marketplace.return_requested_title"),
                                              body: marketplace_return.reason.to_s.truncate(120),
                                              source: marketplace_return, kind: "order")
      redirect_to order_path(@order), notice: t("flash.marketplace.return_requested")
    else
      redirect_to order_path(@order), alert: marketplace_return.errors.full_messages.first
    end
  end

  # The seller answers: approve, refuse, or confirm the item is back.
  def update
    marketplace_return = @order.returns.find(params[:id])
    return head :forbidden unless @order.seller == Current.user

    case params[:decision]
    when "approve" then marketplace_return.approve!(by: Current.user, note: params[:note])
    when "refuse" then marketplace_return.refuse!(by: Current.user, note: params[:note])
    when "receive" then marketplace_return.receive!(by: Current.user)
    else return redirect_to(order_path(@order), alert: t("flash.marketplace.return_no_decision"))
    end
    redirect_to order_path(@order), notice: t("flash.marketplace.return_updated")
  end

  private

  def set_order = (@order = Marketplace::Order.includes(listing: :user, buyer: {}).find(params[:order_id]))
end
