# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# posts#show reads [post, "comments"]: a comment lands in place, a reply under
# its parent, and a deleted one leaves. The post's own stream only refreshes
# the page for what a re-render alone can show.
class CommentThreadBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @writer = User.strict_loading(false).create!(email_address: "thread-writer@brgen.no",
                                                 password: "password123", city: @city, username: "skribent")
    @post = Post.create!(user: @writer, city: @city, title: "Tråden", content: "Svar her")
    @post = Post.strict_loading(false).find(@post.id)
    @thread = [ @post, "comments" ]
  end

  teardown do
    Current.reset
    ActsAsTenant.current_tenant = nil
  end

  test "a comment lands at the end of the thread, rendered for nobody" do
    Current.user = @writer
    streams = capture_turbo_stream_broadcasts(@thread) do
      Comment.create!(user: @writer, commentable: @post, content: "<p>Første</p>")
    end
    append = streams.find { |stream| stream["action"] == "append" }

    assert append
    assert_equal "comments", append["target"]
    assert append.key?("data-viewer-neutral")
    html = append.at_css("template").inner_html
    assert_includes html, "Første"
    assert_not_includes html, "comment-delete", "the writer's delete button must not go to every reader"
    assert(streams.any? { |stream| stream["action"] == "remove" && stream["target"] == "comments_empty" })
  end

  test "a reply lands under its parent" do
    parent = Comment.create!(user: @writer, commentable: @post, content: "<p>Spørsmål</p>")
    streams = capture_turbo_stream_broadcasts(@thread) do
      Comment.create!(user: @writer, commentable: @post, content: "<p>Svar</p>", parent_id: parent.id)
    end
    append = streams.find { |stream| stream["action"] == "append" }

    assert_equal "replies_comment_#{parent.id}", append["target"]
  end

  test "a deleted comment leaves the thread, found by id as the controller finds it" do
    comment = Comment.create!(user: @writer, commentable: @post, content: "<p>Angrer</p>")
    found = Comment.find(comment.id)
    streams = capture_turbo_stream_broadcasts(@thread) { found.destroy! }

    assert(streams.any? { |stream| stream["action"] == "remove" && stream["target"] == "comment_#{comment.id}" })
  end

  test "a comment or a vote does not refresh the post page" do
    streams = capture_turbo_stream_broadcasts(@post) do
      Comment.create!(user: @writer, commentable: @post, content: "<p>Stille</p>")
      Vote.create!(user: @writer, votable: @post, value: 1)
    end

    assert_not_empty streams, "the counts still reach the page"
    assert(streams.none? { |stream| stream["action"] == "refresh" })
  end

  test "an edit refreshes the post page and the city's index" do
    assert_turbo_stream_broadcasts(@post) { @post.update!(title: "Tråden, rettet") }

    streams = capture_turbo_stream_broadcasts(Post.city_posts_stream(@city.id)) { @post.update!(content: "Ny tekst") }
    assert(streams.any? { |stream| stream["action"] == "refresh" })
  end
end
