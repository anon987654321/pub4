# frozen_string_literal: true

# Daily KonMari hygiene: expire overdue wear challenges; nudge 30-day declutter box items.
class DeclutterHygieneJob < ApplicationJob
  queue_as :default

  BOX_DAYS = 30

  def perform
    expire_challenges
    nudge_aging_box_items
  end

  private

  def expire_challenges
    DeclutterChallenge.overdue.find_each(&:expire!)
  end

  def nudge_aging_box_items
    Item.declutter_box.find_each do |item|
      boxed_on = box_date_for(item)
      next if boxed_on > BOX_DAYS.days.ago.to_date

      existing = item.user.recommendations.active.where(kind: "declutter", item: item)
        .where("reason LIKE ?", "%30-day declutter box%")
      next if existing.exists?

      item.user.recommendations.create!(
        kind: "declutter",
        item: item,
        reason: "30-day declutter box elapsed for «#{item.title}» — sell, donate, or restore with intention.",
        score: item.declutter_score[:total_release_score],
        metadata: { boxed_on: boxed_on.iso8601, days_in_box: (Date.current - boxed_on).to_i }
      )
    end
  end

  def box_date_for(item)
    raw = item.metadata.is_a?(Hash) ? item.metadata["declutter_box_at"] : nil
    Date.parse(raw.to_s)
  rescue ArgumentError, TypeError
    item.updated_at.to_date
  end
end
