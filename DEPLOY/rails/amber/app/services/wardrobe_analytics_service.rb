# frozen_string_literal: true

class WardrobeAnalyticsService
  def self.dashboard_for(user)
    new(user).dashboard
  end

  def initialize(user)
    @user = user
  end

  def dashboard
    items = @user.items.active_wardrobe
    wears = WearLog.where(user: @user)
    {
      total_items: items.count,
      total_wears: wears.count,
      cost_per_wear_avg: average_cpw(items),
      category_breakdown: items.group(:category).count,
      most_worn: items.worn_most.limit(5),
      least_worn: items.never_worn.limit(5),
      sustainability_score: sustainability_score(items)
    }
  end

  private

  def average_cpw(items)
    values = items.filter_map { |i| i.cost_per_wear }.compact
    values.any? ? (values.sum / values.size).round(2) : nil
  end

  def sustainability_score(items)
    metric = SustainabilityMetric.where(item_id: items.select(:id)).average(:score)
    metric&.round(1)
  end
end