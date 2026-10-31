# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "json"
require "open3"

class TestBlockGitStash < Minitest::Test
  HOOK = File.expand_path("../tools/block_git_stash.rb", __dir__)

  def call(command, cwd:, tool: "Bash")
    payload = JSON.generate("tool_name" => tool, "cwd" => cwd, "tool_input" => { "command" => command })
    _out, err, status = Open3.capture3(RbConfig.ruby, HOOK, stdin_data: payload)
    [status.exitstatus, err]
  end

  def git(dir, *args) = Open3.capture2e("git", "-c", "user.email=t@t", "-c", "user.name=t", "-C", dir, *args)

  def test_blocks_stash_writes_in_a_linked_worktree_and_explains_the_shared_list
    Dir.mktmpdir("stash-hook-") do |dir|
      main = File.join(dir, "main")
      linked = File.join(dir, "linked")
      Dir.mkdir(main)
      git(main, "init", "-q", "-b", "main")
      git(main, "commit", "-q", "--allow-empty", "-m", "seed")
      git(main, "worktree", "add", "-q", "-b", "other", linked)

      %w[push pop apply drop].each do |sub|
        code, err = call("git stash #{sub}", cwd: linked)
        assert_equal 2, code, sub
        assert_match(/share ONE stash list/, err)
      end
      assert_equal 2, call("git stash", cwd: main).first, "the main checkout also has a sibling worktree"
      assert_equal 2, call("cd x && git -C y stash push -m a", cwd: linked).first
      assert_equal 0, call("git stash list", cwd: linked).first
      assert_equal 0, call("git stash show", cwd: linked).first
      assert_equal 0, call("echo git stash pop", cwd: linked).first
      assert_equal 0, call("git stash pop", cwd: linked, tool: "Edit").first
    end
  end

  def test_a_lone_checkout_may_stash_and_bad_input_passes
    Dir.mktmpdir("stash-hook-") do |dir|
      git(dir, "init", "-q", "-b", "main")

      assert_equal 0, call("git stash pop", cwd: dir).first
      assert_equal 0, Open3.capture3(RbConfig.ruby, HOOK, stdin_data: "not json")[2].exitstatus
    end
  end

  # The fail-closed narrow subset: an unreadable payload that still carries a
  # writing stash call is refused, because there is no legitimate command left
  # to protect once the payload is unreadable.
  def test_an_unreadable_payload_carrying_a_writing_stash_call_is_refused
    broken = '{"tool_name":"Bash","cwd":"/x","tool_input":{"command":"git stash push -m wip"'
    _out, err, status = Open3.capture3(RbConfig.ruby, HOOK, stdin_data: broken)

    assert_equal 2, status.exitstatus
    assert_match(/unreadable/, err)
  end

  def test_an_unreadable_payload_broken_past_command_extraction_is_still_refused
    broken = '{"tool_name":"Bash" "git stash drop" true'
    _out, _err, status = Open3.capture3(RbConfig.ruby, HOOK, stdin_data: broken)

    assert_equal 2, status.exitstatus
  end

  def test_an_unreadable_payload_without_a_writing_stash_call_passes
    assert_equal 0, Open3.capture3(RbConfig.ruby, HOOK, stdin_data: "not json")[2].exitstatus
    assert_equal 0, Open3.capture3(
      RbConfig.ruby, HOOK,
      stdin_data: '{"tool_name":"Bash","tool_input":{"command":"git stash list"'
    )[2].exitstatus, "a read-only stash call rides the fail-open path"
    assert_equal 0, Open3.capture3(
      RbConfig.ruby, HOOK,
      stdin_data: '{"tool_name":"Bash","tool_input":{"command":"echo git stash push"'
    )[2].exitstatus, "an echo is data, on the unreadable path as on the readable one"
  end
end
