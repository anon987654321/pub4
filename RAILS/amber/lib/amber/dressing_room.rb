# frozen_string_literal: true

module Amber
  # Which garment categories hang on which part of the figure.
  #
  # Lives here rather than on OutfitsController because two surfaces need it now:
  # the signed-in dressing room, and the guest landing page, which shows the same
  # mannequin wearing the demo wardrobe. A controller reaching into another
  # controller for a constant is the shape that produces two copies of it later.
  module DressingRoom
    ZONES = {
      head: [ "Accessories" ],
      top: %w[Tops Outerwear],
      bottom: %w[Bottoms Dresses],
      shoes: [ "Shoes" ]
    }.freeze

    # What a guest sees when no demo wardrobe has been seeded: garment names real
    # enough to show what the feature does, per body region. The mannequin hides
    # the overlay of a garment with no photograph and still cycles its name, and
    # HomeLooks draws these as silhouettes, so a fresh install never shows an
    # empty page.
    FALLBACK = {
      headwear: [
        { title: "Gold hoop earrings", brand: "Mejuri", color: "gold" },
        { title: "Silk square scarf", brand: "H&M", color: "rust" },
        { title: "Oatmeal ribbed beanie", brand: "Arket", color: "oatmeal" },
        { title: "Cat-eye sunglasses", brand: "Ray-Ban", color: "tortoise" }
      ],
      tops: [
        { title: "Oatmeal cashmere crew", brand: "COS", color: "oatmeal" },
        { title: "Blush satin blouse", brand: "& Other Stories", color: "blush" },
        { title: "Striped Breton tee", brand: "Arket", color: "navy/white" },
        { title: "Navy oversized blazer", brand: "The Frankie Shop", color: "navy" }
      ],
      bottoms: [
        { title: "Charcoal wide-leg trousers", brand: "Arket", color: "charcoal" },
        { title: "Indigo straight-leg jeans", brand: "Everlane", color: "indigo" },
        { title: "Sage pleated midi skirt", brand: "Sézane", color: "sage" },
        { title: "Ivory silk slip dress", brand: "Reformation", color: "ivory" }
      ],
      shoes: [
        { title: "Black pointed-toe ankle boots", brand: "Vagabond", color: "black" },
        { title: "White leather trainers", brand: "Veja", color: "white" },
        { title: "Tan suede loafers", brand: "Ganni", color: "tan" },
        { title: "Block-heel pumps", brand: "Samsoe Samsoe", color: "nude" }
      ]
    }.freeze

    # The category each region stands for, so a fallback garment is drawn as what
    # it is (a scarf is an accessory, not a sweater).
    FALLBACK_CATEGORY = { headwear: "Accessories", tops: "Tops", bottoms: "Bottoms", shoes: "Shoes" }.freeze

    NO_PHOTOS = Object.new
    def NO_PHOTOS.attached? = false

    Placeholder = Struct.new(:id, :title, :color, keyword_init: true) do
      def photos = NO_PHOTOS
    end

    # FALLBACK names its regions after the body; the mannequin names its own
    # after the four overlay slots. Same four, different vocabulary.
    FALLBACK_ZONE = { head: :headwear, top: :tops, bottom: :bottoms, shoes: :shoes }.freeze

    module_function

    # ranker is optional: a guest has no taste history to rank by, so the demo
    # wardrobe comes back in whatever order the scope gives, which is stable.
    def zones_for(scope, ranker: nil)
      ZONES.transform_values do |categories|
        items = scope.where(category: categories)
        ranker ? ranker.rank(items) : items.to_a
      end
    end

    # The landing page's mannequin: the demo wardrobe when it is seeded, the
    # curated names when it is not, and never nothing.
    def guest_zones
      return zones_for(DemoWardrobe.items.with_photos_for_display) if DemoWardrobe.available?

      FALLBACK_ZONE.transform_values do |key|
        FALLBACK.fetch(key, []).each_with_index.map do |row, index|
          Placeholder.new(id: "#{key}-#{index}", title: row[:title], color: row[:color])
        end
      end
    end
  end
end
