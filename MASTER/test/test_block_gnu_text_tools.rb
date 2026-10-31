# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"

# tools/block_gnu_text_tools.rb: a command that runs sed, awk, find, head, tail, wc, cut, tr, perl or python is
# refused with the Ruby or zsh replacement; the same words as data are not.
class TestBlockGnuTextTools < Minitest::Test
  HOOK = File.expand_path("../tools/block_gnu_text_tools.rb", __dir__)

  def call(command, tool: "Bash")
    payload = { "tool_name" => tool, "tool_input" => { "command" => command } }
    out, status = Open3.capture2e(RbConfig.ruby, HOOK, stdin_data: JSON.generate(payload))
    [status.exitstatus, out]
  end

  def test_each_banned_tool_is_refused_in_command_position
    commands = ["sed -n 1p file", "ls | head -3", "git log | tail -2", "x && wc -l y", "echo a | cut -c1",
                "find . -name x", "awk '{print}' f", "cat f | tr a b", "python3 -c 1", "perl -e 1",
                "ruby -e 1; sed s/a/b/ f", "(head x)", "$(tail y)"]

    commands.each { |command| assert_equal 2, call(command).first, command }
  end

  def test_the_refusal_names_the_replacement
    code, out = call("sed -i s/a/b/ file")

    assert_equal 2, code
    assert_match(/sed: .*Edit tool/, out)
  end

  # The old guard looked only after | ; & ( and so let these through, the remote one on 2026-10-22.
  def test_commands_behind_keywords_wrappers_and_ssh_are_refused
    ["for f in a; do wc -l $f; done", "ls | xargs sed -n 1p", "timeout 5 awk 1 f", "FOO=1 awk 1 f",
     "/usr/bin/sed -n 1p f", "zsh -c 'cut -c1 f'", "ssh dev@brgen.no 'sed -n 1,5p log'"].each do |command|
      assert_equal 2, call(command).first, command
    end
  end

  def test_the_same_words_as_data_are_let_through
    ["echo \"never use sed here\"", "git grep -n head -- lib", "ruby -e 'puts %w[a b].first(1)'", "ls headers/",
     "cat <<'EOF'\nsed -n 1p\nhead -3\nEOF", "git log --format=%s -1", "ruby -e 'x.find { |y| y }'"].each do |command|
      assert_equal 0, call(command).first, command
    end
  end

  def test_other_tools_and_unreadable_input_pass
    assert_equal 0, call("sed -n 1p f", tool: "Read").first
    assert_equal 0, Open3.capture2e(RbConfig.ruby, HOOK, stdin_data: "not json").last.exitstatus
  end

  # The fail-closed narrow subset: an unreadable payload or an unlexable
  # command that still carries a banned-tool invocation at command position is
  # refused, because there is no legitimate command left to protect once a
  # parser has refused the input.
  def test_an_unreadable_payload_carrying_a_banned_invocation_is_refused
    broken = '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ f"'
    out, status = Open3.capture2e(RbConfig.ruby, HOOK, stdin_data: broken)

    assert_equal 2, status.exitstatus
    assert_match(/unreadable/, out)
  end

  def test_an_unlexable_command_carrying_a_banned_invocation_is_refused
    # A real payload, a command whose quoting the lexer refuses but whose text
    # still names sed with a flag behind it.
    broken_command = "sed -n 'unterminated 1p f"
    payload = JSON.generate("tool_name" => "Bash", "tool_input" => { "command" => broken_command })
    out, status = Open3.capture2e(RbConfig.ruby, HOOK, stdin_data: payload)

    assert_equal 2, status.exitstatus, out
  end

  def test_an_unreadable_payload_without_a_banned_invocation_passes
    assert_equal 0, Open3.capture2e(
      RbConfig.ruby, HOOK, stdin_data: '{"tool_name":"Bash","tool_input":{"command":"ls -la"}'
    ).last.exitstatus
    assert_equal 0, Open3.capture2e(
      RbConfig.ruby, HOOK, stdin_data: '{"tool_name":"Bash"}'
    ).last.exitstatus
  end
end
