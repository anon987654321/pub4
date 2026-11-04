# frozen_string_literal: true

require "test_helper"

# shared/_post_vote_rail with no reader at all (a request that never got a
# guest, or an app without guests): the score was a dead number. It is the way
# to sign in now, named for what signing in is for here.
class PostVoteRailTest < ActionView::TestCase
  teardown { Current.reset }

  test "a reader who cannot vote is offered sign-in from the score" do
    Current.user = nil
    post = Post.new(id: 41, title: "Stem")
    def post.score = 7

    render partial: "shared/post_vote_rail", locals: { post:, vote_path: "/posts/41/vote" }
    score = Nokogiri::HTML5.fragment(rendered).at_css(".post-vote-rail a.post-vote-score")

    refute_nil score, "the static score offers no sign-in"
    assert_equal new_session_path, score["href"]
    assert_equal "7", score.text.strip
    assert_equal I18n.t("post.sign_in_to_vote", score: 7), score["aria-label"]
  end

  test "with no vote path the score stays plain" do
    Current.user = nil
    post = Post.new(id: 42, title: "Stem")

    render partial: "shared/post_vote_rail", locals: { post:, vote_path: nil }

    assert_nil Nokogiri::HTML5.fragment(rendered).at_css("a.post-vote-score")
  end
end
