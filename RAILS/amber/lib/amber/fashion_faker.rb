# frozen_string_literal: true

require "faker"

module Amber
  # Realistic female fashion copy for dev/test seeds — not generic Commerce.product_name.
  class FashionFaker
    BRANDS = %w[
      &\ Other\ Stories Reformation Sézane Ganni COS Arket Totême Staud Nanushka
      Zimmermann Mango Zara H&M Everlane Aritzia Veja Samsoe\ Samsoe Rouje
      Faithfull\ the\ Brand Baum\ und\ Pferdgarten The\ Frankie\ Shop
    ].freeze

    MATERIALS = %w[
      linen silk cotton wool cashmere denim leather viscose satin knit suede
      merino tweed crepe jersey corduroy chiffon
    ].freeze

    COLORS = %w[
      ivory blush sage terracotta camel charcoal navy burgundy rose gold black
      cream oatmeal rust indigo sand mauve espresso pearl
    ].freeze

    PIECES = {
      "Tops" => [
        "silk camisole", "cashmere turtleneck", "linen button-down", "ribbed tank",
        "oversized poplin shirt", "fine-knit polo", "cropped cardigan", "satin blouse",
        "merino crew neck", "lace-trim tee", "halter knit top", "wrap blouse"
      ],
      "Bottoms" => [
        "high-waist wide-leg trousers", "pleated midi skirt", "straight-leg jeans",
        "tailored culottes", "satin midi skirt", "wool pencil skirt", "linen shorts",
        "cargo trousers", "leather mini skirt", "cropped flares"
      ],
      "Dresses" => [
        "silk slip dress", "wrap midi dress", "linen shirtdress", "knit maxi dress",
        "satin bias-cut dress", "cotton sundress", "wool shirt dress", "crepe column dress"
      ],
      "Shoes" => [
        "pointed-toe ankle boots", "strappy heeled sandals", "leather loafers",
        "ballet flats", "knee-high boots", "platform mules", "suede slingbacks",
        "white leather trainers", "block-heel pumps", "chelsea boots"
      ],
      "Accessories" => [
        "structured crossbody bag", "woven tote", "silk square scarf", "gold hoop earrings",
        "leather belt", "cat-eye sunglasses", "pearl hair clip", "chain necklace",
        "cashmere beanie", "mini shoulder bag"
      ],
      "Outerwear" => [
        "wool wrap coat", "trench coat", "quilted liner jacket", "cropped bomber",
        "oversized blazer", "faux-fur jacket", "denim jacket", "puffer vest",
        "cashmere coat", "leather moto jacket"
      ],
    }.freeze

    OUTFIT_VIBES = [
      "Gallery opening", "Coffee date", "Office chic", "Weekend market",
      "Rainy commute", "Summer wedding guest", "Travel day", "Evening drinks",
      "Brunch with friends", "Capsule workweek", "Date night", "Festival layers"
    ].freeze

    HASHTAGS = %w[#ootd #capsulewardrobe #styleinspo #outfitoftheday #slowfashion #wardrobeaudit].freeze

    OCCASIONS = Item::OCCASIONS
    SEASONS = Item::SEASONS
    MOODS = Item::MOOD_EFFECTS
    SIZES = %w[XXS XS S M L XL].freeze

    class << self
      def item_title(category: nil)
        cat = category || PIECES.keys.sample
        piece = PIECES.fetch(cat).sample
        color = COLORS.sample
        "#{color.capitalize} #{piece}"
      end

      def item_attributes(category: nil)
        cat = category || PIECES.keys.sample
        {
          title: item_title(category: cat),
          category: cat,
          color: COLORS.sample,
          brand: BRANDS.sample,
          material: MATERIALS.sample,
          size: SIZES.sample,
          season: SEASONS.sample,
          occasion_tags: OCCASIONS.sample,
          mood_effect: MOODS.sample,
          spark_joy: [ true, true, true, false ].sample,
          price_cents: rand(2_900..28_900),
          times_worn: rand(0..40),
          last_worn_on: rand(1..120).days.ago.to_date,
          purchase_date: rand(30..800).days.ago.to_date,
          lifecycle_state: "active",
          metadata: { notes: item_note },
        }
      end

      def outfit_name = "#{OUTFIT_VIBES.sample} — #{SEASONS.sample}"

      def outfit_description
        [
          "Built around texture and proportion — #{MATERIALS.sample} with #{COLORS.sample} accents.",
          "A #{OCCASIONS.sample} look that repeats well in a capsule wardrobe.",
          "Layering play: #{PIECES.values.flatten.sample} over #{PIECES.values.flatten.sample}.",
        ].sample
      end

      def post_body
        opener = [
          "Wore this #{OCCASIONS.sample} look today",
          "Finally styled my #{COLORS.sample} #{PIECES.values.flatten.sample}",
          "Capsule check-in",
          "Outfit repeat — still sparking joy",
          "Decluttered three pieces, kept this hero item",
        ].sample

        detail = Faker::Lorem.sentence(word_count: rand(8..14)).sub(/\.$/, "")
        "#{opener}. #{detail}. #{HASHTAGS.sample(2).join(' ')}"
      end

      def user_display_name
        Faker::Name.female_first_name
      end

      def user_email
        Faker::Internet.unique.email(name: user_display_name)
      end

      private

      def item_note
        [
          "Pairs with #{COLORS.sample} accessories.",
          "Dry clean only — bought on sale at #{BRANDS.sample}.",
          "Needs hemming; otherwise perfect #{OCCASIONS.sample} piece.",
          "Cost-per-wear finally under £2.",
        ].sample
      end
    end
  end
end
