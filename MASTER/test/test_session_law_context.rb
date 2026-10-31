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

  def test_it_states_the_authority_order_and_the_lint_to_run
    code, out = run_hook({ "cwd" => File.join(REPO, "MASTER") })

    assert_equal 0, code
    assert_includes out, "soul.yml > MASTER/data/laws.yml"
    assert_includes out, "No hook refuses a tool call or a finish"
    assert_includes out, "lint --changed-lines"
    assert_match(/^  [A-Z_]+ \(\d+\): /, out, "the top-ranked laws are listed from laws.yml")
  end

  def test_it_is_silent_outside_a_checkout
    Dir.mktmpdir do |dir|
      code, out = run_hook({ "cwd" => dir })

      assert_equal 0, code
      assert_empty out
    end
  end

  def settings = JSON.parse(File.read(File.join(REPO, ".claude", "settings.json"))).fetch("hooks")

  def registered_commands
    settings.values.flatten.flat_map { |entry| entry.fetch("hooks") }.map { |hook| hook.fetch("command") }
  end

  # The briefing runs through hook_ruby.rb, which finds a Ruby that can parse it when the hook's PATH
  # holds only 2.6. No hook refuses a tool call or a finish (operator, 2026-10-31).
  def test_the_committed_settings_brief_the_session_and_block_nothing
    commands = registered_commands

    assert(commands.any? { |command| command.end_with?("hook_ruby.rb\" session_law_context") }, commands.inspect)
    assert_empty commands.grep(%r{MASTER/tools/(?!hook_ruby)\w+\.rb}), "no hook bypasses the launcher"
    refute_includes settings.keys, "PreToolUse", "no hook refuses a tool call"
  end
end
