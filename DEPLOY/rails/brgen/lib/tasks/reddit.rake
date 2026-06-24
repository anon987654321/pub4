# frozen_string_literal: true

namespace :scrape do
  desc "Reddit hot posts via Ferrum + vision LLM (subs: comma-separated, default: norge,bergen,oslo)"
  task :reddit, [ :subs ] => :environment do |_, args|
    subs   = (args[:subs] || "norge,bergen,oslo").split(",").map(&:strip)
    schema = %w[title url body score author comments]
    subs.each do |sub|
      Scrape.call(
        "https://www.reddit.com/r/#{sub}/hot/",
        schema: schema,
        hint: "Skip pinned moderator posts. score is the upvote count. comments is the comment count. body is the post selftext or empty if image/link post."
      ).each { |item| puts item.merge("subreddit" => sub).to_json }
    end
  end

  desc "Seed fictive data from Reddit scrape into brgen models (Posts, Marketplace listings, Takeaway, etc.). Requires OPENROUTER_API_KEY. Run after or instead of pure faker seeds."
  task :reddit_seed, [ :subs ] => :environment do |_, args|
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
        hint: "Skip pinned moderator posts. score is the upvote count. comments is the comment count. body is the post selftext or empty if image/link post."
      )

      items.each do |item|
        # Fictivize + route to subapps intelligently
        title = "[r/#{sub}] #{item['title']}"
        body  = [ item["body"],
                 "— scraped & fictivized from Reddit (score: #{item['score']}, comments: #{item['comments']})" ].compact.join("\n\n")

        # Core social feed (always)
        post = Post.create!(
          user: seed_user,
          title: title,
          content: body,
          community: Community.find_by(slug: sub) || Community.find_by(slug: "bergen") || Community.first
        )
        post.record_activity!("RedditScrapeSeed") if post.respond_to?(:record_activity!)

        # Marketplace
        if sub =~ /buy|sell|market|oslo|bergen/i || item["title"] =~ /sale|selger|kjøp|til salgs/i
          Marketplace::Listing.create!(
            user: seed_user,
            title: item["title"][0..80],
            description: body,
            price_cents: rand(1000..100_000),
            category: Marketplace::Category.all.sample || Marketplace::Category.create!(name: "Misc",
                                                                                        slug: "misc-#{SecureRandom.hex(4)}")
          )
        end

        # Takeaway / restaurants
        if sub =~ /food|mat|oslo|bergen|restaurant|oslofood/i || item["title"] =~ /restaurant|kafe|mat|delivery|takeaway/i
          rest = Takeaway::Restaurant.find_or_create_by!(name: item["title"][0..60]) do |r|
            r.user = seed_user
            r.cuisine_type = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza].sample
            r.address = "#{Faker::Address.street_address}, Bergen"
            r.description = body[0..300]
            r.delivery_fee_cents = rand(2000..5000)
            r.min_order_cents = rand(5000..15_000)
          end
          # Add a menu item
          Takeaway::MenuItem.create!(
            restaurant: rest,
            name: Faker::Food.dish,
            price_cents: rand(8000..25_000),
            description: Faker::Food.description
          )
        end

        # Dating / social prompts (if relationship or local social)
        if /dating|relationship|oslo|bergen|social/i.match?(sub)
          Dating::Profile.find_or_create_by!(user: seed_user) do |p|
            p.bio = body[0..200]
            p.age = rand(20..45)
            p.interests = Faker::Lorem.words(number: 4).join(", ")
          end
        end

        # Playlist / music (if music sub)
        if sub =~ /music|musikk|oslo|bergen/i || item["title"] =~ /musikk|band|konsert|playlist/i
          pl = Playlist::Playlist.find_or_create_by!(name: item["title"][0..50], user: seed_user) do |p|
            p.description = body[0..150]
          end
          if pl
            Playlist::Track.create!(
              title: Faker::Music.song_name,
              artist: Faker::Music.band,
              playlist: pl # simplistic; real would use join
            )
          end
        end

        # TV / media
        next unless /tv|film|movie|serie|netflix/i.match?(sub)

        ch = Tv::Channel.find_or_create_by!(name: "r/#{sub} TV", user: seed_user) do |c|
          c.description = "Fictive channel from Reddit scrape"
        end
        show = Tv::Show.create!(
          channel: ch,
          title: item["title"][0..60],
          description: body[0..200]
        )
        Tv::Episode.create!(
          show: show,
          title: "Ep 1: #{Faker::Lorem.words(number: 3).join(' ')}",
          description: Faker::Lorem.sentence
        )
      end
      puts "Seeded #{items.size} Reddit items from r/#{sub} (fictive, routed to subapps)."
    end
  end
end
