# frozen_string_literal: true

class OutfitGeneration
  def initialize(user)
    @user = user
  end

  def generate!(weather: nil, season: nil, occasion: nil)
    candidates = scoped_items(season:, occasion:)
    grouped = candidates.group_by(&:category)
    picks = [
      least_worn(grouped["Tops"]) || grouped["Dresses"]&.first,
      least_worn(grouped["Bottoms"]),
      grouped["Shoes"]&.first,
      layer_for(weather, grouped)
    ].compact.uniq.first(4)
    return nil if picks.empty?

    outfit = user.outfits.create!(
      name: [ weather, season, occasion, "Generated outfit" ].compact_blank.join(" / "),
      season: season,
      occasion: occasion,
      description: "Generated from weather, season, occasion, and underused wardrobe signals."
    )
    picks.each_with_index { |item, index| outfit.outfit_items.create!(item: item, position: index) }
    user.recommendations.create!(
      kind: "outfit",
      outfit: outfit,
      reason: "Outfit generated for #{[ weather, season, occasion ].compact_blank.join(', ')}",
      score: picks.sum { |item| item.underused? ? 1.0 : 0.5 },
      metadata: { weather: weather, season: season, occasion: occasion, item_ids: picks.map(&:id) }
    )
    outfit
  end

  private

  attr_reader :user

  def scoped_items(season:, occasion:)
    # in_rotation, not active_wardrobe — a generated outfit should not reach
    # into the declutter box for a garment you have already decided about.
    scope = user.items.in_rotation
    scope = scope.where(season: [ season, "All-Season", nil, "" ]) if season.present?
    scope = scope.by_occasion(occasion) if occasion.present?
    scope.order(times_worn: :asc, updated_at: :asc).limit(50).to_a
  end

  def layer_for(weather, grouped)
    return unless weather.to_s.match?(/cold|rain|snow|wind/i)

    grouped["Outerwear"]&.first
  end

  def least_worn(items)
    items&.min_by { |item| item.times_worn.to_i }
  end
end
