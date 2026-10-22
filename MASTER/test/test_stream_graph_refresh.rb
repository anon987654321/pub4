# frozen_string_literal: true

require "digest"
require "tmpdir"
require_relative "test_helper"

# A file the run changed after the dependency graph was built rebuilds the graph once, rather
# than being parked for a person as "changed since dependency graph refresh".
class TestStreamGraphRefresh < Minitest::Test
  # Indexes files at their content as of the last build.
  class FakeGraph
    attr_reader :builds

    def initialize(paths)
      @paths = paths
      @builds = 0
      build(refresh: true)
      @builds = 0
    end

    def build(refresh:)
      @builds += 1 if refresh
      @digests = @paths.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] }
    end

    def includes_path?(path) = @digests.key?(path)
    def source_digest(path) = @digests[path]
  end

  # The stream stage's index check alone.
  class Stage
    include Master::Fix::FixLoop::PassRunner::StreamStage

    def indexed?(graph, path)
      digest = Digest::SHA256.file(path).hexdigest
      refresh_graph_for(graph, path) unless indexed_at?(graph, path, digest)
      indexed_at?(graph, path, digest)
    end
  end

  def test_a_changed_file_rebuilds_the_graph_once_and_is_indexed
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.rb").tap { |file| File.write(file, "A = 1\n") }
      graph = FakeGraph.new([path])
      stage = Stage.new
      sleep 0.01
      File.write(path, "A = 2\n")

      assert stage.indexed?(graph, path)
      assert stage.indexed?(graph, path)
      assert_equal 1, graph.builds
    end
  end

  def test_an_unchanged_file_does_not_rebuild
    Dir.mktmpdir do |dir|
      path = File.join(dir, "a.rb").tap { |file| File.write(file, "A = 1\n") }
      graph = FakeGraph.new([path])

      assert Stage.new.indexed?(graph, path)
      assert_equal 0, graph.builds
    end
  end
end
