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
end
