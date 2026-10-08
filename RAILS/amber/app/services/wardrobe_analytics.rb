# frozen_string_literal: true

# Counts for the wardrobe, in SQL.
#
# This used to materialise the whole wardrobe twice per call — `select(&:underused?)`
# and `filter_map(&:cost_per_wear)` both load every row into Ruby to answer a
# question the database can answer — and then fire another dozen COUNT queries,
# several of them repeats issued a second time by `tips`. It runs on `items#index`
# as well as the analytics page, so it sat on the hot path.
#
# Now: one grouped count covers every lifecycle bucket including the total, two
# scoped counts cover wear, one aggregate covers cost-per-wear, and `tips` reads
# the memoised numbers instead of re-asking.
class WardrobeAnalytics
  # Item.active_wardrobe is the complement of these.
  RELEASED_STATES = %w[released donated sold recycled].freeze

  def initialize(user)
    @user = user
  end

  def summary
    {
      total_items: total_items,
      active_items: active_items,
      never_worn: never_worn,
      underused: underused,
      repair: state_count("repair"),
      declutter_box: declutter_box,
      sentimental_archive: state_count("sentimental_archive"),
      seasonal_archived: state_count("seasonal_archive"),
      by_category: items.group(:category).count,
      by_season: items.group(:season).count,
      cost_per_wear: average_cost_per_wear,
      tips: tips,
      tips_source: "rules",
      overdue_challenges: overdue_challenges,
      active_challenges: DeclutterChallenge.where(user: user).active.count
    }
  end

  private

  attr_reader :user

  def items = user.items

  # lifecycle_state is NOT NULL with a default, so this one query carries every
  # bucket and the total.
  def counts_by_state = @counts_by_state ||= items.group(:lifecycle_state).count
  def state_count(state) = counts_by_state.fetch(state, 0)

  def total_items = @total_items ||= counts_by_state.values.sum
  def active_items = @active_items ||= total_items - RELEASED_STATES.sum { |state| state_count(state) }
  def declutter_box = @declutter_box ||= state_count("declutter_box")
  def never_worn = @never_worn ||= items.never_worn.count
  def underused = @underused ||= items.underused.count
  def overdue_challenges = @overdue_challenges ||= DeclutterChallenge.where(user: user).overdue.count

  # The mean of each garment's own cost-per-wear, not total spend over total
  # wears — a garment worn once should pull the average up on its own terms.
  def average_cost_per_wear
    items.where.not(price_cents: nil).where("times_worn > 0")
         .pick(Arel.sql("AVG(price_cents / 100.0 / times_worn)"))
         &.round(2)
  end

  # Rule-based coach — not an LLM. Labelled as such in the UI, and translated:
  # these sit under a `t()`-rendered heading on a Norwegian-default page.
  def tips
    [
      (t("never_worn") if never_worn.positive?),
      (t("repair") if state_count("repair").positive?),
      (t("underused") if underused.positive?),
      (t("declutter_box", count: declutter_box) if declutter_box.positive?),
      (t("overdue", count: overdue_challenges) if overdue_challenges.positive?)
    ].compact
  end

  def t(key, **interpolations) = I18n.t("coach.#{key}", **interpolations)
end
