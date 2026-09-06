# frozen_string_literal: true

namespace :scrape do
  desc "X (Twitter) posts via Ferrum + vision LLM (queries: comma-separated, default: bergen,oslo,norge)"
  task :x, [ :queries ] => :environment do |_, args|
    queries = (args[:queries] || "bergen,oslo,norge").split(",").map(&:strip)
    schema = %w[author text timestamp likes retweets url]
    queries.each do |q|
      url = "https://x.com/search?q=#{CGI.escape(q)}&src=typed_query&f=live"
      Scrape.call(
        url,
        schema: schema,
        hint: "Extract visible tweets in the search results. author is the @handle or display name. text is the tweet body (ignore images/links for text). timestamp relative or absolute. likes/retweets are counts. url is the tweet permalink if available. Skip ads and 'show more'."
      ).each { |item| puts item.merge("query" => q, "source" => "x").to_json }
    end
  end

  desc "Seed fictive data from X scrape into brgen models (users, posts, comments). Requires OPENROUTER_API_KEY."
  task :x_seed, [ :queries ] => :environment do |_, args|
    require "cgi"
    queries = (args[:queries] || "bergen,oslo,norge").split(",").map(&:strip)
    schema = %w[author text timestamp likes retweets url]

    user = User.first || User.create!(email_address: "seed@x.local", password: "password123",
                                      password_confirmation: "password123", username: "xseed")

    queries.each do |q|
      url = "https://x.com/search?q=#{CGI.escape(q)}&src=typed_query&f=live"
      items = Scrape.call(url, schema: schema, hint: "Extract visible tweets... (same as :x)")

      items.each do |item|
        # Fictivize + route to subapps
        title = "#{q.capitalize} buzz: #{item['text'][0..60]}..."
        body = [ item["text"],
                 "— scraped & fictivized from X search '#{q}' (#{item['timestamp']}, likes: #{item['likes']})" ].compact.join("\n\n")

        # Core social (always for feed)
        post = Post.create!(
          user: user,
          title: title,
          content: body,
          community: Community.find_by(slug: "tech") || Community.find_by(slug: "bergen") || Community.first
        )
        post.record_activity!("XScrapeSeed") if post.respond_to?(:record_activity!)

        text_lower = item["text"].to_s.downcase

        # Marketplace
        if /sale|selger|kjøp|deal|tilbud|market/i.match?(text_lower)
          Marketplace::Listing.create!(
            user: user,
            title: item["text"][0..80],
            description: body,
            price_cents: rand(1000..100_000),
            category: Marketplace::Category.all.sample || Marketplace::Category.create!(name: "Misc",
                                                                                        slug: "misc-#{SecureRandom.hex(4)}")
          )
        end

        # Takeaway
        if /mat|food|restaurant|kafe|delivery|takeaway|spise/i.match?(text_lower)
          rest = Takeaway::Restaurant.find_or_create_by!(name: item["text"][0..50]) do |r|
            r.user = user
            r.cuisine_type = %w[Norwegian Italian Pizza].sample
            r.address = "Bergen"
            r.description = body[0..200]
          end
          Takeaway::MenuItem.create!(restaurant: rest, name: Faker::Food.dish, price_cents: rand(8000..25_000)) if rest
        end

        # Dating / social
        if /dating|date|single|relationship|venner/i.match?(text_lower)
          Dating::Profile.find_or_create_by!(user: user) do |p|
            p.bio = body[0..150]
            p.age = rand(20..45)
          end
        end

        # Playlist / music
        if /musikk|musikk|band|konsert|playlist|spilleliste|song|track/i.match?(text_lower)
          pl = Playlist::Playlist.find_or_create_by!(name: item["text"][0..40], user: user) do |p|
            p.description = body[0..100]
          end
          Playlist::Track.create!(title: Faker::Music.song_name, artist: Faker::Music.band) if pl
        end

        # TV / media
        if /tv|film|serie|netflix|watch|se på/i.match?(text_lower)
          ch = Tv::Channel.find_or_create_by!(name: "#{q} Media", user: user) do |c|
            c.description = "Fictive from X scrape"
          end
          show = Tv::Show.create!(channel: ch, title: item["text"][0..50], description: body[0..150])
          Tv::Episode.create!(show: show, title: "Ep 1", description: Faker::Lorem.sentence)
        end

        # Maps / local places (if location or local buzz)
        if text_lower =~ /bergen|oslo|place|spot|cafe|park|bar|location/i || q =~ /bergen|oslo/i
          Place.find_or_create_by!(name: item["text"][0..40]) do |p|
            p.kind = %w[cafe bar shop park restaurant].sample
            p.address = "Bergen area"
            p.latitude = 60.39 + rand(-0.05..0.05)
            p.longitude = 5.33 + rand(-0.05..0.05)
            p.description = body[0..100]
          end
        end

        # Messages / social convos (sample from posts)
        next unless rand < 0.2

        conv = Conversation.create!
        [ user, users.sample ].uniq.each { |u| conv.conversation_participants.create!(user: u) }
        2.times { Message.create!(conversation: conv, sender: [ user, users.sample ].sample, content: Faker::Lorem.sentence) }
      end
      puts "Seeded #{items.size} X items for query #{q} into Posts (fictive)."
    end
  end
end
