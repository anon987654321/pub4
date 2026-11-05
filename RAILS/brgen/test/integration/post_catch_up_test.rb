# frozen_string_literal: true

require "test_helper"

# A live page whose cable was down asks for what it missed: the front page for
# posts newer than the newest it holds, a post page for comments.
class PostCatchUpTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city

    @author = User.strict_loading(false).create!(email_address: "catch-up@brgen.no", password: "password123",
                                                 username: "innhenter", guest: false, city: @city)
    @seen = Post.create!(user: @author, city: @city, title: "Sett", content: "Allerede på siden")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def streams
    Nokogiri::HTML.fragment(response.body).css("turbo-stream")
  end

  test "the front page carries its high-water mark and watches its own stream" do
    get root_path

    assert_response :success
    assert_select "#feed-panel[data-feed-updates-since-url-value='#{posts_since_path}']"
    assert_select "#feed-panel[data-feed-updates-after-value='#{Post.maximum(:id)}']"
    assert_select "#feed-panel turbo-cable-stream-source[data-feed-updates-target=source]"
  end

  test "missed posts go to the pending chip, oldest first, never a private community's" do
    first = Post.create!(user: @author, city: @city, title: "Først", content: "Mens du sov")
    club = Community.create!(slug: "lukket-innhenting", name: "Lukket", user: @author, city: @city,
                             privacy: "private")
    Post.create!(user: @author, city: @city, community: club, title: "Hemmelig", content: "Bare medlemmer")
    second = Post.create!(user: @author, city: @city, title: "Så", content: "Fortsatt borte")

    get posts_since_path(after: @seen.id)

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert(streams.all? { |stream| stream["action"] == "prepend" && stream["target"] == "feed-pending" })
    frames = streams.map { |stream| stream.at_css("template turbo-frame")["id"] }
    assert_equal [ "post_#{first.id}", "post_#{second.id}" ], frames
  end

  # The chip counts only what the reader's feed would show, so a staged card
  # says where it is and whether it has media (feed_updates_controller#hidden).
  test "a missed post says its neighbourhood and whether it has media" do
    here = Neighborhood.create!(city: @city, name: "Sentrum", slug: "sentrum-innhenting")
    text = Post.create!(user: @author, city: @city, neighborhood: here, title: "Tekst", content: "Bare ord")

    get posts_since_path(after: @seen.id)

    frame = streams.first.at_css("template turbo-frame")
    assert_equal "post_#{text.id}", frame["id"]
    assert_equal here.id.to_s, frame["data-neighborhood-id"]
    assert_equal "false", frame["data-media"]
  end

  test "missed comments land where the stream would have put them" do
    question = Comment.create!(user: @author, commentable: @seen, content: "<p>Før</p>")
    answer = Comment.create!(user: @author, commentable: @seen, content: "<p>Etter</p>", parent_id: question.id)
    later = Comment.create!(user: @author, commentable: @seen, content: "<p>Senere</p>")

    get post_comments_since_path(@seen, after: question.id)

    assert_response :success
    appends = streams.select { |stream| stream["action"] == "append" }
    assert_equal [ "replies_comment_#{question.id}", "comments" ], appends.map { |stream| stream["target"] }
    assert_includes appends.first.to_html, "comment_#{answer.id}"
    assert_includes appends.last.to_html, "comment_#{later.id}"
  end

  test "a page with no comment yet gets the whole thread" do
    Comment.create!(user: @author, commentable: @seen, content: "<p>Første</p>")

    get post_comments_since_path(@seen, after: 0)

    assert(streams.any? { |stream| stream["action"] == "remove" && stream["target"] == "comments_empty" })
    assert(streams.any? { |stream| stream["action"] == "append" && stream["target"] == "comments" })
  end

  test "a private community's thread is not served to a stranger" do
    club = Community.create!(slug: "lukket-trad", name: "Lukket", user: @author, city: @city, privacy: "private")
    hidden = Post.create!(user: @author, city: @city, community: club, title: "Hemmelig tråd", content: "Nei")

    get post_comments_since_path(hidden, after: 0)

    assert_response :not_found
  end

  # The city stream is rendered for nobody, so a blocked person's new card
  # reaches the reader's pending list too; the page names whom to drop, each
  # card names its author, and the catch-up leaves them out on its own side.
  test "a blocked author's new posts stay out of the reader's new-posts chip" do
    reader = User.strict_loading(false).create!(email_address: "catch-reader@brgen.no", password: "password123",
                                                username: "leser_innhent", guest: false, city: @city)
    reader.block!(@author)
    post session_path, params: { email_address: reader.email_address, password: "password123" }

    neighbour = User.strict_loading(false).create!(email_address: "catch-nabo@brgen.no", password: "password123",
                                                   username: "nabo_innhent", guest: false, city: @city)
    shown = Post.create!(user: neighbour, city: @city, title: "Synlig", content: "Fra naboen")

    get root_path
    assert_select "#feed-panel[data-feed-updates-hidden-authors-value=?]", [ @author.id ].to_json
    assert_select "turbo-frame#post_#{shown.id}[data-author-id='#{neighbour.id}']"

    Post.create!(user: @author, city: @city, title: "Blokkert", content: "Skal ikke vises")
    get posts_since_path(after: shown.id)
    assert_response :success
    assert_empty streams
  end
end
