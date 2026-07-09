# frozen_string_literal: true

require "test_helper"

class DependencyTreeTest < ActiveSupport::TestCase
  test "tree_for returns nested nodes without infinite recursion" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "devel", slug: "devel", description: "devel")
    git = Port.create!(platform:, category:, name: "git", pkgpath: "devel/git", comment: "git", version: "1")
    gettext = Port.create!(platform:, category:, name: "gettext", pkgpath: "devel/gettext", comment: "gettext", version: "1")
    Dependency.create!(port: git, depends_on: gettext, dep_type: "build")

    tree = Dependency.tree_for(git)
    assert_kind_of Array, tree
    assert_equal "build: gettext", tree.first[:label]
    assert tree.first[:children].is_a?(Array)
  end
end