# frozen_string_literal: true

class WardrobeAnalyticsService
  def initialize(user)
    @user = user
  end

  def summary
    {
      total_items: items.count,
      active_items: items.active_wardrobe.count,
      never_worn: items.never_worn.count,
      underused: items.select(&:underused?).count,
      repair: items.where(lifecycle_state: "repair").count,
      by_category: items.group(:category).count,
      by_season: items.group(:season).count,
      cost_per_wear: average_cost_per_wear,
      tips: tips
    }
  end

  private

  attr_reader :user

  def items = user.items

  def average_cost_per_wear
    values = items.filter_map(&:cost_per_wear)
    return nil if values.empty?

    (values.sum / values.size).round(2)
  end

  def tips
    [
      ("Wear one never-worn item this week" if items.never_worn.exists?),
      ("Repair or release items marked for repair" if items.where(lifecycle_state: "repair").exists?),
      ("Build one outfit around an underused piece" if items.any?(&:underused?))
    ].compact
  end
end
