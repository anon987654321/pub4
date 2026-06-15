namespace :scrape do
  desc "Fashion/wardrobe inspiration via Ferrum + vision LLM (subs: comma-separated, default: malefashion,femalefashionadvice,streetwear)"
  task :fashion, [:subs] => :environment do |_, args|
    subs   = (args[:subs] || "malefashion,femalefashionadvice,streetwear").split(",").map(&:strip)
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
  task :fashion_seed, [:subs] => :environment do |_, args|
    subs   = (args[:subs] || "malefashion,femalefashionadvice,streetwear").split(",").map(&:strip)
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
          title: "#{item['title'][0..50]} (inspired)",
          category: %w[shirt jacket pants shoes].sample,
          color: %w[black navy olive beige].sample,
          brand: %w[Acne COS Uniqlo].sample,
          description: [item['description'], "Sourced/fictivized from r/#{sub} via Ferrum vision scrape."].compact.join(" "),
          price_cents: rand(2000..8000)
        )

        # Occasionally make an Outfit from it + random
        if rand < 0.4 && seed_user.items.count > 3
          outfit_items = seed_user.items.last(4)
          Outfit.create!(
            user: seed_user,
            name: "Look inspired by #{sub}",
            description: "Fictive outfit from web scrape",
            items: outfit_items,
            context_label: %w[casual work date].sample
          )
        end
      end
      puts "Seeded #{items.size} fashion-inspired items/outfits from r/#{sub}."
    end
  end
end
