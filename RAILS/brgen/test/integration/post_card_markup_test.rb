# frozen_string_literal: true

require "test_helper"

# The feed card as a reader meets it: one element per id, a worded read-more
# link, a machine-readable time, an author name that leads to the author, photos
# told apart, and a cache key that knows who is reading.
class PostCardMarkupTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city

    @author = User.strict_loading(false).create!(email_address: "card-#{SecureRandom.hex(4)}@brgen.no",
                                                 password: "password12345", city: @city, guest: false,
                                                 username: "kort#{SecureRandom.hex(3)}")
    @post = Post.create!(user: @author, title: "Kortet", content: "Ord " * 120, city: @city)
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def card
    get root_path
    assert_response :success
    Nokogiri::HTML(response.body).at_css("turbo-frame##{ActionView::RecordIdentifier.dom_id(@post)}")
  end

  test "the card's id belongs to its frame alone" do
    id = ActionView::RecordIdentifier.dom_id(@post)
    get root_path

    assert_equal 1, Nokogiri::HTML(response.body).css("[id='#{id}']").size
  end

  test "the read-more link is a word, not a glyph" do
    more = card.at_css("a.post-reading-more")

    refute_nil more
    assert_equal I18n.t("post.read_more"), more.text.strip
  end

  test "the card time is a time element with the full date on hover" do
    time = card.at_css("time.feed-card-time")

    refute_nil time
    assert_equal @post.created_at.iso8601, time["datetime"]
    assert_equal I18n.l(@post.created_at, format: :long), time["title"]
    assert_equal I18n.t("shared.time_ago", time: ActionController::Base.helpers.time_ago_in_words(@post.created_at)),
                 time.text.strip
  end

  test "the author name leads to the author's profile" do
    assert_equal user_path(@author), card.at_css(".feed-card-name a")["href"]
  end

  test "each photo is told apart and the first counts the rest" do
    3.times do
      @post.images.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")
    end

    images = card.css(".post-images img")
    assert_equal 3, images.size
    assert_equal I18n.t("post.photo_of", number: 2, total: 3, title: @post.title), images[1]["alt"]
    assert_equal "+2", card.at_css(".post-images a:first-child .post-image-more").text
  end

  test "the quote box shows its limit" do
    hint = card.at_css(".feed-quote-form small")

    assert_equal I18n.t("post.quote_limit", count: Repost::COMMENT_MAX), hint.text
    assert_equal hint["id"], card.at_css(".feed-quote-form textarea")["aria-describedby"]
  end

  test "the cache key carries the reader's presence, the author and the community" do
    source = File.read(Rails.root.join("app/views/posts/_post.html.erb"))
    key = source[/<% cache \[(.*?)\] do %>/m, 1]

    assert_includes key, "Current.user.present?"
    assert_includes key, "post.user"
    assert_includes key, "post.community"
  end

  # From 640px the action row packs left and its children drop to their
  # content width: an icon-only action measured 42px across. Both rules that
  # set min-width auto there now restore the tap floor for .feed-action.
  test "feed actions keep the tap floor once the row packs left" do
    brgen = File.read(Rails.root.join("app/assets/stylesheets/_brgen_feed_posts.scss"))
    shared = File.read(Rails.root.join("../__shared/app/assets/stylesheets/_post_voting.scss"))

    assert_match(/\.feed-card-actions > \.feed-action \{\s*min-width: var\(--tap-min\);/, brgen)
    floor = /\.feed-card\.post-reading-card \.feed-card-actions > \.feed-action \{\s*min-inline-size: var\(--tap-min\);/
    assert_match floor, shared
  end
end
