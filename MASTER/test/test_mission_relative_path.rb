# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require_relative "../lib/fix/mission"

# 7fd5dd5748 wrote the traversal guard as /[\\/]/, which ends the regexp at its second slash: mission.rb
# stopped parsing, and every require of run_budget (so every /fix and most of the suite) raised.
class TestMissionRelativePath < Minitest::Test
  def mission = Master::Fix::Mission.allocate

  def test_a_path_inside_the_repository_is_answered_relative
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      File.write(File.join(root, "a.rb"), "x = 1\n")

      assert_equal "a.rb", mission.send(:repository_relative_path, "a.rb", root)
    end
  end

  def test_traversal_by_either_separator_is_refused
    Dir.mktmpdir do |root|
      root = File.realpath(root)
      bs = 92.chr

      File.write(File.join(root, "a.rb"), "x = 1\n")
      # A backslash is an ordinary name byte here, so this file exists and only the guard refuses it.
      File.write(File.join(root, "x#{bs}..#{bs}a.rb"), "x = 1\n")

      assert_nil mission.send(:repository_relative_path, "x/../a.rb", root)
      assert_nil mission.send(:repository_relative_path, "x#{bs}..#{bs}a.rb", root)
    end
  end
end
