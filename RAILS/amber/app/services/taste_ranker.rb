# frozen_string_literal: true

# Ranks garments by how much this wardrobe's owner actually likes them.
#
# The original Amber specification asked for Mix & Match carousels "influenced
# by its ever-evolving knowledge of your taste and preference". Two things make
# that knowledge evolve, and this service reads both:
#
#   Declared taste  — `StylePreference` rows the owner (or the style profile
#                     form) wrote. `kind: :avoid` counts against a garment no
#                     matter which sign its weight carries.
#   Revealed taste  — joy flag, wear count, wear recency, life phase. What
#                     someone reaches for is a stronger signal than what they
#                     say, so behaviour carries more of the score than words.
#
# Scores are 0.0–1.0 and explainable: `explain` returns the reasons that moved
# a garment, which is what the dressing room shows under each zone.
class TasteRanker
  # Weights sum to 1.0. Behaviour (joy + wear + recency) is 0.62 of the score;
  # declared preferences are 0.24; life phase is 0.14.
  WEIGHTS = {
    joy: 0.24,
    wear: 0.20,
    recency: 0.18,
    declared: 0.24,
    phase: 0.14,
  }.freeze

  # A garment worn this often is "fully" established in the rotation. Above it
  # the wear term saturates, so a single much-worn favourite cannot flatten the
  # whole carousel.
  WEAR_SATURATION = 12

  # Wear recency decays to zero over this window.
  RECENCY_WINDOW_DAYS = 120

  # Inside this window `explain` calls a garment recently worn. It is a
  # reporting threshold only — the score itself decays continuously across
  # RECENCY_WINDOW_DAYS.
  RECENT_WEAR_DAYS = 21

  PHASE_SCORES = {
    "current" => 1.0,
    "aspirational" => 0.6,
    "past-self" => 0.15,
  }.freeze

  def initialize(user)
    @user = user
  end

  # Sorted best-first. Ties break on id so the order is stable between requests
  # — a carousel that reshuffles on every page load is not a preference model.
  def rank(items)
    items.to_a.sort_by { |item| [ -score_for(item), item.id ] }
  end

  def score_for(item)
    (
      WEIGHTS[:joy] * joy_term(item) +
      WEIGHTS[:wear] * wear_term(item) +
      WEIGHTS[:recency] * recency_term(item) +
      WEIGHTS[:declared] * declared_term(item) +
      WEIGHTS[:phase] * phase_term(item)
    ).clamp(0.0, 1.0).round(4)
  end

  # Why this garment ranks where it does, in the reader's language — these
  # strings land beside translated chrome in the dressing room and on the
  # dashboard, and used to be the only English on a Norwegian page.
  def explain(item)
    [
      (t("joy") if item.spark_joy?),
      (t("worn", count: item.times_worn.to_i) if item.times_worn.to_i.positive?),
      (t("recent") if days_since_worn(item)&.<(RECENT_WEAR_DAYS)),
      declared_reason(item),
      (t("aspirational") if item.life_phase == "aspirational"),
      (t("past_self") if item.life_phase == "past-self")
    ].compact
  end

  private

  attr_reader :user

  def joy_term(item)
    return 1.0 if item.spark_joy?
    # nil means never judged, which is not the same as judged and rejected.
    item.spark_joy.nil? ? 0.5 : 0.0
  end

  def wear_term(item)
    [ item.times_worn.to_i / WEAR_SATURATION.to_f, 1.0 ].min
  end

  def recency_term(item)
    days = days_since_worn(item)
    return 0.35 if days.nil? # never worn: neutral-low, not disqualifying

    ((RECENCY_WINDOW_DAYS - days) / RECENCY_WINDOW_DAYS.to_f).clamp(0.0, 1.0)
  end

  # 0.5 is the no-information midpoint so a wardrobe with no declared
  # preferences ranks purely on behaviour rather than being pushed to zero.
  def declared_term(item)
    return 0.5 if preferences.empty?

    text = item.embedding_text.to_s.downcase
    hits = preferences.select { |preference| text.include?(preference.name.to_s.downcase) }
    return 0.5 if hits.empty?

    total = hits.sum { |preference| signed_weight(preference).abs }
    return 0.5 if total.zero?

    signed = hits.sum { |preference| signed_weight(preference) }
    (0.5 + (signed / total / 2.0)).clamp(0.0, 1.0)
  end

  def phase_term(item)
    PHASE_SCORES.fetch(item.life_phase.to_s, 0.7)
  end

  def declared_reason(item)
    return nil if preferences.empty?

    text = item.embedding_text.to_s.downcase
    hit = preferences.find { |preference| text.include?(preference.name.to_s.downcase) }
    return nil unless hit

    t(hit.avoid? ? "avoids" : "matches", name: hit.name)
  end

  def t(key, **interpolations) = I18n.t("taste.#{key}", **interpolations)

  # `avoid` is a negative preference regardless of how its weight was stored —
  # the style profile form writes positive weights for every kind.
  def signed_weight(preference)
    magnitude = preference.weight.to_f.abs
    preference.avoid? ? -magnitude : magnitude
  end

  def days_since_worn(item)
    date = item.last_worn_on
    return nil if date.blank?

    (Date.current - date.to_date).to_i.clamp(0, RECENCY_WINDOW_DAYS)
  end

  def preferences
    @preferences ||= user.style_preferences.to_a
  end
end
