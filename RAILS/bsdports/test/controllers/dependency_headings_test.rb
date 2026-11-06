# frozen_string_literal: true

require "test_helper"

# The dependency headings carried arrow glyphs ("Requires → dependencies"),
# which screen readers read out as "right arrow" in the middle of a heading.
class DependencyHeadingsTest < ActionDispatch::IntegrationTest
  test "dependency headings carry no arrow glyphs" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    git = Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git")
    gettext = Port.create!(platform:, category:, name: "gettext", version: "1", pkgpath: "devel/gettext")
    Dependency.create!(port: git, depends_on: gettext, dep_type: "build")

    [ git, gettext ].each do |port|
      get port_path(port)
      assert_response :success
      nodes = css_select("h2, section[aria-label], ul[aria-label]")
      headings = nodes.map { |node| node.text + node["aria-label"].to_s }
      assert_empty headings.grep(/[←→]/), "#{port.name} page has arrow glyphs in a heading"
    end
  end
end
