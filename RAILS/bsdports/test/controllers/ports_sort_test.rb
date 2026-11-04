# frozen_string_literal: true

require "test_helper"

# The Name/Updated chips rebuilt the URL from category_id alone, so changing
# the order of a search result dropped the search.
class PortsSortTest < ActionDispatch::IntegrationTest
  test "the sort chips keep the search query" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    Port.create!(platform:, category:, name: "git", version: "2.4", pkgpath: "devel/git")

    get ports_url(q: "git")
    assert_response :success
    assert_select "nav.sort-order a[href=?]", ports_path(q: "git")
    assert_select "nav.sort-order a[href=?]", ports_path(q: "git", sort: "updated")
  end
end
