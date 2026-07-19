# frozen_string_literal: true

require_relative "test_helper"

class TestGraphCommand < Minitest::Test
  include Master

  def test_dispatch_graph_reports_blast_radius
    dir = Dir.mktmpdir
    File.write(File.join(dir, "a.rb"), "require_relative 'b'\n")
    File.write(File.join(dir, "b.rb"), "class B; end\n")

    graph = Review::ReferenceGraph.new(root: dir)
    index = Review::CodeIndex.new(root: dir)
    index.build

    output = CLI::CommandRegistry.dispatch_graph(root: dir, code_index: index, reference_graph: graph, ctx: { args: "a.rb" })
    assert_includes output, "graph a.rb"
    assert_includes output, "outbound"
  ensure
    FileUtils.rm_rf(dir)
  end
end
