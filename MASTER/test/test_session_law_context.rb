# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "tmpdir"

# tools/session_law_context.rb puts the constitution in front of the agent at session start, and the three
# Claude Code hooks that mirror MASTER are registered in the committed settings.
class TestSessionLawContext < Minitest::Test
  HOOK = File.expand_path("../tools/session_law_context.rb", __dir__)
  REPO = File.expand_path("../..", __dir__)

  def run_hook(payload)
    out, status = Open3.capture2e(RbConfig.ruby, HOOK, stdin_data: JSON.generate(payload))
    [status.exitstatus, out]
  end

  def test_it_states_the_authority_order_and_the_guards
    code, out = run_hook({ "cwd" => File.join(REPO, "MASTER") })

    assert_equal 0, code
    assert_includes out, "soul.yml > MASTER/data/laws.yml"
    assert_includes out, "a turn cannot finish"
    assert_match(/^  [A-Z_]+ \(\d+\): /, out, "the top-ranked laws are listed from laws.yml")
  end

  def test_it_is_silent_outside_a_checkout
    Dir.mktmpdir do |dir|
      code, out = run_hook({ "cwd" => dir })

      assert_equal 0, code
      assert_empty out
    end
  end

  def registered_commands
    settings = JSON.parse(File.read(File.join(REPO, ".claude", "settings.json"))).fetch("hooks")
    settings.values.flatten.flat_map { |entry| entry.fetch("hooks") }.map { |hook| hook.fetch("command") }
  end

  def test_the_committed_settings_register_the_hooks_that_mirror_master
    commands = registered_commands

    # Through hook_ruby.rb, which finds a Ruby that can parse them when the hook's PATH holds only 2.6:
    # the briefing, the edit recorder and the Stop check.
    endings = ["session_law_context", "finish_check record", "finish_check"].map { |hook| "hook_ruby.rb\" #{hook}" }
    endings.each { |ending| assert_includes commands.map { |command| command[-ending.size..] }, ending }
    assert_empty commands.grep(%r{MASTER/tools/(?!hook_ruby)\w+\.rb}), "no hook bypasses the launcher"
  end
end
