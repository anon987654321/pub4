# frozen_string_literal: true

require_relative "test_helper"

class TestOpenCrabsFeatures < Minitest::Test
  def test_hashline_format_and_validate
    lines = %W[foo\n bar\n]
    formatted = Master::Io::Hashline.format_lines(lines)
    assert_match(/\A1#[0-9a-f]{2}\tfoo/, formatted)

    id = Master::Io::Hashline.line_id("foo")
    anchor = Master::Io::Hashline.parse_anchor("1##{id}")
    content = lines.join
    assert Master::Io::Hashline.valid?(content, line_no: anchor[:line], id: anchor[:id])
  end

  def test_hashline_stale_anchor_rejects
    content = "alpha\nbeta\n"
    id = Master::Io::Hashline.line_id("alpha")
    result = Master::Io::Hashline.replace_line(content, line_no: 1, id: "ff", new_line: "gamma")
    assert result.err?
  end

  def test_output_filter_truncates_long_listing
    output = (1..60).map { |n| "line #{n}" }.join("\n")
    filtered = Master::Io::OutputFilter.filter(command: "ls -la", output:)
    assert filtered.bytesize < output.bytesize
    assert_includes filtered, "omitted"
  end

  def test_subagent_policy_excludes_recursive_tools
    assert Master::Ground::Policy::Subagent.excluded?("spawn_agent")
    assert Master::Ground::Policy::Subagent.excluded?("rebuild")
  end

  def test_subagent_policy_explore_allow_list
    names = Master::Ground::Policy::Subagent.allowed_tool_names(:explore, [])
    assert_includes names, "ReadFile"
    refute_includes names, "WriteFile"
  end

  # plan and explore promise "do not modify files" in their prompt; the allow
  # list is what keeps the promise when the model ignores it.
  def test_read_only_subagents_cannot_call_a_writing_tool
    %i[plan explore].each do |type|
      %w[WriteFile write_file StrReplace str_replace AstEdit ast_edit BatchReplace Shell zsh].each do |tool|
        refute Master::Ground::Policy::Subagent.allowed?(type, tool), "#{type} may call #{tool}"
      end
    end
  end

  # No phone-home. A version check or an analytics client added to lib/ or the
  # face would send the operator's usage somewhere nobody chose.
  TELEMETRY = /segment\.(io|com)|mixpanel|google-analytics|googletagmanager|sentry\.io|posthog|amplitude\.com|update[._-]check/i

  def test_nothing_phones_home
    files = Dir.glob(File.join(Master::ROOT, "{lib,web/app,web/config,bin}/**/*.{rb,js,erb}"))
    assert_operator files.size, :>, 100, "the glob found nothing to read"
    assert "https://www.google-analytics.com/collect".match?(TELEMETRY)
    hits = files.reject { |f| f.include?("/test") }.select { |f| File.read(f, encoding: "UTF-8").match?(TELEMETRY) }
    assert_empty hits.map { |f| f.delete_prefix(Master::ROOT + "/") }
  end

  def test_subagent_context_restricts_tools
    Master::CLI::SubagentContext.run(type: :explore, allowed: %w[ReadFile]) do
      assert Master::CLI::SubagentContext.permits?("ReadFile")
      refute Master::CLI::SubagentContext.permits?("WriteFile")
    end
    assert Master::CLI::SubagentContext.permits?("WriteFile")
  end

  # The brief names the list the react loop refuses against, not the type's
  # declared allow list, so a child is told exactly what a call can reach.
  def test_subagent_brief_names_the_tools_the_fiber_permits
    assert_nil Master::CLI::SubagentContext.brief

    Master::CLI::SubagentContext.run(type: :explore, allowed: %w[ReadFile]) do
      brief = Master::CLI::SubagentContext.brief
      assert_includes brief, "explore subagent"
      assert_includes brief, "only ReadFile"
    end
    Master::CLI::SubagentContext.run(type: :verify, allowed: []) do
      assert_includes Master::CLI::SubagentContext.brief, "no tools"
    end
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

  def test_swarm_role_maps_to_taxonomy
    assert_equal :explore, Master::Ground::Policy::Subagent.type_for_swarm_role(:analyst)
    assert_equal :research, Master::Ground::Policy::Subagent.type_for_swarm_role(:researcher)
    ctx = Master::Ground::Policy::Subagent.context_for_swarm_role(:reviewer, [])
    assert_equal :verify, ctx[:type]
    assert ctx[:allowed].is_a?(Array)
  end

  def test_skills_body_for_returns_description_fallback
    dir = Dir.mktmpdir("master-skill-")
    FileUtils.mkdir_p(File.join(dir, "data"))
    File.write(File.join(dir, "data", "patterns.yml"),
               "skills_registry:\n  skills:\n    - name: demo\n      description: demo skill\n      triggers: [\"fix loop\"]\n")
    skills = Master::CLI::Skills.new(root: dir)
    skills.discover!
    assert_equal "demo skill", skills.body_for("demo")
  ensure
    FileUtils.rm_rf(dir)
  end

  def test_agent_pool_capacity
    bus = Master::Trace::EventBus.new
    # The capacity under test is the taxonomy's, so it is stated here rather
    # than read from the file the assertion below depends on.
    pool = Master::Review::AgentPool.new(governor: nil, event_bus: bus,
      taxonomy: { "spawn_policy" => { "max_concurrent_children" => 4 } })
    hold = Queue.new
    4.times do |i|
      r = pool.spawn(type: :explore, tag: "t#{i}") { hold.pop }
      assert r.ok?, r.message if r.err?
    end
    r = pool.spawn(type: :explore, tag: "overflow") { true }
    assert r.err?
  ensure
    4.times { hold << true }
    pool&.join_all(timeout: 1)
  end
end
