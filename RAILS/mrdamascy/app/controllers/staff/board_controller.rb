# frozen_string_literal: true

class Staff::BoardController < ApplicationController
  # Columns Placed/Confirmed/Preparing/Ready (APP_SPEC §7); from ready the
  # board shows "—" and the courier takes over.
  BOARD_STATES = Order::BOARD_STATES

  before_action -> { require_role!(:staff) }

  def show
    @orders_by_state = Order.board_columns
    @refunds_due = Order.refunds_due
  end

  # Cancel a placed or confirmed order (Order#cancel!). Neither payment client
  # can refund, so a paid order is left owing a manual refund and the toast
  # tells staff where to make it; the refunds list keeps it until marked.
  def cancel
    @order = Order.find(params[:id])
    @order.cancel!
    if @order.refund_due?
      respond_on_board(:alert, t("staff.cancelled_refund_due", id: @order.id, amount: helpers.money(@order.total_ore),
                                                                lane: @order.payment_lane_name))
    else
      respond_on_board(:notice, t("staff.cancelled", id: @order.id))
    end
  rescue Order::InvalidTransition, ActiveRecord::RecordInvalid
    respond_on_board(:alert, t("staff.cannot_cancel"))
  end

  # Staff made the manual refund in the provider's portal.
  def refunded
    @order = Order.find(params[:id])
    @order.mark_refunded!
    respond_on_board(:notice, t("staff.refunded", id: @order.id))
  rescue Order::InvalidTransition
    respond_on_board(:alert, t("staff.cannot_refund"))
  end

  # One big touch target per order card: advance the kitchen state and swap
  # the card in place via Turbo Stream (APP_SPEC §6).
  def advance
    @order = Order.find(params[:id])
    advanced = advance_order_safely

    respond_to do |format|
      format.turbo_stream do
        if advanced
          flash.now[:notice] = t("staff.advanced")
        else
          flash.now[:alert] = t("staff.cannot_advance")
        end
        render turbo_stream: [ board_toast_stream ] + board_card_streams
      end
      format.html do
        if advanced
          redirect_to staff_board_path, notice: t("staff.advanced")
        else
          redirect_to staff_board_path, alert: t("staff.cannot_advance")
        end
      end
    end
  end

  # Overflow courier lane: hand a READY delivery order to Wolt Drive
  # (white-label last-mile — APP_SPEC §5 analog for couriers). Mock mode
  # assigns "Bergen Bud" instantly; real mode calls the Wolt Drive API.
  def wolt_dispatch
    @order = Order.find(params[:id])
    dispatched = dispatch_wolt_safely

    respond_to do |format|
      format.turbo_stream do
        flash.now[dispatched ? :notice : :alert] =
          dispatched ? t("staff.wolt_dispatched", courier: @courier) : t("staff.wolt_failed")
        render turbo_stream: [ board_toast_stream ] + board_card_streams
      end
      format.html do
        if dispatched
          redirect_to staff_board_path, notice: t("staff.wolt_dispatched", courier: @courier)
        else
          redirect_to staff_board_path, alert: t("staff.wolt_failed")
        end
      end
    end
  end

  private

  # Cancel and refund answer the same way: the toast, the order's card and the
  # refunds list in place, or a redirect back to the board.
  def respond_on_board(kind, message)
    respond_to do |format|
      format.turbo_stream do
        flash.now[kind] = message
        refunds = turbo_stream.replace("refunds_due", partial: "staff/board/refunds",
                                                      locals: { refunds: Order.refunds_due })
        render turbo_stream: [ board_toast_stream, refunds ] + board_card_streams
      end
      format.html { redirect_to staff_board_path, kind => message }
    end
  end

  def advance_order_safely
    @order.advance!
    true
  rescue Order::InvalidTransition, ActiveRecord::RecordInvalid
    false
  end

  # Only ready, delivery-mode orders without a dispatch yet are eligible —
  # anything else is a no-op so a stale board card can never double-dispatch.
  def dispatch_wolt_safely
    return false unless @order.state == "ready" && @order.delivery? && @order.external_delivery_id.blank?

    result = WoltDriveClient.request_delivery(order: @order)
    @courier = result[:courier].presence || "Wolt"
    true
  rescue WoltDriveClient::NotAvailable, ActiveRecord::RecordInvalid
    false
  end

  # Card contract: every board card renders with dom id "order_card_<id>"
  # (staff/board/_order_card). A card that left the board (picked_up after
  # ready) is removed; the toast is the shared flash partial, replacing
  # whatever the layout's div#toasts held.
  def board_card_streams
    if @order.state.in?(BOARD_STATES)
      [ turbo_stream.replace(
        "order_card_#{@order.id}", partial: "staff/board/order_card", locals: { order: @order }
      ) ]
    else
      [ turbo_stream.remove("order_card_#{@order.id}") ]
    end
  end

  def board_toast_stream
    turbo_stream.update("toasts", partial: "shared/toast")
  end
end
