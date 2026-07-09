# frozen_string_literal: true

class HomeController < ApplicationController
  include Shared::MasterGuestHome

  def index
    return render_master_guest_home!(title: "Amber") if params[:master].present? && master_guest_home?
    return unless authenticated?

    items = Current.user.items
    @items_count      = items.count
    @joy_count        = items.joy.count
    @never_worn_count = items.never_worn.count
    @worn_this_month  = items.where("updated_at > ?", 30.days.ago).where("times_worn > 0").count
    @utilization_rate = @items_count > 0 ? (@worn_this_month * 100.0 / @items_count).round : 0
    @worst_cpw        = items.where("price > 0 AND times_worn > 0")
                             .select { |i| i.cost_per_wear }
                             .sort_by { |i| -i.cost_per_wear }
                             .first(3)
    @aging_unworn     = items.aging_unworn.limit(4)
    @recent_items     = items.recent.limit(6)
    @planned_this_week = Current.user.planned_outfits.this_week.includes(:outfit)
    @weather          = WeatherService.today
  end
end
