# frozen_string_literal: true

# Cleaning, organising and storing guidance for a wardrobe.
#
# The original Amber specification asked for "tips for cleaning, organizing, and
# storing your wardrobe using architecture, interior design and zen minimalism
# combined with smart algorithms". `WardrobeAnalytics#tips` covered none of that
# — it is five wear-and-declutter nudges — so this service owns the other three
# registers and reads the wardrobe to decide which apply.
#
# Four registers, each named for the discipline it borrows from:
#
#   :care      cleaning and repair, driven by lifecycle state, WardrobeItem
#              condition, and material care rules
#   :storage   what to fold, what to hang, what to archive out of season
#   :zoning    architecture's reach zones — prime reach for what is worn daily,
#              high and deep storage for what is not
#   :restraint zen minimalism — rod density, duplicates, one-in-one-out
#
# Every tip is a rule with a stated principle and the wardrobe evidence that
# triggered it. No LLM is involved; `source` says `rules` so the UI can say so
# too, the same honesty contract `WardrobeAnalytics#tips_source` already keeps.
#
# The copy lives under `closet.tips.<id>` in the locale files rather than in
# this file. Amber defaults to Norwegian, so a rules engine that only speaks
# English produces a page half in each language.
class ClosetOrganization
  Tip = Data.define(:id, :register, :title, :body, :principle, :count) do
    def to_h = { id:, register:, title:, body:, principle:, count: }
  end

  REGISTERS = %i[care storage zoning restraint].freeze

  # Hanging distorts anything heavy and knitted; folding creases anything
  # structured. Matched against Item#material.
  FOLD_MATERIALS = /knit|wool|cashmere|alpaca|merino|jersey|sweat/i
  HANG_MATERIALS = /silk|linen|viscose|rayon|tailor|suit|satin/i
  BREATHE_MATERIALS = /leather|suede|shearling|fur/i

  # Material families with care advice, in match order. Each key is also its
  # locale key under `closet.materials` and `closet.tips.material_*`.
  MATERIAL_FAMILIES = {
    wool: /wool|cashmere|merino|alpaca/i,
    silk: /silk|satin/i,
    linen: /linen/i,
    leather: /leather|suede/i,
    denim: /denim/i,
    cotton: /cotton/i,
  }.freeze

  # Rod-density thresholds. Below `AIRY` a closet reads as composed; above
  # `CROWDED` garments crush each other and nothing is visible at a glance.
  AIRY_PER_CATEGORY = 8
  CROWDED_PER_CATEGORY = 20

  # A garment worn at least this often earns prime reach — the band between
  # hip and shoulder that costs no bending or reaching.
  PRIME_REACH_WEARS = 6

  # Past three material tips the care register stops being a list of decisions
  # and becomes a laundry manual.
  MATERIAL_TIP_LIMIT = 3

  def initialize(user)
    @user = user
  end

  # All applicable tips, care first — a garment that needs washing cannot be
  # stored, and one that needs repair cannot be zoned.
  def tips
    REGISTERS.flat_map { |register| public_send(:"#{register}_tips") }
  end

  def grouped
    tips.group_by(&:register)
  end

  def summary
    {
      tips: tips.map(&:to_h),
      by_register: grouped.transform_values { |group| group.map(&:to_h) },
      source: "rules"
    }
  end

  # Memoised because breathe_tip consults it, and the condition tip costs a
  # query.
  def care_tips
    @care_tips ||= [
      tip(:clean_needed, :care, count_of(:clean_needed)),
      tip(:repair, :care, count_of(:repair)),
      tip(:tailor, :care, count_of(:tailor)),
      tip(:condition, :care, WardrobeItem.where(user: user).needs_attention.count),
      *material_care_tips
    ].compact
  end

  def storage_tips
    [
      tip(:seasonal_archive, :storage, active.count { |item| out_of_season?(item) }),
      tip(:fold, :storage, material_count(FOLD_MATERIALS)),
      tip(:hang, :storage, material_count(HANG_MATERIALS)),
      breathe_tip,
      tip(:archived_stale, :storage, count_of(:seasonal_archive))
    ].compact
  end

  def zoning_tips
    [
      tip(:prime_reach, :zoning, active.count { |item| item.times_worn.to_i >= PRIME_REACH_WEARS }),
      tip(:deep_storage, :zoning, active.count { |item| item.times_worn.to_i.zero? && item.spark_joy? }),
      category_zone_tip,
      color_run_tip
    ].compact
  end

  def restraint_tips
    [
      density_tip,
      duplicate_tip,
      one_in_one_out_tip,
      negative_space_tip
    ].compact
  end

  private

  attr_reader :user

  # `count` is both the evidence and the guard: a tip with nothing behind it is
  # never emitted. The callers whose trigger is a shape rather than a tally —
  # three categories present, four distinct colours — do their own guarding and
  # always pass a positive count.
  def tip(id, register, count, **interpolations)
    count = count.to_i
    return nil unless count.positive?

    scope = "closet.tips.#{id}"
    shared = { count: count, garments: garments(count), **interpolations }
    Tip.new(
      id: id,
      register: register,
      title: I18n.t("#{scope}.title", **shared),
      body: I18n.t("#{scope}.body", **shared),
      principle: I18n.t("#{scope}.principle"),
      count: count
    )
  end

  def garments(count) = I18n.t("closet.garments", count: count.to_i)

  def items = @items ||= user.items.to_a
  def active = @active ||= items.reject { |item| item.released? || item.in_declutter_box? }

  def count_of(state) = counts_by_state.fetch(state.to_s, 0)

  def counts_by_state
    @counts_by_state ||= items.group_by(&:lifecycle_state).transform_values(&:size)
  end

  def material_count(pattern) = active.count { |item| item.material.to_s.match?(pattern) }

  # "Condition twice a year, never seal in plastic" (care) and "cotton bags,
  # never plastic" (storage) are the same instruction twice, and on any wardrobe
  # with leather in it both fired. The care tip is the more complete of the two,
  # so it wins and this one stands down.
  def breathe_tip
    return nil if care_tips.any? { |tip| tip.id == :material_leather }

    tip(:breathe, :storage, material_count(BREATHE_MATERIALS))
  end

  def material_care_tips
    counts = Hash.new(0)
    active.each do |item|
      family = MATERIAL_FAMILIES.find { |_key, pattern| item.material.to_s.match?(pattern) }&.first
      counts[family] += 1 if family
    end

    counts.sort_by { |family, count| [ -count, family.to_s ] }.first(MATERIAL_TIP_LIMIT).filter_map do |family, count|
      tip(:"material_#{family}", :care, count, material: I18n.t("closet.materials.#{family}"))
    end
  end

  def out_of_season?(item)
    season = item.season.to_s
    season.present? && season != "All-Season" && season != item.current_season &&
      item.lifecycle_state != "seasonal_archive"
  end

  def category_zone_tip
    spread = active.group_by { |item| item.category.to_s }.reject { |category, _| category.empty? }
    return nil if spread.size < 3

    order = spread.sort_by { |_category, group| -group.size }.map(&:first)
    tip(:category_zones, :zoning, spread.size, zones: order.first(4).join(" → "))
  end

  def color_run_tip
    colors = active.filter_map { |item| item.color.presence }.reject { |color| color.start_with?("#") }
    return nil if colors.uniq.size < 4

    tip(:color_run, :zoning, colors.uniq.size)
  end

  def density_tip
    categories = active.group_by { |item| item.category.to_s }.reject { |category, _| category.empty? }
    crowded = categories.select { |_category, group| group.size > CROWDED_PER_CATEGORY }
    return nil if crowded.empty?

    tip(:density, :restraint, crowded.values.sum(&:size),
        categories: crowded.keys.to_sentence,
        verb: I18n.t("closet.is_are", count: crowded.size),
        crowded: CROWDED_PER_CATEGORY,
        airy: AIRY_PER_CATEGORY)
  end

  def duplicate_tip
    groups = DuplicateDetector.new(user).groups
    return nil if groups.blank?

    surplus = groups.sum { |group| Array(group).size - 1 }
    # The tip's own count is the surplus, so the group tally needs its own
    # pluralised phrase rather than riding on `count`.
    tip(:duplicates, :restraint, surplus, group_word: I18n.t("closet.groups", count: groups.size))
  rescue StandardError => e
    Rails.logger.warn("ClosetOrganization duplicate_tip: #{e.class}: #{e.message}")
    nil
  end

  def one_in_one_out_tip
    added = items.count { |item| item.created_at.present? && item.created_at > 90.days.ago }
    released = items.count { |item| item.released? || item.in_declutter_box? }
    return nil if added <= released

    tip(:one_in_one_out, :restraint, added - released, added: added, released: released)
  end

  def negative_space_tip
    return nil if active.size < 12

    total = active.size
    joy = active.count(&:spark_joy?)
    return nil if joy.zero? || joy > total * 0.75

    tip(:negative_space, :restraint, total - joy, joy: joy, total: total)
  end
end
