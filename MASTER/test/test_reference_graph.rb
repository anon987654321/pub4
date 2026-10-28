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

      assert_includes edges.map { |edge| edge[:to] }, "RAILS/tools/operator/deploy_paths.rb"
      refute_includes edges.map { |edge| edge[:to] }, "tools/operator/deploy_paths.rb"
    end
  end

  # File.binread returns nil at the end of an empty file; a .gitkeep crashed the whole /fix structure stage.
  def test_an_empty_file_does_not_crash_the_walk
    Dir.mktmpdir("reference-graph") do |root|
      FileUtils.mkdir_p(File.join(root, "MASTER", "data"))
      File.write(File.join(root, "MASTER", "data", ".gitkeep"), "")
      File.write(File.join(root, "MASTER", "a.rb"), "module A; end
")

      result = Master::Review::ReferenceGraph.new(root:).build

      assert result[:edges].is_a?(Array)
    end
  end

  # fix_loop and the stream stage both ask the graph whether a path has a node.
  def test_a_built_graph_answers_whether_a_path_has_a_node
    Dir.mktmpdir("reference-graph") do |root|
      File.write(File.join(root, "a.rb"), "module A; end\n")
      graph = Master::Review::ReferenceGraph.new(root:)
      graph.build

      assert graph.includes_path?(File.join(root, "a.rb"))
      refute graph.includes_path?(File.join(root, "missing.rb"))
    end
  end

  # Builds a graph over files given as name => source, and yields it with the root.
  def graph_of(files)
    Dir.mktmpdir("reference-graph") do |root|
      files.each { |name, source| File.write(File.join(root, name), source) }
      graph = Master::Review::ReferenceGraph.new(root:)
      graph.build
      yield graph, root
    end
  end

  # Master and Master::CLI are opened in hundreds of files. A reference to the scope is not a dependency on any
  # one of them; counted as one it linked every file to the whole tree and blocked every repair.
  def test_a_namespace_opened_in_many_files_is_not_a_dependency_on_each
    opened = (0..9).to_h { |n| ["ns_#{n}.rb", "module Ns\n  VALUE_#{n} = #{n}\nend\n"] }
    files = opened.merge("thing.rb" => "module Ns\n  class Thing; end\nend\n",
                         "scope_user.rb" => "puts Ns\n", "thing_user.rb" => "Ns::Thing.new\n")

    graph_of(files) do |graph, root|
      callers = graph.blast_radius(File.join(root, "thing.rb")).fetch(:inbound)

      assert_includes callers, "thing_user.rb", "a reference to the class is a dependency on its file"
      refute_includes callers, "scope_user.rb", "a reference to the scope is not"
    end
  end

  def test_a_class_split_over_two_files_depends_on_both
    files = { "part_a.rb" => "class Split\n  def a = 1\nend\n", "part_b.rb" => "class Split\n  def b = 2\nend\n",
              "user.rb" => "Split.new\n" }

    graph_of(files) do |graph, root|
      %w[part_a.rb part_b.rb].each do |part|
        assert_includes graph.blast_radius(File.join(root, part)).fetch(:inbound), "user.rb"
      end
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
      assert(result[:edges].any? do |edge|
        edge[:from] == "lib/jobs/persist.rb" &&
          edge[:to] == "lib/services/shared_service.rb" &&
          edge[:type] == :method_call
      end)
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

  def test_resolves_local_typescript_and_stylesheet_imports
    Dir.mktmpdir("reference-graph-imports") do |root|
      app = File.join(root, "src", "app.ts")
      component = File.join(root, "src", "shared.tsx")
      style = File.join(root, "src", "app.scss")
      tokens = File.join(root, "src", "tokens.scss")
      FileUtils.mkdir_p(File.dirname(app))
      File.write(app, "import { Shared } from \"./shared\";\nexport { Shared };\n")
      File.write(component, "export const Shared = 1;\n")
      File.write(style, '@use "./tokens";\n')
      File.write(tokens, "$space: 4px;\n")

      graph = Master::Review::ReferenceGraph.new(root:)
      result = graph.build
      imports = result[:edges].select { |edge| edge[:type] == :local_import }

      assert_includes imports.map { |edge| [edge[:from], edge[:to]] },
                      ["src/app.ts", "src/shared.tsx"]
      assert_includes imports.map { |edge| [edge[:from], edge[:to]] },
                      ["src/app.scss", "src/tokens.scss"]
      assert_empty result[:analysis_failures]
    end
  end

  def test_unresolved_local_import_is_a_gap_not_a_clean_dependency_list
    Dir.mktmpdir("reference-graph-unresolved-import") do |root|
      app = File.join(root, "src", "app.ts")
      FileUtils.mkdir_p(File.dirname(app))
      File.write(app, 'import { Missing } from "./missing";' + "\n")

      graph = Master::Review::ReferenceGraph.new(root:)
      result = graph.build
      unresolved = graph.unresolved_for(app)

      assert unresolved.any? { |reference| reference[:kind] == :import && reference[:name] == "./missing" }
      assert_equal 1, result.dig(:metrics, :unresolved_local_imports)
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
