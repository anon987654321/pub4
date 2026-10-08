# frozen_string_literal: true

require "test_helper"

# The index actions paginated on 2026-08-10 (e4e1e1fe4), and the pager they all
# render.
#
# Written because that change had nothing watching it. Eleven controllers grew a
# `pagy(...)` call and eleven views grew a `render "shared/pager"`, verified by
# hand at the time and by nothing since — on a day when two other changes of mine
# broke and were caught by a peer rather than a suite.
#
# What these assert is the property the change was for: the page renders, and it
# renders a bounded number of rows. Not the pagy call, which is an implementation
# detail — a later move to a different paginator should keep these green.
class PaginatedIndexTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def user(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", city: @city,
    )
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  # A page of rows beyond one screenful, so an unpaginated action is visibly
  # different from a paginated one.
  OVERFLOW = 30

  test "bookmarks index paginates rather than rendering every bookmark" do
    ActsAsTenant.with_tenant(@city) do
      reader = user("bookmark-reader")
      author = user("bookmark-author")
      community = Community.create!(name: "Bm #{SecureRandom.hex(3)}", slug: "bm-#{SecureRandom.hex(4)}")

      OVERFLOW.times do |i|
        post = Post.create!(user: author, community:, title: "Post #{i}", content: "…")
        Bookmark.create!(user: reader, post:)
      end

      sign_in(reader)
      get saved_path

      assert_response :success

      # Counted in the response, not through assigns — that needs the
      # rails-controller-testing gem, and the rendered row count is the thing
      # that actually costs memory on a 1GB box.
      rendered = css_select(".post-feed > *").size
      assert_operator rendered, :>, 0, "the page rendered no posts at all"
      assert_operator rendered, :<, OVERFLOW,
                      "bookmarks#index rendered all #{OVERFLOW} bookmarks; this list only grows"
      assert_select "nav.pager", 1, "a truncated list must say there is more"
    end
  end

  test "the shared pager offers a next page and no dead previous link on page one" do
    ActsAsTenant.with_tenant(@city) do
      reader = user("pager-reader")
      author = user("pager-author")
      community = Community.create!(name: "Pg #{SecureRandom.hex(3)}", slug: "pg-#{SecureRandom.hex(4)}")

      OVERFLOW.times do |i|
        post = Post.create!(user: author, community:, title: "Paged #{i}", content: "…")
        Bookmark.create!(user: reader, post:)
      end

      sign_in(reader)
      get saved_path

      assert_response :success
      assert_select "nav.pager" do
        # page 1: a next link, and nothing pointing back past the first page.
        assert_select "a[rel=next]", 1
        assert_select "a[rel=prev]", 0, "page one must not offer a previous page"
      end
    end
  end

  # The pager is the one piece shared across three apps on two pagy majors. It
  # uses page/pages/next only; `prev` is `previous` in pagy 43 and would raise.
  test "the pager renders on a pagy 43 app without calling a pagy 9 helper" do
    ActsAsTenant.with_tenant(@city) do
      reader = user("major-reader")
      author = user("major-author")
      community = Community.create!(name: "Mj #{SecureRandom.hex(3)}", slug: "mj-#{SecureRandom.hex(4)}")

      OVERFLOW.times do |i|
        post = Post.create!(user: author, community:, title: "Major #{i}", content: "…")
        Bookmark.create!(user: reader, post:)
      end

      sign_in(reader)

      # pagy_nav does not exist on 43; if the pager ever reaches for it this
      # raises NoMethodError rather than rendering, which is the bug that shipped
      # in hashtags/show and went unnoticed because it needs a second page.
      assert_nothing_raised { get saved_path }
      assert_response :success
    end
  end

  test "an index with one page of results renders no pager at all" do
    ActsAsTenant.with_tenant(@city) do
      reader = user("single-reader")
      sign_in(reader)
      get saved_path

      assert_response :success
      assert_select "nav.pager", 0, "one page of results needs no pagination chrome"
    end
  end
end
