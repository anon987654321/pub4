# frozen_string_literal: true

class GarmentTaxonomy
  CATEGORY_ALIASES = {
    "top" => "Tops",
    "shirt" => "Tops",
    "tee" => "Tops",
    "t-shirt" => "Tops",
    "pants" => "Bottoms",
    "trousers" => "Bottoms",
    "jeans" => "Bottoms",
    "skirt" => "Bottoms",
    "dress" => "Dresses",
    "shoe" => "Shoes",
    "sneaker" => "Shoes",
    "boot" => "Shoes",
    "jacket" => "Outerwear",
    "coat" => "Outerwear",
    "accessory" => "Accessories",
    "bag" => "Accessories",
  }.freeze

  WEATHER_BY_MATERIAL = {
    /wool|cashmere|alpaca/i => "cold",
    /linen|hemp/i => "warm",
    /cotton/i => "mild",
    /leather|suede/i => "dry",
    /nylon|polyester|shell/i => "rain",
  }.freeze

  FORMALITY_BY_CATEGORY = {
    "Dresses" => 0.65,
    "Outerwear" => 0.45,
    "Shoes" => 0.5,
    "Accessories" => 0.35,
    "Tops" => 0.4,
    "Bottoms" => 0.4,
  }.freeze

  def self.normalize_category(value)
    raw = value.to_s.strip
    Item::CATEGORIES.find { |category| category.casecmp?(raw) } || CATEGORY_ALIASES.fetch(raw.downcase, raw.presence || "Accessories")
  end

  def self.weather_fit(item)
    material = item.material.to_s
    match = WEATHER_BY_MATERIAL.find { |pattern, _fit| material.match?(pattern) }
    match&.last || "all_weather"
  end

  def self.formality_score(item)
    base = FORMALITY_BY_CATEGORY.fetch(item.category, 0.4)
    modifiers = [ item.brand, item.material, item.occasion_tags ].join(" ")
    base += 0.2 if modifiers.match?(/silk|wool|tailored|formal|wedding|office/i)
    base -= 0.15 if modifiers.match?(/gym|sweat|jersey|beach/i)
    base.clamp(0.0, 1.0).round(2)
  end

  def self.semantic_tags(item)
    [
      item.category,
      item.color,
      item.material,
      item.brand,
      weather_fit(item),
      "formality:#{formality_score(item)}",
      *item.occasions
    ].compact.map(&:to_s).reject(&:blank?).uniq
  end
end
