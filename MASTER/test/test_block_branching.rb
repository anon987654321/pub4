# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"

class TestBlockBranching < Minitest::Test
  HOOK = File.expand_path("../tools/block_branching.rb", __dir__)

  def call(command, tool: "Bash")
    payload = JSON.generate("tool_name" => tool, "tool_input" => { "command" => command })
    _out, err, status = Open3.capture3(RbConfig.ruby, HOOK, stdin_data: payload)
    [status.exitstatus, err]
  end

  def test_blocks_creating_worktrees_branches_and_pull_requests
    [
      "git worktree add ../x", "git -C /repo worktree add -b topic ../x", "git branch topic", "git checkout -b topic",
      "git switch -c topic", "git switch --create topic", "cd x && git checkout -B topic origin/main",
      "gh pr create --title t", "gh pr merge 12 --squash", "MASTER/bin/operator x; gh pr merge 3",
    ].each do |command|
      code, err = call(command)
      assert_equal 2, code, command
      assert_match(/straight to main/, err)
    end
  end

  def test_blocks_pushing_anything_but_main
    ["git push origin topic", "git push -u origin topic", "git push origin HEAD:topic", "git push origin main topic"].each do |command|
      assert_equal 2, call(command).first, command
    end
  end

  def test_allows_main_reading_and_cleanup
    [
      "git push", "git push origin main", "git push origin HEAD:main", "git push origin HEAD", "PUB4_PUSH_ALL=1 git push origin HEAD:main",
      "git worktree list", "git worktree remove ../x", "git worktree prune", "git branch", "git branch -a", "git branch -D topic",
      "git branch --show-current", "git checkout main", "git checkout -- file.rb", "git switch main", "git push origin --delete topic",
      "gh pr view 12", "gh pr list", "echo git worktree add", "git commit -m 'git branch topic'",
    ].each do |command|
      assert_equal 0, call(command).first, command
    end
  end

  def test_other_tools_and_bad_input_pass
    assert_equal 0, call("git worktree add x", tool: "Edit").first
    assert_equal 0, Open3.capture3(RbConfig.ruby, HOOK, stdin_data: "not json")[2].exitstatus
  end
end
