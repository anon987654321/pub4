class WardrobeGapService
  ESSENTIALS = {
    "Tops" => 5,
    "Bottoms" => 3,
    "Shoes" => 2,
    "Outerwear" => 1,
    "Accessories" => 2
  }.freeze

  CONNECTORS = [
    { name: "neutral top", category: "Tops", colors: %w[white black navy grey beige] },
    { name: "dark bottom", category: "Bottoms", colors: %w[black navy denim charcoal] },
    { name: "weather layer", category: "Outerwear", colors: %w[black navy beige olive] },
    { name: "versatile shoe", category: "Shoes", colors: %w[black white brown] }
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
        reason: "A resilient wardrobe usually needs at least #{minimum} #{category.downcase}."
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
        name: connector[:name],
        reason: "Missing #{connector[:name]} for easier outfit combinations."
      }
    end
  end
end
