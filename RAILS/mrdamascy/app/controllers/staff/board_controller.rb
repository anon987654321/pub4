# frozen_string_literal: true

class Staff::BoardController < ApplicationController
  # Columns Placed/Confirmed/Preparing/Ready (APP_SPEC §7); from ready the
  # board shows "—" and the courier takes over.
  BOARD_STATES = Order::BOARD_STATES

  before_action -> { require_role!(:staff) }

  def show
    @orders_by_state = Order.board_columns
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
