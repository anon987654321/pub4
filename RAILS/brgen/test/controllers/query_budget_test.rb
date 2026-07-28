# frozen_string_literal: true

require "test_helper"

# The home feed ran 243 queries for 25 posts. Four aggregates over the
# collection did it: Votable#score, #voted_by?, Post#comment_count and one
# ActiveStorage lookup per card. None of them were caught by
# strict_loading_by_default, because an aggregate on an association is a fresh
# query rather than an association load — `votes.sum(:value)` goes to the
# database even when :votes is already preloaded.
#
# A budget, not an exact count: the point is that adding a post must not add
# queries. The guard is that the count stays flat as the feed grows.
class QueryBudgetTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def count_queries
    seen = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, payload|
      next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])
      next if payload[:sql].include?("schema_migrations")

      seen += 1
    end
    yield
    seen
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  def seed_posts(count)
    author = User.strict_loading(false).create!(
      email_address: "budget-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", city: @city,
    )
    community = Community.create!(name: "Budget #{SecureRandom.hex(3)}", slug: "budget-#{SecureRandom.hex(4)}")

    count.times do |i|
      post = Post.create!(user: author, community:, title: "Budget #{i}", content: "…")
      Vote.create!(user: author, votable: post, value: 1)
      Comment.create!(user: author, commentable: post, content: "hi")
    end
  end

  test "the home feed does not spend queries per post" do
    ActsAsTenant.with_tenant(@city) do
      seed_posts(3)
      get root_path
      few = count_queries { get root_path }

      seed_posts(12)
      many = count_queries { get root_path }

      assert_operator many, :<=, few + 2,
                      "feed cost grew with the number of posts (#{few} -> #{many}): an N+1 is back"
    end
  end

  test "comment_count reads the counter cache rather than counting rows" do
    ActsAsTenant.with_tenant(@city) do
      seed_posts(1)
      post = Post.order(:id).last

      queries = count_queries { post.comment_count }

      assert_equal 0, queries, "comment_count must not query"
      assert_equal 1, post.comment_count
    end
  end

  # Votable is shared by every app, so this pins the behaviour at the concern.
  test "score and voted_by use the loaded association when there is one" do
    ActsAsTenant.with_tenant(@city) do
      seed_posts(1)
      author = User.order(:id).last
      post = Post.includes(:votes).order(:id).last

      queries = count_queries do
        post.score
        post.voted_by?(author)
        post.upvotes
      end

      assert_equal 0, queries, "aggregates must use the preloaded votes"
      assert_equal 1, post.score
    end
  end
end
