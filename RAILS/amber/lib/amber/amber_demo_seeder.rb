# frozen_string_literal: true

module Amber
  # Credible capsule wardrobe demo — safe to run idempotently on production.
  class AmberDemoSeeder
    ITEMS = [
      { title: "Bergen rain shell", category: "Outerwear", color: "navy", brand: "Patagonia", size: "M",
        price_cents: 12_900, times_worn: 42, season: "All-Season", occasion: "work", spark_joy: true },
      { title: "Merino crew neck", category: "Tops", color: "oatmeal", brand: "COS", size: "M",
        price_cents: 4_500, times_worn: 28, season: "Autumn", occasion: "casual", spark_joy: true },
      { title: "Dark straight jeans", category: "Bottoms", color: "indigo", brand: "Arket", size: "32",
        price_cents: 8_900, times_worn: 35, season: "All-Season", occasion: "casual", spark_joy: true },
      { title: "White Oxford shirt", category: "Tops", color: "white", brand: "Uniqlo", size: "M",
        price_cents: 3_900, times_worn: 19, season: "Spring", occasion: "work", spark_joy: true },
      { title: "Black Chelsea boots", category: "Shoes", color: "black", brand: "Vagabond", size: "42",
        price_cents: 14_500, times_worn: 31, season: "Autumn", occasion: "work", spark_joy: true },
      { title: "Quilted liner jacket", category: "Outerwear", color: "olive", brand: "Arket", size: "M",
        price_cents: 7_900, times_worn: 12, season: "Winter", occasion: "casual", spark_joy: true },
      { title: "Grey wool trousers", category: "Bottoms", color: "charcoal", brand: "COS", size: "M",
        price_cents: 9_900, times_worn: 22, season: "Winter", occasion: "work", spark_joy: true },
      { title: "Silk square scarf", category: "Accessories", color: "rust", brand: "H&M", size: "onesize",
        price_cents: 2_900, times_worn: 8, season: "All-Season", occasion: "formal", spark_joy: true },
      { title: "Linen summer dress", category: "Dresses", color: "sage", brand: "Everlane", size: "M",
        price_cents: 11_500, times_worn: 6, season: "Summer", occasion: "date", spark_joy: true },
      { title: "Crossbody leather bag", category: "Accessories", color: "tan", brand: "Fossil", size: "onesize",
        price_cents: 6_500, times_worn: 48, season: "All-Season", occasion: "travel", spark_joy: true },
      { title: "Running trainers", category: "Shoes", color: "white", brand: "On", size: "42",
        price_cents: 15_900, times_worn: 55, season: "All-Season", occasion: "gym", spark_joy: true },
      { title: "Striped Breton tee", category: "Tops", color: "navy/white", brand: "Arket", size: "M",
        price_cents: 3_500, times_worn: 14, season: "Summer", occasion: "casual", spark_joy: false }
    ].freeze

    OUTFITS = [
      { name: "Rainy Bergen commute", occasion: "work", season: "Autumn",
        items: ["Bergen rain shell", "Merino crew neck", "Dark straight jeans", "Black Chelsea boots"] },
      { name: "Weekend café", occasion: "casual", season: "Spring",
        items: ["Striped Breton tee", "Dark straight jeans", "Quilted liner jacket", "Crossbody leather bag"] },
      { name: "Office layers", occasion: "work", season: "Winter",
        items: ["White Oxford shirt", "Grey wool trousers", "Bergen rain shell", "Silk square scarf"] }
    ].freeze

    def seed!
      demo = ensure_demo_user!
      items_by_title = seed_items!(demo)
      seed_outfits!(demo, items_by_title)
    end

    private

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
        index[row[:title]] = item
      end
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