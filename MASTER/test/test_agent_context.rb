# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../tools/agent_context"

class TestAgentContext < Minitest::Test
  def test_shell_contract_names_the_runtime_primitives
    text = Operator::AgentContext.shell_contract.join("\n")

    assert_includes text, "zsh"
    assert_includes text, "Master::Io::Exec"
    assert_includes text, "first pass on an unfamiliar or broad tree"
  end

  def test_tree_mode_skips_runtime_noise
    Dir.mktmpdir("agent-tree") do |root|
      FileUtils.mkdir_p(File.join(root, "src", "nested"))
      FileUtils.mkdir_p(File.join(root, "node_modules", "noise"))
      File.write(File.join(root, "src", "main.rb"), "puts 1\n")
      File.write(File.join(root, "src", "nested", "deep.rb"), "puts 2\n")

      output = Operator::AgentContext.render_tree(root:, max_depth: 4, max_entries: 10)

      assert_includes output, "src/"
      assert_includes output, "main.rb"
      assert_includes output, "deep.rb"
      refute_includes output, "node_modules"
    end
  end

  def test_tree_mode_respects_the_entry_limit
    Dir.mktmpdir("agent-tree") do |root|
      10.times { |i| File.write(File.join(root, "file#{i}.rb"), "puts #{i}\n") }

      output = Operator::AgentContext.render_tree(root:, max_depth: 4, max_entries: 3)

      assert_includes output, "entries shown: 3"
      assert_includes output, "max entries reached"
    end
  end
end
