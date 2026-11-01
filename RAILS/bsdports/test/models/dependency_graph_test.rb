# frozen_string_literal: true

require "test_helper"

class DependencyGraphTest < ActiveSupport::TestCase
  test "graph_for returns unique nodes and typed dependency edges" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "graph", slug: "graph", description: "graph")
    root = Port.create!(platform:, category:, name: "root", pkgpath: "graph/root", version: "1")
    middle = Port.create!(platform:, category:, name: "middle", pkgpath: "graph/middle", version: "1")
    leaf = Port.create!(platform:, category:, name: "leaf", pkgpath: "graph/leaf", version: "1")
    Dependency.create!(port: root, depends_on: middle, dep_type: "build")
    Dependency.create!(port: middle, depends_on: leaf, dep_type: "test")
    Dependency.create!(port: leaf, depends_on: root, dep_type: "run")

    graph = Dependency.graph_for(root)

    assert_equal 3, graph[:nodes].size
    assert_equal 3, graph[:edges].size
    assert_equal [ "build", "test", "run" ], graph[:edges].map { |edge| edge[:type] }
    assert_equal [ 0, 1, 2 ], graph[:nodes].map { |node| node[:depth] }
    assert_equal false, graph[:truncated]
  end

  test "graph_for stops at its depth limit" do
    platform = platforms(:openbsd)
    category = Category.create!(platform:, name: "graph-depth", slug: "graph-depth")
    chain = Array.new(8) do |index|
      Port.create!(platform:, category:, name: "node#{index}", pkgpath: "graph-depth/node#{index}", version: "1")
    end
    chain.each_cons(2) { |left, right| Dependency.create!(port: left, depends_on: right, dep_type: "run") }

    graph = Dependency.graph_for(chain.first)

    assert_equal 7, graph[:nodes].size
    assert_equal 6, graph[:nodes].map { |node| node[:depth] }.max
    assert graph[:truncated]
  end
end
