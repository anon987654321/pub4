# frozen_string_literal: true

namespace :scrape do
  desc "Reddit hot posts via Ferrum + vision LLM (subs: comma-separated, default: norge,bergen,oslo)"
  task :reddit, [ :subs ] => :environment do |_, args|
    subs = (args[:subs] || "norge,bergen,oslo").split(",").map(&:strip)
    schema = RedditSeedService::POST_SCHEMA
    subs.each do |sub|
      Scrape.call(
        "https://www.reddit.com/r/#{sub}/hot/",
        schema: schema,
        hint: "Skip pinned moderator posts. comment_count is upvotes. top_comments is an array of preview comments."
      ).each { |item| puts item.merge("subreddit" => sub).to_json }
    end
  end

  desc "Seed unique local posts from Reddit (rephrased + Strunk & White). Requires OPENROUTER_API_KEY."
  task :reddit_seed, [ :domain ] => :environment do |_, args|
    domain = args[:domain].presence || "brgen.no"
    city = City.find_by!(domain: domain)
    posts = RedditSeedService.new(city:, domain:).call
    puts "Seeded #{posts.size} unique posts for #{domain} (rephrased, no Reddit attribution)."
  end
end
