# frozen_string_literal: true

# One ticket, several people, one delivery.
class Takeaway::GroupOrdersController < Takeaway::BaseController
  before_action :require_user_session

  # The host opens the ticket to the link. Their own order, and only while the
  # kitchen has not been told about it.
  def create
    order = Current.user.takeaway_orders.find(params[:order_id])
    return redirect_to(order_path(order), alert: t("flash.takeaway.group_too_late")) unless order.status == "pending"

    order.open_group!
    redirect_to order_path(order), notice: t("flash.takeaway.group_opened")
  end

  # Anyone with the link. The token is the invitation — an order id in a link
  # pasted into a group chat would let somebody read the next lunch by counting.
  def show
    @order = Takeaway::Order.includes(:restaurant, order_items: %i[menu_item user]).find_by!(group_token: params[:id])
    return redirect_to(root_path, alert: t("flash.takeaway.group_closed")) unless @order.joinable?

    @menu_items = @order.restaurant.menu_items.where(available: true).order(:name)
  end

  # Adding your own line to somebody else's ticket.
  def update
    order = joinable_order or return

    item = order.restaurant.menu_items.find(params.require(:menu_item_id))
    quantity = params[:quantity].to_i.clamp(1, 20)
    order.order_items.create!(menu_item: item, quantity: quantity,
                              unit_price_cents: item.price_cents, user: Current.user)
    recalculate(order)
    redirect_to group_order_path(order.group_token), notice: t("flash.takeaway.group_line_added")
  end

  # Taking your own line back off it. Yours only: a ticket where anyone can
  # delete anyone's lunch is a ticket people stop sharing.
  def destroy
    order = joinable_order or return

    line = order.order_items.find_by!(id: params.require(:line_id), user_id: Current.user.id)
    line.destroy
    recalculate(order)
    redirect_to group_order_path(order.group_token), notice: t("flash.takeaway.group_line_removed")
  end
  private

  # Preloaded, and answered once: calculate_totals! sums order_items.target, so
  # an order found bare would total zero, and Takeaway::MenuItem reads its
  # restaurant while validating availability — a lazy read on a strict-loading
  # record.
  def joinable_order
    order = Takeaway::Order.includes(:restaurant, order_items: :menu_item).find_by!(group_token: params[:id])
    return order if order.joinable?

    redirect_to(root_path, alert: t("flash.takeaway.group_closed"))
    nil
  end

  # The line was just written, so the in-memory list is one behind it.
  def recalculate(order)
    order.order_items.reload
    order.calculate_totals!
  end
end
