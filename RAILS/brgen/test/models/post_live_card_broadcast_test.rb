# frozen_string_literal: true

require "test_helper"
require "turbo/broadcastable/test_helper"

# A card on an open front page follows its post: the score on a vote, the
# comment count on a comment, the text on an edit, and the card goes on a
# deletion or a takedown. Nothing sent to the city stream may carry one
# reader's state to another.
class PostLiveCardBroadcastTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    @author = User.strict_loading(false).create!(email_address: "live-card-author@brgen.no",
                                                 password: "password123", city: @city)
    @voter = User.strict_loading(false).create!(email_address: "live-card-voter@brgen.no",
                                                password: "password123", city: @city)
    @post = Post.create!(user: @author, city: @city, title: "Levende kort", content: "Tellerne følger med")
    # As a request finds it: a fresh read carries no changes from its own creation.
    @post = Post.strict_loading(false).find(@post.id)
    @stream = Post.city_feed_stream(@city.id)
  end

  teardown do
    Current.reset
    ActsAsTenant.current_tenant = nil
  end

  test "a vote sends the new score to the front page and to the post's own page" do
    streams = capture_turbo_stream_broadcasts(@stream) { Vote.create!(user: @voter, votable: @post, value: 1) }
    score = streams.find { |stream| stream["targets"] == %([data-post-score="post_#{@post.id}"]) }

    assert score, "no score update on the city stream"
    assert_equal "update", score["action"]
    assert_equal "1", score.at_css("template").inner_html.strip
    assert_turbo_stream_broadcasts(@post) { Vote.create!(user: @author, votable: @post, value: 1) }
  end

  test "a comment and its deletion send the comment count" do
    comment = nil
    added = capture_turbo_stream_broadcasts(@stream) do
      comment = Comment.create!(user: @voter, commentable: @post, content: "<p>Enig</p>")
    end
    assert_equal "1", count_update(added)

    removed = capture_turbo_stream_broadcasts(@stream) { comment.destroy! }
    assert_equal "", count_update(removed)
  end

  test "an edit sends the card rendered for nobody, marked so" do
    Current.user = @voter
    streams = capture_turbo_stream_broadcasts(@stream) { @post.update!(title: "Rettet tittel") }
    card = streams.find { |stream| stream["action"] == "replace" }

    assert card, "no card replacement on an edit"
    assert card.key?("data-viewer-neutral")
    assert_equal "post_#{@post.id}", card["target"]
    html = card.at_css("template").inner_html
    assert_includes html, "Rettet tittel"
    assert_not_includes html, "post-vote-button", "a card for the stream must not carry the editor's vote buttons"
  end

  test "a vote does not resend the card" do
    streams = capture_turbo_stream_broadcasts(@stream) { Vote.create!(user: @voter, votable: @post, value: 1) }

    assert(streams.none? { |stream| stream["action"] == "replace" })
  end

  test "a deleted post leaves the chip and the feed" do
    streams = capture_turbo_stream_broadcasts(@stream) { @post.destroy! }
    removal = streams.find { |stream| stream["action"] == "remove" }

    assert removal
    assert_equal "#feed-pending > #post_#{@post.id}, li:has(> #post_#{@post.id})", removal["targets"]
  end

  test "a moderator's takedown leaves the feed though it runs no callback" do
    report = Struct.new(:reportable).new(@post)
    workflow = ModerationWorkflow.allocate
    workflow.define_singleton_method(:subject_for, &:reportable)

    streams = capture_turbo_stream_broadcasts(@stream) { workflow.send(:remove_content, report) }

    assert(streams.any? { |stream| stream["action"] == "remove" })
  end

  test "a resolved link embed sends the card" do
    streams = capture_turbo_stream_broadcasts(@stream) { @post.link_embed_resolved }

    assert(streams.any? { |stream| stream["action"] == "replace" && stream.key?("data-viewer-neutral") })
  end

  test "a post in a private community changes nothing on the city stream" do
    club = Community.create!(slug: "lukket-live", name: "Lukket", user: @author, city: @city, privacy: "private")
    hidden = Post.create!(user: @author, city: @city, community: club, title: "Hemmelig", content: "Bare medlemmer")

    streams = capture_turbo_stream_broadcasts(@stream) do
      Vote.create!(user: @voter, votable: hidden, value: 1)
      hidden.update!(title: "Fortsatt hemmelig")
      hidden.destroy!
    end
    assert_empty streams.map(&:to_html)
  end

  private

  def count_update(streams)
    update = streams.find { |stream| stream["targets"] == %([data-post-comment-count="post_#{@post.id}"]) }
    assert update, "no comment count update"
    update.at_css("template").inner_html.strip
  end
end
