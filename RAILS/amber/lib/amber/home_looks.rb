# frozen_string_literal: true

module Amber
  # The four looks on the home page: each an outfit, its garments drawn as
  # silhouettes and laid on the figure where they are worn.
  #
  # A signed-in reader's own outfits come first, then the demo wardrobe's, then
  # looks put together from DressingRoom::FALLBACK, so the page shows four
  # outfits on a box where nothing was ever seeded. Garments are drawn from
  # their title and colour rather than from stored photographs for the same
  # reason, and so a look costs no image request.
  module HomeLooks
    COUNT = 4

    Garment = Data.define(:title, :color, :category, :zone)
    Look = Data.define(:name, :garments)

    # Where on the figure a shape is worn. The stylesheet places each zone in
    # the figure's own proportions (.look-zone--<zone>).
    ZONE_BY_SHAPE = {
      beanie: :crown, sunglasses: :eyes, earrings: :ears, bag: :hand,
      boots: :feet, trainers: :feet,
      trousers: :legs, jeans: :legs, shorts: :legs, skirt: :legs,
      dress: :dress, shirtdress: :dress,
      coat: :torso, blazer: :torso, sweater: :torso, blouse: :torso, tee: :torso
    }.freeze

    # Painted first to last, so a coat lies over the trousers and the
    # sunglasses over the hat.
    LAYER_ORDER = %i[legs feet dress torso hand crown ears eyes].freeze

    module_function

    def looks_for(user = nil)
      looks = outfit_looks(user&.outfits) + outfit_looks(demo_outfits) + fallback_looks
      looks.first(COUNT)
    end

    def outfit_looks(scope)
      return [] unless scope

      scope.includes(:items).limit(COUNT).filter_map do |outfit|
        garments = outfit.items.map { |item| garment(item.title, item.color, item.category) }
        Look.new(name: outfit.name, garments: layered(garments)) if garments.any?
      end
    end

    def demo_outfits
      DemoWardrobe.user && DemoWardrobe.outfits
    end

    # Look n wears the n-th garment of each body region.
    def fallback_looks
      Array.new(COUNT) do |index|
        garments = DressingRoom::FALLBACK.filter_map do |key, rows|
          row = rows[index]
          garment(row[:title], row[:color], DressingRoom::FALLBACK_CATEGORY.fetch(key)) if row
        end
        Look.new(name: nil, garments: layered(garments))
      end
    end

    def garment(title, color, category)
      shape = GarmentSilhouette.shape_for(title: title, category: category)
      Garment.new(title: title, color: color, category: category, zone: ZONE_BY_SHAPE.fetch(shape, :torso))
    end

    def layered(garments)
      garments.sort_by { |garment| LAYER_ORDER.index(garment.zone) }
    end
  end
end
