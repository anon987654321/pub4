# frozen_string_literal: true

require "test_helper"

# In-page <header> elements on the ports index and category pages said
# role="banner", so each page had two banners, and <nav> elements restated
# role="navigation", which they already have.
class LandmarkRolesTest < ActionDispatch::IntegrationTest
  test "pages have no in-page banner and no restated nav role" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    port = Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git")

    [ root_path, category_path(category), port_path(port) ].each do |path|
      get path
      assert_response :success
      assert_select "main [role=banner]", 0, path
      assert_select "nav[role=navigation]", 0, path
    end
  end
end
