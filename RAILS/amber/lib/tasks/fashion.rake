# frozen_string_literal: true

namespace :scrape do
  desc "Fashion/wardrobe inspiration via Ferrum + vision LLM (subs: comma-separated, default: femalefashionadvice,30PlusSkinCare,PetiteFashion)"
  task :fashion, [ :subs ] => :environment do |_, args|
    subs = (args[:subs] || "femalefashionadvice,30PlusSkinCare,PetiteFashion").split(",").map(&:strip)
    schema = %w[title description url upvotes comments image_hints]
    subs.each do |sub|
      Scrape.call(
        "https://www.reddit.com/r/#{sub}/hot/",
        schema: schema,
        hint:   "Focus on outfit photos and descriptions. title is the post title, description any selftext or top comments summary. upvotes and comments counts. image_hints from visual (colors, style, items like jacket, sneakers). Skip ads."
      ).each { |item| puts item.merge("subreddit" => sub).to_json }
    end
  end

  desc "Seed fictive wardrobe/outfit data from fashion scrape into amber. Requires OPENROUTER_API_KEY. Supplements Faker seeds."
  task :fashion_seed, [ :subs ] => :environment do |_, args|
    subs = (args[:subs] || "femalefashionadvice,30PlusSkinCare,PetiteFashion").split(",").map(&:strip)
    schema = %w[title description url upvotes comments image_hints]

    seed_user = User.find_or_create_by!(email_address: "fashion-seed@amber.local") do |u|
      u.password = u.password_confirmation = "password123"
    end

    subs.each do |sub|
      items = Scrape.call(
        "https://www.reddit.com/r/#{sub}/hot/",
        schema: schema,
        hint:   "Focus on outfit photos and descriptions. title is the post title, description any selftext or top comments summary. upvotes and comments counts. image_hints from visual (colors, style, items like jacket, sneakers). Skip ads."
      )

      items.each do |item|
        # Create Item as fictive wardrobe piece inspired by scrape
        item_rec = Item.create!(
          user: seed_user,
          title: "#{item['title'][0..50]} (inspired by r/#{sub})",
          category: %w[shirt jacket pants shoes dress coat sweater accessory hat].sample,
          color: %w[black navy white gray beige olive burgundy teal mustard].sample,
          brand: %w[Acne Arket COS Uniqlo Zara H&M Everlane Patagonia].sample,
          description: [ item["description"] || item["title"], "Sourced/fictivized from r/#{sub} via Ferrum vision scrape (upvotes: #{item["upvotes"]})." ].compact.join(" "),
          price_cents: rand(1500..15000),
          worn_count: rand(0..25),
          last_worn_at: rand(1..90).days.ago
        )

        # Create Outfit incorporating this + some random existing items for richer capsules
        if rand < 0.5 && seed_user.items.count > 2
          outfit_items = (seed_user.items.last(3) + [ item_rec ]).uniq.sample(4)
          Outfit.create!(
            user: seed_user,
            name: "#{sub.titleize} Look #{rand(100)}",
            description: "Fictive outfit capsule inspired by scraped Reddit content",
            items: outfit_items,
            context_label: %w[casual work date travel party].sample,
            estimated_value: outfit_items.sum(&:price_cents),
            total_wears: rand(0..15),
            last_worn_at: rand(1..60).days.ago
          )
        end

        # Occasionally a Post sharing the style (ties to social feed in brgen too if cross-posted)
        if rand < 0.3
          Post.create!(
            user: seed_user,
            body: "Styled this #{item_rec.category} from r/#{sub} inspo. #wardrobe #ootd",
            item: item_rec
          )
        end
      end
      puts "Seeded #{items.size} fashion-inspired items/outfits from r/#{sub}."
    end
  end
end
