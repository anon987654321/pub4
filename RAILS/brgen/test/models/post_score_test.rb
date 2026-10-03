# frozen_string_literal: true

require "test_helper"

# posts.score is a materialized sum, which means it can be wrong in a way an
# aggregate never could. These pin the two things that make it safe: the write
# path keeps it true, and the read path stops joining votes.
class PostScoreTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    ActsAsTenant.current_tenant = City.find_by!(domain: "brgen.no")
    @author = person("psc_author")
    @voter = person("psc_voter")
    @post = Post.create!(user: @author, title: "Score #{SecureRandom.hex(3)}")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def person(name)
    User.strict_loading(false).create!(
      email_address: "#{name}@brgen.no", password: "password123",
      username: "#{name}_#{SecureRandom.hex(2)}", guest: false
    )
  end

  test "an up-vote, a flip and a removal each move the score by the right amount" do
    assert_equal 0, @post.reload[:score]

    vote = Vote.create!(user: @voter, votable: @post, value: 1)
    assert_equal 1, @post.reload[:score]

    # The delta is -2, not -1: the arithmetic has to account for where the vote
    # was, not only where it landed. This is the case a naive counter gets wrong.
    vote.update!(value: -1)
    assert_equal(-1, @post.reload[:score])

    vote.destroy!
    assert_equal 0, @post.reload[:score]
  end

  # Shared::Votable#score is included by Comment and Takeaway::Review too, and
  # neither has the column. The concern has to answer for both.
  test "score reads the column on posts and the sum on comments" do
    Vote.create!(user: @voter, votable: @post, value: 1)
    assert_equal 1, @post.reload.score

    comment = Comment.create!(user: @author, commentable: @post, content: "hm")
    Vote.create!(user: @voter, votable: comment, value: 1)
    assert_not comment.class.column_names.include?("score"), "comments has no score column"
    assert_equal 1, comment.reload.score
  end

  test "ranking scopes no longer aggregate the votes table" do
    %i[hot top].each do |scope|
      sql = Post.public_send(scope).to_sql
      assert_not_includes sql.upcase, %(JOIN "VOTES"), "#{scope} should not join votes"
      assert_includes sql, "posts.score", "#{scope} should order by the column"
    end
  end

  # The column and the votes it summarises must agree. If they ever diverge the
  # feed ranks by a number nothing else believes.
  test "the materialized score agrees with the votes it stands for" do
    Vote.create!(user: @voter, votable: @post, value: 1)
    Vote.create!(user: @author, votable: @post, value: -1)

    assert_equal Vote.where(votable: @post).sum(:value), @post.reload[:score]
  end
end
