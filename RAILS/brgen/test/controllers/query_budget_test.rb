# frozen_string_literal: true

require "test_helper"
require "base64"
require "stringio"

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

  # communities#show was the most expensive endpoint in the app: 816 queries and
  # a 3.5s p50 across 2,584 logged requests on 2026-08-01, worst case 110s. It
  # had drifted from the feed controllers in two ways at once — it preloaded
  # :user and :votes but not :community or the image attachment, and it
  # paginated nothing, so it rendered every post the community had ever held.
  # The count is what the missing LIMIT costs: a community holding a few hundred
  # posts pays a few queries for each of them.
  #
  # Which of these two tests carries the fix is worth being exact about, because
  # it is not symmetric. The pagination test below goes red the moment pagy is
  # removed. The repeat test does NOT independently catch dropping :community or
  # with_attached_image here — checked by reverting each — because inverse_of
  # already sets post.community when posts are loaded through the community, and
  # the ActiveStorage lookups stay under REPEAT_ALLOWANCE. So the preload change
  # is consistency with the sibling feeds rather than something pinned by a
  # failing test, and the pagination is what the measured win rests on. The
  # repeat check still earns its place as a guard against the next N+1 added to
  # this page.
  #
  # A 1x1 PNG: seeding a real attachment at least exercises the ActiveStorage
  # path rather than answering `post.image.attached?` from an empty preload.
  PIXEL_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  def attach_images_to(posts)
    posts.each_with_index do |post, i|
      post.image.attach(io: StringIO.new(PIXEL_PNG), filename: "p#{i}.png", content_type: "image/png")
    end
  end

  test "a community page does not repeat a query per post" do
    ActsAsTenant.with_tenant(@city) do
      seed_posts(12)
      community = Community.order(:id).last
      attach_images_to(community.posts.strict_loading(false).to_a)

      get community_path(community)
      assert_response :success

      repeats = repeated_shapes { get community_path(community) }
      assert_empty repeats.map { |sql, n| "#{n}x #{sql[0, 90]}" },
                   "one query per post on communities#show is the N+1 this endpoint was built with"
    end
  end

  test "a community page pages its posts instead of rendering all of them" do
    ActsAsTenant.with_tenant(@city) do
      seed_posts(30)
      community = Community.order(:id).last

      get community_path(community)
      assert_response :success

      # `assigns` is gone in Rails 8 without rails-controller-testing, so count
      # what actually reached the page: one distinct /posts/:slug per rendered card.
      # Posts are slug-routed now (Shared::Sluggable), e.g. /posts/budget-0.
      rendered = response.body.scan(%r{/posts/([a-z0-9][a-z0-9-]*)}).flatten.uniq.size
      assert_operator rendered, :<, 30,
                      "communities#show rendered all #{rendered} posts; it must paginate like the feeds"
      assert_operator rendered, :>, 0, "the page rendered no posts at all — the test proves nothing"
      assert_match(/[?&]page=2/, response.body,
                   "paging without a link to the next page makes older posts unreachable")
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

  # Every test above this one renders as a guest, and the layout's expensive work
  # is behind `if Current.user`. So the whole authenticated chrome — the unread
  # badge, the turbo_stream_from subscriptions, the push controller — was outside
  # this file's reach, and an N+1 lived there undisturbed: the badge summed
  # Conversation#unread_count_for over every DM, at 2 queries each, on every
  # render of every page. Signing in is the coverage that was missing, not the
  # assertion — reverting the fix takes the layout from 15 -> 15 queries to
  # 19 -> 35, and both tests below go red.
  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def seed_dms_for(user, count)
    count.times do |i|
      other = User.strict_loading(false).create!(
        email_address: "dm-#{i}-#{SecureRandom.hex(4)}@brgen.no",
        password: "password123", city: @city,
      )
      convo = Conversation.find_or_create_direct(user, other)
      2.times { |j| convo.messages.create!(content: "m#{j}", sender: other, message_type: "text") }
    end
  end

  test "signed-in chrome does not spend queries per conversation" do
    ActsAsTenant.with_tenant(@city) do
      seed_posts(3)
      me = User.strict_loading(false).create!(
        email_address: "chrome-#{SecureRandom.hex(4)}@brgen.no",
        password: "password123", city: @city,
      )
      sign_in(me)

      seed_dms_for(me, 2)
      get root_path
      assert_response :success
      few = count_queries { get root_path }

      seed_dms_for(me, 8)
      many = count_queries { get root_path }

      assert_operator many, :<=, few + 2,
                      "layout cost grew with DM count (#{few} -> #{many}): the unread badge N+1 is back"

      repeats = repeated_shapes { get root_path }
      assert_empty repeats.map { |sql, n| "#{n}x #{sql[0, 90]}" },
                   "a repeated query shape in authenticated chrome is an N+1"
    end
  end

  test "the messenger index does not spend queries per thread" do
    ActsAsTenant.with_tenant(@city) do
      me = User.strict_loading(false).create!(
        email_address: "msgr-#{SecureRandom.hex(4)}@brgen.no",
        password: "password123", city: @city,
      )
      sign_in(me)

      seed_dms_for(me, 2)
      get conversations_path
      assert_response :success
      few = count_queries { get conversations_path }

      seed_dms_for(me, 8)
      many = count_queries { get conversations_path }

      assert_operator many, :<=, few + 4,
                      "messenger index cost grew with thread count (#{few} -> #{many})"
    end
  end
end
