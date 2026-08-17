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

    # What a guest sees when no demo wardrobe has been seeded. The garment names
    # are real enough to show what the feature does, and the mannequin's own
    # controller already handles a garment with no photograph — it hides the
    # overlay and still cycles the name, the count and the reason.
    #
    # This existed before as WardrobeShowcase::FALLBACK, and it is the reason a
    # fresh install never showed an empty landing page. Keeping that property is
    # the point of reaching for it here.
    NO_PHOTOS = Object.new
    def NO_PHOTOS.attached? = false

    Placeholder = Struct.new(:id, :title, :color, keyword_init: true) do
      def photos = NO_PHOTOS
    end

    # WardrobeShowcase names its zones after body regions; the mannequin names
    # its own after the four overlay slots. Same four, different vocabulary.
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
        WardrobeShowcase::FALLBACK.fetch(key, []).each_with_index.map do |row, index|
          Placeholder.new(id: "#{key}-#{index}", title: row[:title], color: row[:color])
        end
      end
    end
  end
end
