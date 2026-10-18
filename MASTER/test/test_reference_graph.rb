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

  def test_prism_connects_a_static_method_caller_to_its_definition_file
    Dir.mktmpdir("reference-graph-ast") do |root|
      caller = File.join(root, "lib", "jobs", "persist.rb")
      shared = File.join(root, "lib", "services", "shared_service.rb")
      FileUtils.mkdir_p(File.dirname(caller))
      FileUtils.mkdir_p(File.dirname(shared))
      File.write(shared, <<~RUBY)
        module Services
          class SharedService
            def save
              true
            end
          end
        end
      RUBY
      File.write(caller, <<~RUBY)
        module Jobs
          class Persist
            def run
              Services::SharedService.new.save
            end
          end
        end
      RUBY

      graph = Master::Review::ReferenceGraph.new(root:)
      result = graph.build
      radius = graph.blast_radius(shared)

      assert_includes radius[:inbound], "lib/jobs/persist.rb"
      assert result[:edges].any? do |edge|
        edge[:from] == "lib/jobs/persist.rb" &&
          edge[:to] == "lib/services/shared_service.rb" &&
          edge[:type] == :method_call
      end
      assert_equal Digest::SHA256.hexdigest(File.read(shared)), graph.source_digest(shared)
      assert_empty result[:analysis_failures]
    end
  end

  def test_dynamic_dispatch_is_recorded_instead_of_misread_as_a_literal
    Dir.mktmpdir("reference-graph-dynamic") do |root|
      path = File.join(root, "lib", "dynamic.rb")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, <<~RUBY)
        class DynamicRunner
          def run(object, method_name)
            object.send(method_name)
          end
        end
      RUBY

      graph = Master::Review::ReferenceGraph.new(root:)
      result = graph.build

      assert_equal 1, graph.dynamic_for(path).size
      assert_equal "dynamic method name", graph.dynamic_for(path).first[:reason]
      assert_equal 1, result.dig(:metrics, :dynamic_sites)
    end
  end

  def test_refresh_reports_invalid_ruby_source_as_an_analysis_gap
    Dir.mktmpdir("reference-graph-invalid") do |root|
      path = File.join(root, "broken.rb")
      File.write(path, "def incomplete(\n")

      graph = Master::Review::ReferenceGraph.new(root:)
      result = graph.build(refresh: true)

      assert_includes result[:nodes], "broken.rb"
      assert result[:analysis_failures].any? { |failure| failure[:path] == "broken.rb" }
    end
  end
end
