# frozen_string_literal: true

require "test_helper"

# dependency_tree_test.rb covers tree_for, which is the recursive half. The
# record itself -- its type vocabulary, its uniqueness scope, and the label the
# tree renders -- had nothing.
#
# The uniqueness scope is the interesting one: [port_id, depends_on_id, dep_type]
# means one port may depend on another twice, once at build time and once at run
# time, which is correct and is exactly what a narrower scope would have broken.
class DependencyTest < ActiveSupport::TestCase
  setup do
    @platform = platforms(:openbsd)
    @category = Category.create!(platform: @platform, name: "devel", slug: "devel")
    @git = port("git")
    @gettext = port("gettext")
  end

  def port(name)
    Port.create!(platform: @platform, category: @category, name:, pkgpath: "devel/#{name}", version: "1")
  end

  test "the declared types are the ones accepted" do
    Dependency::TYPES.each do |type|
      assert Dependency.new(port: @git, depends_on: @gettext, dep_type: type).valid?, "#{type} was refused"
    end
    refute Dependency.new(port: @git, depends_on: @gettext, dep_type: "runtime").valid?
  end

  # A dependency with no stated type is a runtime dependency; the label says so.
  test "an untyped dependency is allowed and reads as a runtime one" do
    edge = Dependency.create!(port: @git, depends_on: @gettext)

    assert_nil edge.dep_type
    assert_equal "run: gettext", edge.label
  end

  test "the label names the type and the port it points at" do
    assert_equal "build: gettext", Dependency.new(port: @git, depends_on: @gettext, dep_type: "build").label
  end

  test "a label survives a missing target rather than raising" do
    assert_equal "build", Dependency.new(port: @git, dep_type: "build").label
  end

  # The scope is what makes a build-time and a run-time edge between the same
  # two ports two records rather than a conflict.
  test "one pair may be joined once per type" do
    Dependency.create!(port: @git, depends_on: @gettext, dep_type: "build")

    assert Dependency.new(port: @git, depends_on: @gettext, dep_type: "run").valid?,
           "a port can depend on another at build time and at run time"
    refute Dependency.new(port: @git, depends_on: @gettext, dep_type: "build").valid?
  end

  test "the direction matters" do
    Dependency.create!(port: @git, depends_on: @gettext, dep_type: "build")

    assert Dependency.new(port: @gettext, depends_on: @git, dep_type: "build").valid?,
           "a reverse edge is a different fact, however unlikely"
  end

  test "both ends are required" do
    refute Dependency.new(depends_on: @gettext).valid?
    refute Dependency.new(port: @git).valid?
  end

  test "runtime and buildtime select only their own kind" do
    build = Dependency.create!(port: @git, depends_on: @gettext, dep_type: "build")
    run = Dependency.create!(port: @git, depends_on: @gettext, dep_type: "run")
    Dependency.create!(port: @git, depends_on: port("zlib"), dep_type: "lib")

    assert_equal [ build ], Dependency.buildtime.to_a
    assert_equal [ run ], Dependency.runtime.to_a
  end

  # depth > 6 and a seen set are the two termination conditions, and only the
  # second has a test. A chain longer than the bound must stop rather than
  # recurse to the end of it.
  test "a chain deeper than the bound stops at the bound" do
    chain = (0..8).map { |i| port("lib#{i}") }
    chain.each_cons(2) { |a, b| Dependency.create!(port: a, depends_on: b, dep_type: "run") }

    depth = 0
    node = Dependency.tree_for(chain.first)
    while node.any?
      depth += 1
      node = node.first[:children]
    end

    assert_operator depth, :<=, 7, "the depth bound did not hold"
    assert_operator depth, :>, 1, "the walk stopped before it started"
  end

  test "a port with no dependencies has an empty tree rather than nil" do
    assert_equal [], Dependency.tree_for(@gettext)
  end

  test "every node in the tree carries what a view needs to render it" do
    Dependency.create!(port: @git, depends_on: @gettext, dep_type: "build")
    node = Dependency.tree_for(@git).first

    assert_equal %i[id label pkgpath children].sort, node.keys.sort
    assert_equal "devel/gettext", node[:pkgpath]
  end
end
