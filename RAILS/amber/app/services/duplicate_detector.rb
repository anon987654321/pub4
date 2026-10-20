# frozen_string_literal: true

class DuplicateDetector
  def initialize(user)
    @user = user
  end

  def groups(min_size: 2)
    @user.items.active_wardrobe.group_by(&:duplicate_key).values.select { |items| items.size >= min_size }
  end

  def ranked_groups
    groups.map do |items|
      {
        key: items.first.duplicate_key,
        count: items.size,
        keeper: best_keeper(items),
        candidates: release_candidates(items),
        reason: reason_for(items)
      }
    end.sort_by { |group| -group[:count] }
  end

  private

  def best_keeper(items)
    items.max_by { |item| [ item.times_worn.to_i, item.spark_joy? ? 1 : 0, -(item.cost_per_wear || 0) ] }
  end

  def release_candidates(items)
    keeper = best_keeper(items)
    items.reject { |item| item == keeper }.sort_by { |item| [ -item.declutter_score[:total_release_score], item.times_worn.to_i ] }
  end

  def reason_for(items)
    first = items.first
    I18n.t("duplicates.reason",
           count: items.size,
           color: first.color.presence,
           category: first.category.to_s.downcase).squish
  end
end
