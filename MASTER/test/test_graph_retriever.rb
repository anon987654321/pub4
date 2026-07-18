# frozen_string_literal: true

require_relative "test_helper"

# GraphRAG retrieval: multi-hop dependency neighbours ranked by proximity (decay per hop).
class TestGraphRetriever < Minitest::Test
  # Mirrors ReferenceGraph#blast_radius: takes an absolute path, returns relative neighbours.
  class FakeGraph
    def initialize(root, outbound)
      @root = root
      @outbound = outbound
    end

    def blast_radius(abs_path)
      rel = abs_path.sub("#{@root}/", "")
      { target: rel, inbound: [], outbound: @outbound.fetch(rel, []) }
    end
  end

  def test_ranks_neighbours_by_hop_distance
    root = "/repo"
    graph = FakeGraph.new(root, "a.rb" => ["b.rb"], "b.rb" => ["c.rb"])
    retriever = Master::Review::GraphRetriever.new(reference_graph: graph, root: root)

    result = retriever.neighbors(["#{root}/a.rb"], hops: 2)
    assert_equal %w[b.rb c.rb], result.first(2)
  end

  def test_excludes_seeds_and_caps_limit
    root = "/repo"
    graph = FakeGraph.new(root, "a.rb" => %w[b.rb c.rb d.rb])
    retriever = Master::Review::GraphRetriever.new(reference_graph: graph, root: root)

    result = retriever.neighbors(["#{root}/a.rb"], hops: 1, limit: 2)
    assert_equal 2, result.size
    refute_includes result, "a.rb"
  end
end
