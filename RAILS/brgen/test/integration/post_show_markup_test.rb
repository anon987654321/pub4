# frozen_string_literal: true

require "test_helper"

# posts#show as a reader meets it: the byline, the quotes, the comment heading
# and sort, the empty state and the share image.
class PostShowMarkupTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city

    @author = make_user("forfatter")
    @quoter = make_user("siterer")
    @post = Post.create!(user: @author, title: "Vis meg", content: "innhold", city: @city)
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def make_user(name)
    User.strict_loading(false).create!(email_address: "#{name}-#{SecureRandom.hex(4)}@brgen.no",
                                       password: "password12345", city: @city, guest: false,
                                       username: "#{name}#{SecureRandom.hex(3)}")
  end

  def page
    get post_path(@post)
    assert_response :success
    Nokogiri::HTML(response.body)
  end

  test "the byline links the author and dates the time in full" do
    meta = page.at_css(".feed-post-show-meta")

    assert_equal user_path(@author), meta.at_css(%(a[href="#{user_path(@author)}"]))&.[]("href")
    assert_equal I18n.l(@post.created_at, format: :long), meta.at_css("time")["title"]
  end

  test "each quote names its author as a profile link and says when" do
    @quoter.reposts.create!(post: @post, comment: "Godt sagt")
    quote = page.at_css("#quotes blockquote")

    assert_equal user_path(@quoter), quote.at_css("cite a")["href"]
    refute_nil quote.at_css("time[datetime]")
  end

  test "the comments heading counts the comments" do
    heading = page.at_css("#comments-section > h2")

    assert_equal I18n.t("comments.heading_count", count: @post.comment_count), heading.text.strip
  end

  test "the empty comment state is not a live region" do
    assert_nil page.at_css("#comments_empty [aria-live]")
  end

  test "the active comment sort is marked current" do
    @post.comments.create!(user: @quoter, content: "første")
    links = page.css("nav.comment-sort a")

    assert_equal 1, links.count { _1["aria-current"] == "true" }
    assert_includes links.find { _1["aria-current"] }["class"], "active"
  end

  test "a gallery post shares its first photo" do
    @post.images.attach(io: File.open(file_fixture("tiny.png")), filename: "tiny.png", content_type: "image/png")

    image = page.at_css("meta[property='og:image']")["content"]
    assert_includes image, "tiny.png"
  end
end
