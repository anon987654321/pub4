# frozen_string_literal: true

require "test_helper"

# posts#show loads every root comment with includes(replies: [:user, :votes]),
# and comment_children used to ask the database for each root's replies again.
# The thread reads the loaded replies now, in the same best-first order and
# through the same blocked-author and removed filters.
class CommentPreloadedRepliesTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"

    @author = make_user("preload-author")
    @post = Post.create!(user: @author, city: @city, title: "Tråd", content: "…")
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def make_user(prefix)
    User.strict_loading(false).create!(email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
                                       username: "#{prefix.tr("-", "_")}_#{SecureRandom.hex(3)}",
                                       password: "password123", city: @city)
  end

  def reply_queries_for(ids)
    seen = []
    callback = lambda do |*, payload|
      next unless payload[:sql].include?('"comments"."parent_id" = ')

      values = Array(payload[:type_casted_binds]).map { _1.respond_to?(:value) ? _1.value : _1 }
      seen << payload[:sql] if (values & ids).any? || ids.any? { |id| payload[:sql].include?("= #{id}") }
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    seen
  end

  test "the post page asks no per-root query for replies it already loaded" do
    roots = Array.new(3) { |n| Comment.create!(user: @author, commentable: @post, content: "root #{n}") }
    roots.each do |root|
      2.times { |n| Comment.create!(user: @author, commentable: @post, content: "svar #{n}", parent_id: root.id) }
    end

    queries = reply_queries_for(roots.map(&:id)) { get post_path(@post) }

    assert_response :success
    roots.each { |root| assert_select "#replies_comment_#{root.id} > turbo-frame", 2 }
    assert_empty queries, "re-queried replies: #{queries.first}"
  end

  test "loaded replies keep best-first order and drop removed and blocked authors" do
    reader = make_user("preload-reader")
    blocked = make_user("preload-blocked")
    reader.block!(blocked)
    root = Comment.create!(user: @author, commentable: @post, content: "root")
    quiet = Comment.create!(user: @author, commentable: @post, content: "stille svar", parent_id: root.id)
    liked = Comment.create!(user: @author, commentable: @post, content: "likt svar", parent_id: root.id)
    Vote.create!(user: reader, votable: liked, value: 1)

    Comment.create!(user: @author, commentable: @post, content: "fjernet svar", parent_id: root.id,
                    removed_at: Time.current)
    Comment.create!(user: blocked, commentable: @post, content: "blokkert svar", parent_id: root.id)

    post session_path, params: { email_address: reader.email_address, password: "password123" }
    get post_path(@post)

    assert_response :success
    ids = css_select("#replies_comment_#{root.id} > turbo-frame").map { _1["id"] }
    assert_equal [ "comment_#{liked.id}", "comment_#{quiet.id}" ], ids
  end
end
