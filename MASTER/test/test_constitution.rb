# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestConstitution < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("constitution_test")
    Master::Ground::Constitution.clear_cache!
  end

  def teardown
    FileUtils.remove_entry(@dir)
    Master::Ground::Constitution.clear_cache!
  end

  def test_instances_share_cached_snapshot_until_reload
    write_principle("first")
    first = Master::Ground::Constitution.new(dir: @dir)
    write_principle("second")
    second = Master::Ground::Constitution.new(dir: @dir)

    assert_includes first.system_prompt, "first"
    assert_includes second.system_prompt, "first"
    refute_includes second.system_prompt, "second"
  end

  def test_unreadable_principle_cannot_disappear_from_the_constitution
    write_principle("first")
    constitution = Master::Ground::Constitution.new(dir: @dir)
    File.write(File.join(@dir, "broken.md"), "\u0000")

    error = assert_raises(RuntimeError) { constitution.reload! }

    assert_match(/constitution principle unreadable|constitution unreadable/, error.message)
  end

  def test_reload_invalidates_cache_for_directory
    write_principle("first")
    constitution = Master::Ground::Constitution.new(dir: @dir)
    write_principle("second")

    constitution.reload!

    assert_includes constitution.system_prompt, "second"
  end

  def test_secret_veto_blocks_exec_argv_and_git_commit_messages
    pattern = /sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}/
    rule = Master::Core::Constitution.send(:no_secret_rule, { "secrets" => pattern })
    secret = "sk-#{'a' * 24}"

    exec_verdict = rule.judge.call(Master::Core::Effect.exec(["printf", secret]), nil)
    assert_instance_of Master::Core::Verdict::Block, exec_verdict
    assert_equal :no_secret, exec_verdict.by

    git_verdict = rule.judge.call(
      Master::Core::Effect.git(:commit, paths: ["README.md"], message: "publish #{secret}"),
      nil,
    )
    assert_instance_of Master::Core::Verdict::Block, git_verdict
    assert_nil rule.judge.call(Master::Core::Effect.exec(["printf", "safe text"]), nil)
  end

  def test_secret_veto_fails_closed_when_its_pattern_is_missing
    rule = Master::Core::Constitution.send(:no_secret_rule, {})
    verdict = rule.judge.call(Master::Core::Effect.exec(["true"]), nil)

    assert_instance_of Master::Core::Verdict::Block, verdict
    assert_equal :no_secret, verdict.by
    assert_match(/missing or invalid/, verdict.reason)
  end

  private

  def write_principle(body)
    File.write(File.join(@dir, "principle.md"), <<~MD)
      ---
      name: Test
      description: Cache test
      type: axiom
      ---
      #{body}
    MD
  end
end
