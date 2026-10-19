# frozen_string_literal: true

class CapsuleBuilder
  DEFAULT_LIMIT = 12

  def initialize(user)
    @user = user
  end

  def build(limit: DEFAULT_LIMIT, occasion: nil, season: nil)
    candidates = @user.items.joy
    candidates = candidates.by_occasion(occasion) if occasion.present?
    candidates = candidates.where(season: [ season, "All-Season", nil, "" ]) if season.present?

    selected = []
    Item::CATEGORIES.each do |category|
      item = candidates.by_category(category).worn_most.first || candidates.by_category(category).recent.first
      selected << item if item
    end

    remaining = candidates.where.not(id: selected.compact.map(&:id)).sort_by do |item|
      [ -(item.times_worn.to_i), item.cost_per_wear || 999_999, item.created_at || Time.current ]
    end

    (selected.compact + remaining).uniq.first(limit)
  end

  def explain(items)
    items.map do |item|
      {
        id: item.id,
        title: item.title,
        category: item.category,
        reason: reason_for(item)
      }
    end
  end

  private

  def reason_for(item)
    return "High utility: worn #{item.times_worn} times." if item.times_worn.to_i.positive?
    return "Strong emotional signal: sparks joy." if item.spark_joy?

    "Adds category coverage for #{item.category}."
  end
end
