# frozen_string_literal: true

class RedditSeed
  POST_SCHEMA = %w[title url body score author comment_count top_comments].freeze
  COMMENT_SCHEMA = %w[author body score].freeze

  def initialize(city:, domain:, subs: nil, rewriter: Shared::ContentRewriter)
    @city = city
    @domain = domain
    @subs = subs || Brgen::DomainRegistry.subreddits_for(domain)
    @rewriter = rewriter
  end

  def call
    ActsAsTenant.with_tenant(@city) do
      seed_user = seed_account("reddit-seed@#{@domain}", "community")
      @subs.flat_map { |sub| seed_subreddit(sub, seed_user) }
    end
  end

  private

  def seed_subreddit(sub, seed_user)
    items = Scrape.call(
      "https://www.reddit.com/r/#{sub}/hot/",
      schema: POST_SCHEMA,
      hint: post_hint(sub)
    )

    items.map { |item| seed_item(item, sub, seed_user) }
  end

  def seed_item(item, sub, seed_user)
    comments = extract_comments(item)
    rewritten = @rewriter.rewrite(
      title: item["title"].to_s,
      body: item["body"].to_s,
      comments: comments,
      city_name: @city.name,
      locale: @city.try(:locale) || "en"
    )

    post = create_post(rewritten, sub, seed_user)
    seed_comments(post, rewritten.comments)
    route_verticals(rewritten, item, sub, seed_user)
    post
  end

  def extract_comments(item)
    scraped = normalize_comments(item["top_comments"])
    return scraped if scraped.any?
    return [] if item["url"].blank?

    Scrape.call(
      item["url"],
      schema: COMMENT_SCHEMA,
      hint: "Extract up to 5 top-level comments visible on the thread. Skip AutoModerator and deleted."
    ).map { |row| row["body"].to_s }.reject(&:blank?)
  rescue StandardError => error
    Rails.logger.warn("RedditSeed comment scrape failed: #{error.message}")
    []
  end

  def normalize_comments(raw)
    case raw
    when Array
      raw.filter_map { |row| row.is_a?(Hash) ? row["body"].to_s : row.to_s }.reject(&:blank?)
    when String
      begin
        JSON.parse(raw).filter_map { |row| row["body"].to_s }.reject(&:blank?)
      rescue JSON::ParserError
        []
      end
    else
      []
    end
  end

  def create_post(rewritten, sub, seed_user)
    community = Community.find_by(slug: sub) ||
                Community.find_by(slug: Brgen::CityContent.community_slugs_for(@city.country_code).first) ||
                Community.first

    post = Post.create!(
      user: seed_user,
      city: @city,
      title: rewritten.title.truncate(300),
      content: rewritten.body,
      community: community,
      created_at: staggered_time
    )
    post.record_activity!("RedditSeed") if post.respond_to?(:record_activity!)
    post
  end

  def seed_comments(post, bodies)
    rows = bodies.first(8).each_with_index.filter_map do |body, index|
      commenter = seed_account("seed-#{Digest::SHA256.hexdigest(body)[0, 12]}@#{@domain}", "member")
      {
        user_id: commenter.id,
        commentable_type: post.class.name,
        commentable_id: post.id,
        content: body.truncate(10_000),
        created_at: post.created_at + (index + 1).minutes + rand(0..40).seconds,
        updated_at: Time.current
      }
    end
    Comment.insert_all(rows) if rows.any?
    post.touch
  end

  def route_verticals(rewritten, item, sub, seed_user)
    body = rewritten.body
    title = rewritten.title

    seed_marketplace(title, body, sub, seed_user) if marketplace_signal?(sub, title)
    seed_takeaway(title, body, sub, seed_user) if takeaway_signal?(sub, title)
    seed_dating(body, sub, seed_user) if dating_signal?(sub)
    seed_playlist(title, body, sub, seed_user) if playlist_signal?(sub, title)
    seed_tv(title, body, sub, seed_user) if tv_signal?(sub)
  end

  def seed_marketplace(title, body, sub, seed_user)
    Marketplace::Listing.create!(
      user: seed_user,
      title: title.truncate(80),
      description: body,
      price_cents: rand(1000..100_000),
      category: Marketplace::Category.all.sample ||
                Marketplace::Category.create!(name: "Misc", slug: "misc-#{SecureRandom.hex(4)}")
    )
  end

  def seed_takeaway(title, body, sub, seed_user)
    rest = Takeaway::Restaurant.find_or_create_by!(name: title.truncate(60)) do |restaurant|
      restaurant.user = seed_user
      restaurant.cuisine_type = %w[Norwegian Italian Chinese Japanese Indian Thai Mexican Pizza].sample
      restaurant.address = "#{Faker::Address.street_address}, #{@city.name}"
      restaurant.city = @city.name
      restaurant.description = body.truncate(300)
      restaurant.delivery_fee_cents = rand(2000..5000)
      restaurant.min_order_cents = rand(5000..15_000)
    end
    Takeaway::MenuItem.create!(
      restaurant: rest,
      name: Faker::Food.dish,
      price_cents: rand(8000..25_000),
      description: Faker::Food.description
    )
  end

  def seed_dating(body, sub, seed_user)
    Dating::Profile.find_or_create_by!(user: seed_user) do |profile|
      profile.bio = body.truncate(200)
      profile.age = rand(20..45)
      profile.interests = Faker::Lorem.words(number: 4).join(", ")
    end
  end

  def seed_playlist(title, body, sub, seed_user)
    playlist = Playlist::Playlist.find_or_create_by!(name: title.truncate(50), user: seed_user) do |record|
      record.description = body.truncate(150)
    end
    return unless playlist

    Playlist::Track.create!(
      title: Faker::Music.song_name,
      artist: Faker::Music.band,
      playlist: playlist
    )
  end

  def seed_tv(title, body, sub, seed_user)
    channel = Tv::Channel.find_or_create_by!(name: "#{@city.name} TV", user: seed_user) do |record|
      record.description = "Local media from #{@city.name}"
    end
    show = Tv::Show.create!(channel: channel, title: title.truncate(60), description: body.truncate(200))
    Tv::Episode.create!(
      show: show,
      title: "Episode 1",
      description: Faker::Lorem.sentence
    )
  end

  def marketplace_signal?(sub, title) = sub =~ /buy|sell|market|oslo|bergen/i || title =~ /sale|selger|kjøp|til salgs/i
  def takeaway_signal?(sub, title) = sub =~ /food|mat|restaurant/i || title =~ /restaurant|kafe|mat|delivery|takeaway/i
  def dating_signal?(sub) = /dating|relationship|social/i.match?(sub)
  def playlist_signal?(sub, title) = sub =~ /music|musikk/i || title =~ /musikk|band|konsert|playlist/i
  def tv_signal?(sub) = /tv|film|movie|serie|netflix/i.match?(sub)

  def seed_account(email, prefix)
    User.strict_loading(false).find_or_create_by!(email_address: email) do |user|
      user.username = "#{prefix}_#{@city.slug}_#{SecureRandom.hex(3)}"
      user.password = user.password_confirmation = SecureRandom.hex(16)
      user.city = @city
    end
  end

  def staggered_time = rand(1..96).hours.ago + rand(0..59).minutes

  def post_hint(sub)
    <<~HINT
      Skip pinned moderator posts. comment_count is the visible comment total.
      top_comments is an array of up to 3 objects with author and body from the listing card or preview.
      body is post selftext; empty for link/image posts.
      Subreddit: r/#{sub}
    HINT
  end
end
