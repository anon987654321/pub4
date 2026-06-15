namespace :scrape do
  desc "Reddit hot posts via Ferrum + vision LLM (subs: comma-separated, default: norge,bergen,oslo)"
  task :reddit, [:subs] => :environment do |_, args|
    subs   = (args[:subs] || "norge,bergen,oslo").split(",").map(&:strip)
    schema = %w[title url body score author comments]
    subs.each do |sub|
      Scrape.call(
        "https://www.reddit.com/r/#{sub}/hot/",
        schema: schema,
        hint:   "Skip pinned moderator posts. score is the upvote count. comments is the comment count. body is the post selftext or empty if image/link post."
      ).each { |item| puts item.merge("subreddit" => sub).to_json }
    end
  end

  desc "Seed fictive data from Reddit scrape into brgen models (Posts, Marketplace listings, Takeaway, etc.). Requires OPENROUTER_API_KEY. Run after or instead of pure faker seeds."
  task :reddit_seed, [:subs] => :environment do |_, args|
    subs   = (args[:subs] || "norge,bergen,oslo").split(",").map(&:strip)
    schema = %w[title url body score author comments]

    seed_user = User.find_or_create_by!(email_address: "reddit-seed@brgen.no") do |u|
      u.username = "redditseed"
      u.password = u.password_confirmation = "password123"
    end

    subs.each do |sub|
      items = Scrape.call(
        "https://www.reddit.com/r/#{sub}/hot/",
        schema: schema,
        hint:   "Skip pinned moderator posts. score is the upvote count. comments is the comment count. body is the post selftext or empty if image/link post."
      )

      items.each do |item|
        # Fictivize + route to subapps
        title = "[r/#{sub}] #{item['title']}"
        body  = [item['body'], "— scraped & fictivized from Reddit (score: #{item['score']})"].compact.join("\n\n")

        if sub =~ /food|mat|oslo|bergen/i || item['title'] =~ /restaurant|food|delivery/i
          # Takeaway inspiration
          Takeaway::Restaurant.find_or_create_by!(name: item['title'][0..60]) do |r|
            r.user = seed_user
            r.cuisine_type = %w[Norwegian Italian Pizza].sample
            r.address = "Bergen"
            r.description = body[0..200]
          end
        elsif sub =~ /buy|sell|market/i || item['title'] =~ /sale|selger|kjøp/i
          # Marketplace
          Marketplace::Listing.create!(
            user: seed_user,
            title: title,
            description: body,
            price_cents: rand(5000..50000),
            category: Marketplace::Category.first || Marketplace::Category.create!(name: "Misc", slug: "misc")
          )
        else
          # Default to core Post (visible in feed for all subapps)
          post = Post.create!(
            user: seed_user,
            title: title,
            content: body,
            community: Community.find_by(slug: "bergen") || Community.first
          )
          post.record_activity!("RedditScrapeSeed") if post.respond_to?(:record_activity!)
        end
      end
      puts "Seeded #{items.size} Reddit items from r/#{sub} (fictive, routed to subapps)."
    end
  end
end
