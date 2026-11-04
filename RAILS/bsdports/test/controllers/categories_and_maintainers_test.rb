# frozen_string_literal: true

require "test_helper"

# categories#index/show and maintainers#index/show had no controller test of
# their own: the listing, the counts, the port list and an empty search.
class CategoriesAndMaintainersTest < ActionDispatch::IntegrationTest
  setup do
    platform = platforms(:openbsd)
    @category = Category.create!(platform:, name: "net", slug: "net", description: "Networking")
    @maintainer = Maintainer.create!(name: "Kari Nordmann")
    @port = Port.create!(platform:, category: @category, name: "curl", version: "8", pkgpath: "net/curl",
                         maintainer_id: @maintainer.id)
  end

  test "the category index lists each category with its port count" do
    get categories_path
    assert_response :success
    assert_select "#categories li a[href=?]", category_path(@category), text: "net"
    assert_select "#categories li small", text: I18n.t("ports.port_count", count: 1)
  end

  test "a category page heads its ports with the category" do
    get category_path(@category)
    assert_response :success
    assert_select "h1", text: "net"
    assert_select "a[href=?]", port_path(@port), text: "curl"
  end

  test "a category search that matches nothing says so" do
    get categories_path(q: "zzzz-no-such-category")
    assert_response :success
    assert_select "#categories li", 0
    assert_includes response.body, I18n.t("empty.no_categories_search")
  end

  test "the maintainer index lists each maintainer with their port count" do
    get maintainers_path
    assert_response :success
    assert_select "#maintainers li a[href=?]", maintainer_path(@maintainer), text: "Kari Nordmann"
    assert_select "#maintainers li small", text: I18n.t("ports.port_count", count: 1)
  end

  test "a maintainer page lists the ports they maintain" do
    get maintainer_path(@maintainer)
    assert_response :success
    assert_select "h1", text: "Kari Nordmann"
    assert_select "#maintainer-ports a[href=?]", port_path(@port), text: "curl"
  end

  test "a maintainer search that matches nothing says so" do
    get maintainers_path(q: "zzzz-no-such-maintainer")
    assert_response :success
    assert_select "#maintainers li", 0
    assert_includes response.body, I18n.t("empty.no_maintainers_search")
  end
end
