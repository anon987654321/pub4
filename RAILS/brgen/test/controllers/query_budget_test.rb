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

  # A stronger, cheaper guard than a per-page number: an N+1 is by definition
  # the same query shape repeated, so normalise binds and look for repeats. This
  # caught 20 ActiveStorage lookups on tv and 14 city lookups on takeaway, both
  # of which a per-page budget would have had to be told about in advance.
  REPEAT_ALLOWANCE = 2

  def repeated_shapes
    shapes = Hash.new(0)
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, _s, _f, _i, payload|
      next if payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])
      next if payload[:sql].include?("schema_migrations")

      shapes[payload[:sql].gsub(/\d+/, "?").gsub(/'[^']*'/, "?").squeeze(" ")] += 1
    end
    yield
    shapes.select { |_, n| n > REPEAT_ALLOWANCE }
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end

  # Each vertical needs rows before this can prove anything: with an empty table
  # there is nothing to repeat over, and the assertion passes for the wrong
  # reason. Checked by reintroducing takeaway's N+1 — with no restaurants seeded
  # the test stayed green, which is exactly the failure mode a coverage test
  # must not have.
  def seed_vertical_rows(count)
    owner = User.strict_loading(false).create!(
      email_address: "vertical-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", city: @city,
    )
    channel = Tv::Channel.create!(user: owner, name: "Ch #{SecureRandom.hex(3)}", slug: "ch-#{SecureRandom.hex(4)}")

    count.times do |i|
      # active is a nullable boolean with no schema default, and the index
      # scopes to where(active: true) — seeds without it render an empty page,
      # which is how the first version of this test passed while the N+1 it was
      # written for was still present.
      Takeaway::Restaurant.create!(
        user: owner, name: "Kro #{i}-#{SecureRandom.hex(2)}", address: "Storgata #{i}",
        cuisine_type: "nordic", city: @city, active: true,
      )
      Tv::Video.create!(user: owner, channel:, title: "Video #{i}")
    end
  end

  test "no vertical index repeats a query per row" do
    ActsAsTenant.with_tenant(@city) do
      seed_posts(6)
      seed_vertical_rows(6)

      { "brgen.no" => "/", "tv.brgen.no" => "/", "takeaway.brgen.no" => "/" }.each do |vhost, path|
        host! vhost
        get path
        assert_response :success, "#{vhost}#{path} did not render"

        repeats = repeated_shapes { get path }
        assert_empty repeats.map { |sql, n| "#{vhost}: #{n}x #{sql[0, 80]}" },
                     "one query per row is an N+1"
      end
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
