# frozen_string_literal: true

require_relative "test_helper"

class TestOpenCrabsFeatures < Minitest::Test
  def test_hashline_format_and_validate
    lines = ["foo\n", "bar\n"]
    formatted = Master::Reach::Hashline.format_lines(lines)
    assert_match(/\A1#[0-9a-f]{2}\tfoo/, formatted)

    id = Master::Reach::Hashline.line_id("foo")
    anchor = Master::Reach::Hashline.parse_anchor("1##{id}")
    content = lines.join
    assert Master::Reach::Hashline.valid?(content, line_no: anchor[:line], id: anchor[:id])
  end

  def test_hashline_stale_anchor_rejects
    content = "alpha\nbeta\n"
    id = Master::Reach::Hashline.line_id("alpha")
    result = Master::Reach::Hashline.replace_line(content, line_no: 1, id: "ff", new_line: "gamma")
    assert result.err?
  end

  def test_output_filter_truncates_long_listing
    output = (1..60).map { |n| "line #{n}" }.join("\n")
    filtered = Master::Reach::OutputFilter.filter(command: "ls -la", output:)
    assert filtered.bytesize < output.bytesize
    assert_includes filtered, "omitted"
  end

  def test_subagent_policy_excludes_recursive_tools
    assert Master::Ground::SubagentPolicy.excluded?("spawn_agent")
    assert Master::Ground::SubagentPolicy.excluded?("rebuild")
  end

  def test_subagent_policy_explore_allow_list
    names = Master::Ground::SubagentPolicy.allowed_tool_names(:explore, [])
    assert_includes names, "ReadFile"
    refute_includes names, "WriteFile"
  end

  def test_subagent_context_restricts_tools
    Master::Ground::SubagentContext.run(type: :explore, allowed: %w[ReadFile]) do
      assert Master::Ground::SubagentContext.permits?("ReadFile")
      refute Master::Ground::SubagentContext.permits?("WriteFile")
    end
    assert Master::Ground::SubagentContext.permits?("WriteFile")
  end

  def test_phantom_repetition_detector
    span = "x" * 60
    text = ([span] * 4).join(" ")
    assert Master::PhantomRecovery.repetition_loop?(text)
    refute Master::PhantomRecovery.repetition_loop?("short text")
  end

  def test_active_plan_pin_and_read
    dir = Dir.mktmpdir("master-plan-")
    root = dir
    Master::Ground::ActivePlan.pin(root, "- step one\n- step two")
    body = Master::Ground::ActivePlan.read(root)
    assert_includes body, "step one"
    section = Master::Ground::ActivePlan.prompt_section(root)
    assert_includes section, "Active plan"
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_agent_pool_capacity
    bus = Master::Trace::EventBus.new
    pool = Master::Judge::AgentPool.new(governor: nil, event_bus: bus,
      taxonomy_path: File.join(Master::ROOT, "data", "agent_taxonomy.yml"))
    4.times do |i|
      r = pool.spawn(type: :explore, tag: "t#{i}") { sleep 0.05 }
      assert r.ok?, r.message if r.err?
    end
    r = pool.spawn(type: :explore, tag: "overflow") { true }
    assert r.err?
    pool.join_all(timeout: 1)
  end
end