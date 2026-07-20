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

  test "tree_for terminates on cyclic dependencies" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "cycle", slug: "cycle", description: "cycle")
    a = Port.create!(platform:, category:, name: "liba", pkgpath: "cycle/liba", comment: "a", version: "1")
    b = Port.create!(platform:, category:, name: "libb", pkgpath: "cycle/libb", comment: "b", version: "1")
    Dependency.create!(port: a, depends_on: b, dep_type: "run")
    Dependency.create!(port: b, depends_on: a, dep_type: "run")

    tree = Dependency.tree_for(a)
    assert_kind_of Array, tree
    assert_equal 1, tree.size
    assert_equal "run: libb", tree.first[:label]

    # Reverse edge appears once; seen set stops further expansion of a.
    cycle_back = tree.first[:children]
    assert_equal 1, cycle_back.size
    assert_equal "run: liba", cycle_back.first[:label]
    assert_equal [], cycle_back.first[:children]
  end
end
