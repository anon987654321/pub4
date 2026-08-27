# frozen_string_literal: true

module Amber
  # Guest landing carousels — body zones with demo wardrobe items.
  class WardrobeShowcase
    SlideItem = Struct.new(:title, :brand, :color, :category, keyword_init: true)

    Zone = Data.define(:key, :label, :hint, :items, :reverse)

    HEADWEAR_PATTERN = /beanie|scarf|earring|sunglass|hat|cap|headband|barrette|clip|hoop/i.freeze
    OUTERWEAR_EXCLUDE_PATTERN = /coat|shell|parka|trench|wrap coat/i.freeze

    ZONES = [
      { key: :headwear, label: "Headwear", hint: "Hats, scarves & jewelry",
        categories: %w[Accessories], reverse: false, filter: :headwear },
      { key: :tops, label: "Tops & layers", hint: "Sweaters, tees & shirts",
        categories: %w[Tops Outerwear], reverse: true, filter: :layers },
      { key: :bottoms, label: "Bottoms", hint: "Pants, skirts & shorts",
        categories: %w[Bottoms], reverse: false },
      { key: :shoes, label: "Shoes", hint: "Boots, flats & trainers",
        categories: %w[Shoes], reverse: true }
    ].freeze

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

    class << self
      def rows
        ZONES.map do |meta|
          items = items_for(meta[:key], meta[:categories], filter: meta[:filter])
          Zone.new(
            key: meta[:key],
            label: meta[:label],
            hint: meta[:hint],
            items: loop_slides(items),
            reverse: meta[:reverse]
          )
        end
      end

      # One garment at a time, per operator instruction 2026-08-11.
      #
      # slidesPerView: "auto" sizes each slide from its own CSS, and the slide
      # card is 4.5rem wide, so a viewport fits a dozen at once and the row read
      # as a filmstrip rather than a carousel. The width lives in
      # _guest_showcase.scss and the count lives here; changing only the CSS
      # would leave "auto" still deciding, and changing only this would leave a
      # 4.5rem card centred in an empty row. Both move together.
      #
      # speed drops with the count. 9000 ms was a continuous crawl for a
      # marquee of many small slides; the same speed on a single full-width
      # slide is one garment sliding for nine seconds. A discrete step with a
      # pause between reads as a carousel.
      def carousel_options(reverse:)
        {
          slidesPerView: 1,
          spaceBetween: 0,
          loop: true,
          speed: 700,
          grabCursor: true,
          allowTouchMove: true,
          autoplay: {
            delay: 3_600,
            disableOnInteraction: false,
            reverseDirection: reverse,
            pauseOnMouseEnter: true
          }
        }
      end

      private

      def items_for(key, categories, filter: nil)
        unless DemoWardrobe.available?
          return FALLBACK[key].map { |row| SlideItem.new(**row, category: categories.first) }
        end

        # with_photos_for_display preloads attachments, blobs and variant_records,
        # and the slide partial asks for the named :thumb variants WardrobeMediaJob
        # preprocesses. Inventing multi-width webp variants in the partial costs N
        # cold lookups per image.
        DemoWardrobe.items
                    .with_photos_for_display
                    .select do |item|
          categories.include?(item.category) && zone_match?(item, filter)
        end
      end

      def zone_match?(item, filter)
        title = item.title.to_s
        case filter
        when :headwear then title.match?(HEADWEAR_PATTERN)
        when :layers then item.category == "Tops" || !title.match?(OUTERWEAR_EXCLUDE_PATTERN)
        else true
        end
      end

      def loop_slides(items)
        list = items.to_a
        return list if list.empty?
        return list if list.size >= 8

        (list * ((8.0 / list.size).ceil)).first(12)
      end
    end
  end
end
