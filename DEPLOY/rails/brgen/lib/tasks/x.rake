namespace :scrape do
  desc "X (Twitter) posts via Ferrum + vision LLM (queries: comma-separated, default: bergen,oslo,norge)"
  task :x, [:queries] => :environment do |_, args|
    queries = (args[:queries] || "bergen,oslo,norge").split(",").map(&:strip)
    schema  = %w[author text timestamp likes retweets url]
    queries.each do |q|
      url = "https://x.com/search?q=#{CGI.escape(q)}&src=typed_query&f=live"
      Scrape.call(
        url,
        schema: schema,
        hint:   "Extract visible tweets in the search results. author is the @handle or display name. text is the tweet body (ignore images/links for text). timestamp relative or absolute. likes/retweets are counts. url is the tweet permalink if available. Skip ads and 'show more'."
      ).each { |item| puts item.merge("query" => q, "source" => "x").to_json }
    end
  end

  desc "Seed fictive data from X scrape into brgen models (posts, etc.). Requires OPENROUTER_API_KEY."
  task :x_seed, [:queries] => :environment do |_, args|
    require "cgi"
    queries = (args[:queries] || "bergen,oslo,norge").split(",").map(&:strip)
    schema  = %w[author text timestamp likes retweets url]

    user = User.first || User.create!(email_address: "seed@x.local", password: "password123", password_confirmation: "password123", username: "xseed")

    queries.each do |q|
      url = "https://x.com/search?q=#{CGI.escape(q)}&src=typed_query&f=live"
      items = Scrape.call(url, schema: schema, hint: "Extract visible tweets... (same as :x)")

      items.each do |item|
        # Fictivize: anonymize, mix with local flavor, use for Post or subapp content
        post = Post.create!(
          user: user,
          title: "#{q.capitalize} buzz: #{item['text'][0..60]}...",
          content: [item['text'], "— scraped & fictivized from X search '#{q}' (#{item['timestamp']})"].join("\n\n"),
          community: Community.find_by(slug: "tech") || Community.first
        )
        post.record_activity!("XScrapeSeed") if post.respond_to?(:record_activity!)

        # Example: if text mentions food/deal -> takeaway or marketplace inspiration
        if item['text'] =~ /mat|food|deal|tilbud/i
          # Could create Takeaway::Restaurant or Marketplace::Listing seed here
          puts "  -> potential takeaway/marketplace lead from X: #{item['text'][0..50]}"
        end
      end
      puts "Seeded #{items.size} X items for query #{q} into Posts (fictive)."
    end
  end
end
