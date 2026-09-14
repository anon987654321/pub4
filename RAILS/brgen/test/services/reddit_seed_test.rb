# frozen_string_literal: true

require "test_helper"

class RedditSeedTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @admin = User.strict_loading(false).create!(
      email_address: "reddit_seed_test@brgen.no",
      password: "password123",
      city: @city
    )
    @community = Community.create!(slug: "seed-test", name: "Seed Test", user: @admin, city: @city)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "seeds rephrased posts without reddit markers" do
    stub_scrape([
      {
        "title" => "[r/bergen] Best kanelbolle?",
        "body" => "Looking for bakery tips downtown.",
        "url" => "https://www.reddit.com/r/bergen/comments/abc123/",
        "top_comments" => [ { "author" => "u1", "body" => "Baker Hansen on Torget." } ]
      }
    ])

    rewriter = Object.new
    rewriter.define_singleton_method(:rewrite) do |**_kwargs|
      Shared::ContentRewriter::Result.new(
        title: "Best cinnamon bun downtown?",
        body: "Which bakery should I try near Torget?",
        comments: [ "Baker Hansen opens early.", "Get there before ten." ]
      )
    end

    posts = ActsAsTenant.with_tenant(@city) {
      RedditSeed.new(city: @city, domain: "brgen.no", subs: [ "bergen" ], rewriter: rewriter).call
    }

    assert_equal 1, posts.size
    post = posts.first
    refute_match(/\[r\//i, post.title)
    refute_match(/reddit/i, post.content)
    seeded_comments = Comment.strict_loading(false).where(commentable: post)
    assert seeded_comments.count >= 2
    assert seeded_comments.all? { |comment| comment.content !~ /reddit/i }
  end

  test "a tv subreddit seeds a channel, a show and its first episode" do
    stub_scrape([ { "title" => "Kveldens serie", "body" => "Hva ser dere på?", "url" => "" } ])

    rewriter = Object.new
    rewriter.define_singleton_method(:rewrite) do |title:, body:, **_kwargs|
      Shared::ContentRewriter::Result.new(title: title, body: body, comments: [])
    end

    ActsAsTenant.with_tenant(@city) do
      RedditSeed.new(city: @city, domain: "brgen.no", subs: [ "tv" ], rewriter: rewriter).call
    end

    show = Tv::Show.strict_loading(false).find_by!(title: "Kveldens serie")
    assert_equal [ 1 ], Tv::Episode.where(show: show).pluck(:number)
  end

  private

  def stub_scrape(items)
    Shared::Scrape.define_singleton_method(:call) { |_url, **_kwargs| items }
  end
end
