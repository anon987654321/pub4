# frozen_string_literal: true

require "test_helper"

# The dependency tree claimed role=tree / treeitem / group with no
# aria-expanded or keyboard handling behind it, and its nodes were plain
# text with no way to reach the dependency's own page.
class DependencyTreeMarkupTest < ActionDispatch::IntegrationTest
  test "the tree is plain nested lists whose nodes link to their ports" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel")
    git = Port.create!(platform:, category:, name: "git", version: "2.45", pkgpath: "devel/git")
    gettext = Port.create!(platform:, category:, name: "gettext", version: "1", pkgpath: "devel/gettext")
    Dependency.create!(port: git, depends_on: gettext, dep_type: "build")

    get port_path(git)
    assert_response :success
    assert_select "[role=tree], [role=treeitem], [role=group]", 0
    assert_select "section[aria-label=?] li a[href=?]", I18n.t("ports.tree_heading"), port_path(gettext)
  end
end
