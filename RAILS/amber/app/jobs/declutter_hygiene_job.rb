# frozen_string_literal: true

# Daily KonMari hygiene: expire overdue wear challenges; nudge 30-day declutter box items.
class DeclutterHygieneJob < ApplicationJob
  queue_as :default

  BOX_DAYS = 30
  # The reason text is written to a row that outlives any locale change,
  # so the key travels with it in metadata and the copy is rendered from it.
  REASON_KEY = "amber.declutter.box_elapsed"

  def perform
    expire_challenges
    nudge_aging_box_items
  end

  private

  def expire_challenges
    DeclutterChallenge.overdue.find_each(&:expire!)
  end

  def nudge_aging_box_items
    # includes(:user): strict_loading_by_default made item.user raise on the
    # first record, so this job has never nudged anything. The preload also
    # turns a user lookup per boxed item into one query.
    Item.declutter_box.includes(:user).find_each do |item|
      boxed_on = box_date_for(item)
      next if boxed_on > BOX_DAYS.days.ago.to_date

      # Deduped on the marker in metadata rather than on an English substring
      # of the reason text — the old LIKE stopped matching the moment the copy
      # was translated, which would have produced a duplicate nudge per run.
      existing = item.user.recommendations.active.where(kind: "declutter", item: item)
        .where("json_extract(metadata, '$.reason_key') = ?", REASON_KEY)
      next if existing.exists?

      item.user.recommendations.create!(
        kind: "declutter",
        item: item,
        reason: I18n.t(REASON_KEY, title: item.title),
        score: item.declutter_score[:total_release_score],
        metadata: { reason_key: REASON_KEY, title: item.title,
                    boxed_on: boxed_on.iso8601, days_in_box: (Date.current - boxed_on).to_i }
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
