# frozen_string_literal: true

class OutfitCompatibility
  OCCASION_WEIGHTS = {
    "work" => 0.72,
    "formal" => 0.85,
    "gym" => 0.18,
    "date" => 0.65,
    "travel" => 0.45,
    "casual" => 0.35
  }.freeze

  def initialize(user)
    @user = user
  end

  def score(outfit, occasion: nil, weather: nil)
    items = outfit.items.to_a
    return 0.0 if items.empty?

    scores = [ category_balance(items), color_balance(items), occasion_fit(items, occasion), weather_fit(items, weather), preference_fit(items) ]
    (scores.sum / scores.size).round(3)
  end

  def explain(outfit, occasion: nil, weather: nil)
    items = outfit.items.to_a
    {
      category_balance: category_balance(items),
      color_balance: color_balance(items),
      occasion_fit: occasion_fit(items, occasion),
      weather_fit: weather_fit(items, weather),
      preference_fit: preference_fit(items),
      overall: score(outfit, occasion:, weather:)
    }
  end

  private

  def category_balance(items)
    categories = items.map(&:category).compact
    required = %w[Tops Bottoms Shoes]
    coverage = required.count { |category| categories.include?(category) } / required.size.to_f
    [ coverage, 1.0 ].min
  end

  def color_balance(items)
    colors = items.map(&:color).compact_blank.map(&:downcase)
    return 0.5 if colors.empty?
    unique = colors.uniq.size
    return 0.9 if unique <= 3
    return 0.7 if unique == 4

    0.45
  end

  def occasion_fit(items, occasion)
    return 0.7 if occasion.blank?
    desired = OCCASION_WEIGHTS.fetch(occasion.to_s.downcase, 0.5)
    avg = items.sum { |item| GarmentTaxonomy.formality_score(item) } / items.size.to_f
    (1.0 - (desired - avg).abs).clamp(0.0, 1.0)
  end

  def weather_fit(items, weather)
    return 0.75 if weather.blank?
    weather = weather.to_s.downcase
    matches = items.count { |item| [ GarmentTaxonomy.weather_fit(item), "all_weather" ].include?(weather) || GarmentTaxonomy.weather_fit(item) == "all_weather" }
    [ matches / items.size.to_f, 1.0 ].min
  end

  def preference_fit(items)
    preferences = @user.style_preferences.to_a
    return 0.7 if preferences.empty?

    text = items.map(&:embedding_text).join(" ").downcase
    total_weight = preferences.sum { |preference| preference.weight.to_f.abs }
    return 0.7 if total_weight.zero?

    score = preferences.sum do |preference|
      text.include?(preference.name.to_s.downcase) ? preference.weight.to_f : 0
    end

    ((score / total_weight) + 0.5).clamp(0.0, 1.0)
  end
end
