# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# /posts: the sort tabs say which is chosen, and the communities aside reads
# the cached popular list rather than querying on every render.
class PostsIndexMarkupTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def current_tabs(path)
    get path
    assert_response :success
    Nokogiri::HTML(response.body).css("nav.sort-tabs a[aria-current=true]").map { _1["href"] }
  end

  test "the active sort tab is marked current" do
    assert_equal [ posts_path ], current_tabs(posts_path)
    assert_equal [ posts_path(sort: "top") ], current_tabs(posts_path(sort: "top"))
  end

  test "the heading class names a role, not a look" do
    get posts_path

    assert_select "h1.primary-title", text: I18n.t("pages.all_posts")
  end

  test "the communities aside reads the cached popular list" do
    called = false
    original = Community.method(:popular_cached)
    spy = lambda do |**options|
      called = true
      original.call(**options)
    end

    Community.stub(:popular_cached, spy) { get posts_path }
    assert called, "/posts queried communities directly instead of Community.popular_cached"
  end
end
