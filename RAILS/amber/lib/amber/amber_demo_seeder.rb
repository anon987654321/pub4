# frozen_string_literal: true

require "stringio"

module Amber
  # Credible female capsule wardrobe demo — safe to run idempotently on production.
  class AmberDemoSeeder
    ITEMS = [
      { title: "Ivory silk slip dress", image: "amber-ivory-silk-dress", category: "Dresses", color: "ivory", brand: "Reformation", size: "S",
        price_cents: 18_900, times_worn: 14, season: "Summer", occasion: "date", spark_joy: true,
        material: "silk" },
      { title: "Camel wool wrap coat", image: "amber-camel-wrap-coat", category: "Outerwear", color: "camel", brand: "Totême", size: "M",
        price_cents: 42_900, times_worn: 38, season: "Winter", occasion: "work", spark_joy: true,
        material: "wool" },
      { title: "Black pointed-toe ankle boots", image: "amber-black-ankle-boots", category: "Shoes", color: "black", brand: "Vagabond", size: "38",
        price_cents: 16_500, times_worn: 52, season: "All-Season", occasion: "work", spark_joy: true,
        material: "leather" },
      { title: "Oatmeal cashmere crew neck", image: "amber-oatmeal-cashmere", category: "Tops", color: "oatmeal", brand: "COS", size: "S",
        price_cents: 12_900, times_worn: 31, season: "Autumn", occasion: "casual", spark_joy: true,
        material: "cashmere" },
      { title: "Charcoal wide-leg trousers", image: "amber-charcoal-trousers", category: "Bottoms", color: "charcoal", brand: "Arket", size: "S",
        price_cents: 9_900, times_worn: 27, season: "All-Season", occasion: "work", spark_joy: true,
        material: "wool" },
      { title: "Navy oversized blazer", image: "amber-navy-blazer", category: "Outerwear", color: "navy", brand: "The Frankie Shop", size: "M",
        price_cents: 14_900, times_worn: 19, season: "Spring", occasion: "work", spark_joy: true,
        material: "linen" },
      { title: "Sage pleated midi skirt", image: "amber-sage-midi-skirt", category: "Bottoms", color: "sage", brand: "Sézane", size: "S",
        price_cents: 8_500, times_worn: 11, season: "Spring", occasion: "casual", spark_joy: true,
        material: "cotton" },
      { title: "Tan structured crossbody", image: "amber-tan-crossbody", category: "Accessories", color: "tan", brand: "Staud", size: "onesize",
        price_cents: 7_900, times_worn: 64, season: "All-Season", occasion: "travel", spark_joy: true,
        material: "leather" },
      { title: "Blush satin blouse", image: "amber-blush-satin-blouse", category: "Tops", color: "blush", brand: "& Other Stories", size: "S",
        price_cents: 5_900, times_worn: 9, season: "Spring", occasion: "formal", spark_joy: true,
        material: "satin" },
      { title: "Indigo straight-leg jeans", image: "amber-indigo-jeans", category: "Bottoms", color: "indigo", brand: "Everlane", size: "28",
        price_cents: 9_500, times_worn: 44, season: "All-Season", occasion: "casual", spark_joy: true,
        material: "denim" },
      { title: "Gold hoop earrings", image: "amber-gold-hoops", category: "Accessories", color: "gold", brand: "Mejuri", size: "onesize",
        price_cents: 3_200, times_worn: 72, season: "All-Season", occasion: "date", spark_joy: true,
        material: "gold" },
      { title: "Rust linen shirtdress", image: "amber-rust-shirtdress", category: "Dresses", color: "rust", brand: "Faithfull the Brand", size: "S",
        price_cents: 11_900, times_worn: 5, season: "Summer", occasion: "travel", spark_joy: false,
        material: "linen" },
      { title: "Oatmeal ribbed beanie", image: "amber-oatmeal-beanie", category: "Accessories", color: "oatmeal", brand: "Arket", size: "onesize",
        price_cents: 2_900, times_worn: 18, season: "Winter", occasion: "casual", spark_joy: true,
        material: "wool" },
      { title: "Cat-eye sunglasses", image: "amber-cateye-sunglasses", category: "Accessories", color: "tortoise", brand: "Ray-Ban", size: "onesize",
        price_cents: 15_900, times_worn: 41, season: "Summer", occasion: "travel", spark_joy: true,
        material: "acetate" },
      { title: "Striped Breton tee", image: "amber-breton-tee", category: "Tops", color: "navy/white", brand: "Arket", size: "S",
        price_cents: 3_500, times_worn: 14, season: "Summer", occasion: "casual", spark_joy: true,
        material: "cotton" },
      { title: "White leather trainers", image: "amber-white-trainers", category: "Shoes", color: "white", brand: "Veja", size: "38",
        price_cents: 12_900, times_worn: 55, season: "All-Season", occasion: "casual", spark_joy: true,
        material: "leather" },
      { title: "Sage linen shorts", image: "amber-sage-shorts", category: "Bottoms", color: "sage", brand: "COS", size: "S",
        price_cents: 6_900, times_worn: 8, season: "Summer", occasion: "casual", spark_joy: true,
        material: "linen" }
    ].freeze

    OUTFITS = [
      { name: "Gallery opening", occasion: "formal", season: "Spring",
        items: [ "Blush satin blouse", "Charcoal wide-leg trousers", "Black pointed-toe ankle boots", "Gold hoop earrings" ] },
      { name: "Coffee date", occasion: "casual", season: "Autumn",
        items: [ "Oatmeal cashmere crew neck", "Indigo straight-leg jeans", "Tan structured crossbody" ] },
      { name: "Office chic", occasion: "work", season: "Winter",
        items: [ "Navy oversized blazer", "Charcoal wide-leg trousers", "Black pointed-toe ankle boots", "Camel wool wrap coat" ] }
    ].freeze

    def initialize(attach_media: !Shared::DemoMedia.skip_attach?)
      @attach_media = attach_media
    end

    def seed!
      demo = ensure_demo_user!
      items_by_title = seed_items!(demo)
      seed_outfits!(demo, items_by_title)
    end

    private

    attr_reader :attach_media

    def ensure_demo_user!
      user = User.strict_loading(false).find_or_create_by!(email_address: DemoWardrobe::DEMO_EMAIL) do |u|
        u.password = u.password_confirmation = "password123"
      end
      profile = user.profile || user.create_profile!
      profile.update!(display_name: DemoWardrobe::DEMO_DISPLAY_NAME) if profile.display_name.blank?
      user
    end

    def seed_items!(user)
      ITEMS.each_with_object({}) do |row, index|
        item = user.items.find_or_initialize_by(title: row[:title])
        item.assign_attributes(
          category: row[:category],
          color: row[:color],
          brand: row[:brand],
          size: row[:size],
          material: row[:material],
          price_cents: row[:price_cents],
          times_worn: row[:times_worn],
          season: row[:season],
          occasion_tags: row[:occasion],
          spark_joy: row[:spark_joy],
          lifecycle_state: "active",
          purchase_date: rand(180..900).days.ago.to_date,
          last_worn_on: rand(1..21).days.ago.to_date
        )
        item.save!
        attach_photo!(item, row) if attach_media && row[:image]
        index[row[:title]] = item
      end
    end

    # A drawn cut-out first, a photograph only if this box cannot rasterise one.
    #
    # The photographs came from picsum keyed by the garment's name, which is a
    # random landscape: the mannequin on the landing page wore a doorway, a
    # street scene and a beach, because the zone overlays are object-fit boxes
    # over the figure and a photograph fills them edge to edge.
    def attach_photo!(item, row)
      png = GarmentSilhouette.png(title: row[:title], color: row[:color], category: row[:category])
      if png.nil?
        return true if item.photos.attached?

        return Shared::DemoMedia.attach_remote_postpro!(
          item, :photos, seed: row[:image], preset: "portrait", width: 720, height: 960
        )
      end
      return true if silhouette_attached?(item)

      # Replaces rather than skips: every demo item already wears a picsum
      # photograph, and leaving it there is the bug. Scoped to the demo user's
      # own wardrobe, which nobody else edits.
      item.photos.purge
      item.photos.attach(io: StringIO.new(png), filename: "#{row[:image]}.png", content_type: "image/png")
      true
    end

    def silhouette_attached?(item)
      item.photos.attached? && item.photos.any? { |photo| photo.blob.content_type == "image/png" }
    end

    def seed_outfits!(user, items_by_title)
      OUTFITS.each do |row|
        outfit = user.outfits.find_or_initialize_by(name: row[:name])
        outfit.assign_attributes(
          occasion: row[:occasion],
          season: row[:season],
          description: "Demo capsule look — browse only until you sign in."
        )
        outfit.save!

        row[:items].each do |title|
          item = items_by_title[title]
          next unless item

          outfit.outfit_items.find_or_create_by!(item: item)
        end
      end
    end
  end
end
