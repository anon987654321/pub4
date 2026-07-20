# frozen_string_literal: true

class WardrobeAnalytics
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
      declutter_box: items.declutter_box.count,
      sentimental_archive: items.sentimental.count,
      seasonal_archived: items.seasonal_archived.count,
      by_category: items.group(:category).count,
      by_season: items.group(:season).count,
      cost_per_wear: average_cost_per_wear,
      tips: tips,
      tips_source: "rules",
      overdue_challenges: DeclutterChallenge.where(user: user).overdue.count,
      active_challenges: DeclutterChallenge.where(user: user).active.count
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

  # Rule-based coach — not an LLM. Labelled as such in the UI.
  def tips
    [
      ("Wear one never-worn item this week" if items.never_worn.exists?),
      ("Repair or release items marked for repair" if items.where(lifecycle_state: "repair").exists?),
      ("Build one outfit around an underused piece" if items.any?(&:underused?)),
      ("#{items.declutter_box.count} items waiting in the declutter box" if items.declutter_box.exists?),
      ("#{DeclutterChallenge.where(user: user).overdue.count} wear challenges are overdue" if DeclutterChallenge.where(user: user).overdue.exists?)
    ].compact
  end
end
