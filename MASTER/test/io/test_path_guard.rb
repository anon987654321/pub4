# frozen_string_literal: true

require "test_helper"

class PathGuardTest < Minitest::Test
  def setup
    @root = Master::ROOT
    @tool = Class.new do
      include Master::Io::PathGuard
      def initialize(root) = @root = root
    end.new(@root)
  end

  def test_rejects_prefix_escape_paths
    result = @tool.resolve("#{@root}_evil/secret.txt")
    assert result.err?
    assert_match(/escapes project root/, result.message)
  end

  def test_accepts_paths_inside_root
    result = @tool.resolve("lib/io/path_guard.rb")
    assert result.ok?
    assert result.value!.start_with?(@root)
  end
end
