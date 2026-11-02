# frozen_string_literal: true

class Courier::RunsController < ApplicationController
  before_action -> { require_role!(:courier) }

  # Two lists (APP_SPEC §7): ready for pickup + on the way, with address,
  # total and the pickup/deliver buttons.
  def show
    @ready_orders = Order.where(state: "ready").includes(:order_items).order(:placed_at, :id)
    @on_the_way_orders = Order.where(state: "picked_up").includes(:order_items).order(:placed_at, :id)
  end

  # ready → picked_up: the bag goes in the courier bag (APP_SPEC §4).
  def pickup
    order = Order.find(params[:id])

    begin
      order.pickup!
      redirect_to courier_runs_path, notice: t("courier.picked_up")
    rescue Order::InvalidTransition, ActiveRecord::RecordInvalid
      redirect_to courier_runs_path, alert: t("courier.cannot_pickup")
    end
  end

  # picked_up → delivered — this also awards the Sahtein stamp (Order#deliver!).
  def deliver
    order = Order.find(params[:id])

    begin
      order.deliver!
      redirect_to courier_runs_path, notice: t("courier.delivered")
    rescue Order::InvalidTransition, ActiveRecord::RecordInvalid
      redirect_to courier_runs_path, alert: t("courier.cannot_deliver")
    end
  end
end
