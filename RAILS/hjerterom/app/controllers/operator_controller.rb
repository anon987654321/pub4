# frozen_string_literal: true

class OperatorController < ApplicationController
  before_action :require_real_user

  def index
    @today_shifts = Shift.where(starts_at: Time.current.beginning_of_day..Time.current.end_of_day).order(:starts_at)
    @open_shifts = Shift.where(state: :open).future.limit(10)
    @open_requests = FoodRequest.where(status: %w[pending open]).order(created_at: :desc).limit(10)
    @reuse_counts = FoodItem.group(:category).count
    @urgent_items = FoodItem.urgent.available.limit(10)
    @route = DeliveryRoute.find_by(route_date: Date.current) || RoutePlanner.build_for
    @notification_failures = SolidQueue::FailedExecution.order(created_at: :desc).limit(5) if defined?(SolidQueue::FailedExecution)
    @next_action = next_recommended_action
  end

  private

  def next_recommended_action
    return "Assign an open shift" if @open_shifts.any?
    return "Review pending food requests" if @open_requests.any?
    return "Pack urgent reuse items" if @urgent_items.any?

    "All clear — review today's route"
  end
end