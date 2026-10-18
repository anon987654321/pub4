# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "test_helper"
require_relative "../lib/review/reference_graph"

class TestReferenceGraph < Minitest::Test
  def test_resolves_require_relative_from_the_callers_directory
    Dir.mktmpdir("reference-graph") do |root|
      caller = File.join(root, "RAILS", "brgen", "config", "boot.rb")
      shared = File.join(root, "RAILS", "tools", "operator", "deploy_paths.rb")
      FileUtils.mkdir_p(File.dirname(caller))
      FileUtils.mkdir_p(File.dirname(shared))
      File.write(caller, 'require_relative "../../tools/operator/deploy_paths"' + "\n")
      File.write(shared, "module Operator; end\n")

      graph = Master::Review::ReferenceGraph.new(root:)
      result = graph.build
      edges = result[:edges].select { |edge| edge[:from] == "RAILS/brgen/config/boot.rb" && edge[:type] == :require }

      assert_includes edges.map { |edge| edge[:to] }, "MASTER/tools/rails/operator/deploy_paths.rb"
      refute_includes edges.map { |edge| edge[:to] }, "tools/operator/deploy_paths.rb"
    end
  end

  def test_blast_radius_uses_the_resolved_cross_tree_edge
    Dir.mktmpdir("reference-graph") do |root|
      caller = File.join(root, "RAILS", "brgen", "app.rb")
      shared = File.join(root, "RAILS", "shared", "app.rb")
      FileUtils.mkdir_p(File.dirname(caller))
      FileUtils.mkdir_p(File.dirname(shared))
      File.write(caller, 'require_relative "../shared/app"' + "\n")
      File.write(shared, "module Shared; end\n")

      graph = Master::Review::ReferenceGraph.new(root:)
      graph.build

      radius = graph.blast_radius(shared)

      assert_includes radius[:inbound], "RAILS/brgen/app.rb"
    end
  end


  def test_indexes_extensionless_text_sources_and_is_idempotent_until_refreshed
    Dir.mktmpdir("reference-graph") do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "Rakefile"), 'require_relative "lib/app"' + "\n")
      File.write(File.join(root, "lib", "app.rb"), "module App; end\n")

      graph = Master::Review::ReferenceGraph.new(root:)
      first = graph.build
      second = graph.build

      assert_includes first[:nodes], "Rakefile"
      assert_includes first[:edges].map { |edge| edge[:from] }, "Rakefile"
      assert_equal first[:edges].size, second[:edges].size
      refute first[:analysis_failures].any?

      File.write(File.join(root, "Rakefile"), "# changed without a dependency\n")
      refreshed = graph.build(refresh: true)
      assert_empty refreshed[:edges].select { |edge| edge[:from] == "Rakefile" }
    end
  end
end
