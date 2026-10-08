# frozen_string_literal: true

class DeclutterScore
  def initialize(item)
    @item = item
  end

  def score
    {
      joy: joy_score,
      utility: utility_score,
      fit: fit_score,
      duplicate_pressure: duplicate_pressure,
      cost_pressure: cost_pressure,
      repair_pressure: repair_pressure,
      total_release_score: total_release_score.round(3),
      quadrant: quadrant,
      recommendation: recommendation
    }
  end

  def recommendation
    return "keep" if high_joy? && high_utility?
    return "sentimental_archive" if sentimental_signal? && !high_utility?
    return "wear_this_week" if high_joy? && !high_utility?
    return "replace_gradually" if !high_joy? && high_utility?
    return "repair" if repair_pressure > 0.65
    return "sell" if resale_candidate?
    return "donate" if donation_candidate?

    "declutter_box"
  end

  private

  def joy_score
    return 1.0 if @item.spark_joy == true
    return 0.15 if @item.spark_joy == false

    case @item.life_phase
    when "current" then 0.65
    when "aspirational" then 0.45
    when "past-self" then 0.25
    else 0.5
    end
  end

  def utility_score
    wears = @item.times_worn.to_i
    recent_bonus = @item.respond_to?(:last_worn_on) && @item.last_worn_on.present? && @item.last_worn_on > 90.days.ago.to_date ? 0.25 : 0
    ([ wears / 20.0, 0.75 ].min + recent_bonus).clamp(0.0, 1.0)
  end

  def fit_score
    review = @item.declutter_review
    return 0.2 if review&.reason_kept == "uncomfortable"
    return 0.35 if @item.life_phase == "past-self"

    0.75
  end

  def duplicate_pressure
    similar = @item.user.items.active_wardrobe.where.not(id: @item.id).select { |candidate| candidate.duplicate_key == @item.duplicate_key }
    [ similar.size / 4.0, 1.0 ].min
  end

  def cost_pressure
    return 0.0 unless @item.price_cents.present?
    return 0.8 if @item.times_worn.to_i.zero? && @item.price_cents > 50_000
    return 0.5 if @item.cost_per_wear.to_f > 250

    0.1
  end

  def repair_pressure
    return 0.0 unless @item.lifecycle_state.in?(%w[repair clean_needed tailor])
    estimate = @item.sustainability_metric&.repair_cost_estimate.to_f
    price = @item.price_cents.to_i / 100.0
    return 0.5 if price.zero?

    [ estimate / price, 1.0 ].min
  end

  def total_release_score
    (1.0 - joy_score) * 0.28 +
      (1.0 - utility_score) * 0.28 +
      (1.0 - fit_score) * 0.14 +
      duplicate_pressure * 0.14 +
      cost_pressure * 0.08 +
      repair_pressure * 0.08
  end

  def quadrant
    return "high_joy_high_use" if high_joy? && high_utility?
    return "high_joy_low_use" if high_joy? && !high_utility?
    return "low_joy_high_use" if !high_joy? && high_utility?

    "low_joy_low_use"
  end

  def high_joy? = joy_score >= 0.6
  def high_utility? = utility_score >= 0.45

  def sentimental_signal?
    @item.declutter_review&.reason_kept.in?(%w[memory gift rare]) || @item.life_phase == "past-self"
  end

  def resale_candidate?
    @item.price_cents.to_i >= 30_000 && @item.photos.attached? && total_release_score > 0.45
  end

  def donation_candidate?
    total_release_score > 0.55 && !resale_candidate?
  end
end
