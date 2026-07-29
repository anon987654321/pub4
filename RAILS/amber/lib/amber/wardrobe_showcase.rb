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
        { title: "Cat-eye sunglasses", brand: "Ray-Ban", color: "tortoise" },
      ],
      tops: [
        { title: "Oatmeal cashmere crew", brand: "COS", color: "oatmeal" },
        { title: "Blush satin blouse", brand: "& Other Stories", color: "blush" },
        { title: "Striped Breton tee", brand: "Arket", color: "navy/white" },
        { title: "Navy oversized blazer", brand: "The Frankie Shop", color: "navy" },
      ],
      bottoms: [
        { title: "Charcoal wide-leg trousers", brand: "Arket", color: "charcoal" },
        { title: "Indigo straight-leg jeans", brand: "Everlane", color: "indigo" },
        { title: "Sage pleated midi skirt", brand: "Sézane", color: "sage" },
        { title: "Ivory silk slip dress", brand: "Reformation", color: "ivory" },
      ],
      shoes: [
        { title: "Black pointed-toe ankle boots", brand: "Vagabond", color: "black" },
        { title: "White leather trainers", brand: "Veja", color: "white" },
        { title: "Tan suede loafers", brand: "Ganni", color: "tan" },
        { title: "Block-heel pumps", brand: "Samsoe Samsoe", color: "nude" },
      ],
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

      def carousel_options(reverse:)
        {
          slidesPerView: "auto",
          spaceBetween: 10,
          loop: true,
          speed: 9_000,
          grabCursor: true,
          allowTouchMove: true,
          autoplay: {
            delay: 0,
            disableOnInteraction: false,
            reverseDirection: reverse,
            pauseOnMouseEnter: true,
          },
        }
      end

      private

      def items_for(key, categories, filter: nil)
        if DemoWardrobe.available?
          # with_attached_photos, as DemoWardrobeController already does. The
          # slide partial asks every item for photos.attached? and photos.first,
          # so without the preload each of the four zones re-queried the
          # attachment and blob for every slide it rendered. The guest home page
          # was issuing 191 queries and spending 6s in views, and on a one-vCPU
          # box that is long enough for Falcon's container to judge the child
          # blocked and SIGKILL it -- the page returned 200 in 10s and the
          # worker died immediately after, so the site kept going down.
          # variant_records as well as the blob. with_attached_photos is only
          # includes(photos_attachments: :blob), and the slide partial renders
          # each photo through responsive_image_tag at two widths in two formats
          # -- four variant lookups per image, none of them covered by that
          # preload. With the images finally attaching, the page went to 544
          # queries; the blob preload alone does not reach them.
          DemoWardrobe.items
                      .includes(photos_attachments: { blob: :variant_records })
                      .select do |item|
            categories.include?(item.category) && zone_match?(item, filter)
          end
        else
          FALLBACK[key].map { |row| SlideItem.new(**row, category: categories.first) }
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
