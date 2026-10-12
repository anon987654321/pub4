# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "open3"
require "tmpdir"

class TestRequireLawFirst < Minitest::Test
  HOOK = File.join(Master::ROOT, "tools", "require_law_first.rb")
  INSIDE = File.join(Master::ROOT, "README.md")

  def run_hook(event, session, input)
    payload = { "hook_event_name" => event, "session_id" => session, "tool_input" => input }
    Open3.capture3(RbConfig.ruby, HOOK, stdin_data: JSON.generate(payload))
  end

  def session = "test-#{Process.pid}-#{name}"

  def teardown = FileUtils.rm_f(File.join(Dir.tmpdir, "pub4-law-first-#{session.gsub(/\W/, "_")}"))

  def test_edit_in_a_checkout_is_refused_until_the_law_is_read
    _, err, status = run_hook("PreToolUse", session, { "file_path" => INSIDE })
    assert_equal 2, status.exitstatus
    assert_includes err, "agent_context.rb --tree"

    run_hook("PostToolUse", session, { "command" => "ruby MASTER/tools/agent_context.rb --tree" })
    _, _, status = run_hook("PreToolUse", session, { "file_path" => INSIDE })
    assert_equal 0, status.exitstatus
  end

  def test_the_law_card_counts_as_reading_the_law
    run_hook("PostToolUse", session, { "command" => "MASTER/bin/operator laws SINGULARITY --card" })
    _, _, status = run_hook("PreToolUse", session, { "file_path" => INSIDE })
    assert_equal 0, status.exitstatus
  end

  def test_a_write_outside_any_checkout_passes
    _, _, status = run_hook("PreToolUse", session, { "file_path" => File.join(Dir.tmpdir, "scratch.txt") })
    assert_equal 0, status.exitstatus
  end

  def test_unparseable_input_is_let_through
    _, _, status = Open3.capture3(RbConfig.ruby, HOOK, stdin_data: "not json")
    assert_equal 0, status.exitstatus
  end
end
