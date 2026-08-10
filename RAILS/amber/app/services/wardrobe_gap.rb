# frozen_string_literal: true

class WardrobeGap
  ESSENTIALS = {
    "Tops" => 5,
    "Bottoms" => 3,
    "Shoes" => 2,
    "Outerwear" => 1,
    "Accessories" => 2
  }.freeze

  # `key` names the locale entry under `gaps.connectors`; the display name is
  # translated rather than baked in, because these reasons render beside
  # translated chrome on the Shop smarter page.
  CONNECTORS = [
    { key: :neutral_top, category: "Tops", colors: %w[white black navy grey beige] },
    { key: :dark_bottom, category: "Bottoms", colors: %w[black navy denim charcoal] },
    { key: :weather_layer, category: "Outerwear", colors: %w[black navy beige olive] },
    { key: :versatile_shoe, category: "Shoes", colors: %w[black white brown] }
  ].freeze

  def initialize(user)
    @user = user
  end

  def gaps
    ESSENTIALS.filter_map do |category, minimum|
      count = @user.items.by_category(category).count
      next if count >= minimum

      {
        kind: "category_minimum",
        category: category,
        owned: count,
        target: minimum,
        missing: minimum - count,
        reason: I18n.t("gaps.category_minimum", count: minimum, category: category.downcase)
      }
    end + connector_gaps
  end

  def create_recommendations!
    gaps.each do |gap|
      @user.recommendations.find_or_create_by!(kind: "purchase_gap", reason: gap[:reason]) do |recommendation|
        recommendation.score = gap.fetch(:missing, 1).to_f
        recommendation.metadata = gap
      end
    end
  end

  private

  def connector_gaps
    CONNECTORS.filter_map do |connector|
      exists = @user.items.by_category(connector[:category]).any? do |item|
        connector[:colors].include?(item.color.to_s.downcase)
      end
      next if exists

      {
        kind: "connector",
        category: connector[:category],
        name: I18n.t("gaps.connectors.#{connector[:key]}"),
        reason: I18n.t("gaps.connector", name: I18n.t("gaps.connectors.#{connector[:key]}"))
      }
    end
  end
end
