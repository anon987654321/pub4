# frozen_string_literal: true

require_relative "test_helper"

class TestRepligenDispatch < Minitest::Test
  class FakeAgent
    def ask_once(seed, system:)
      "Cinematic #{seed} with dolly motion and golden hour light."
    end

    def ask(seed, system:, image: nil)
      ask_once(seed, system: system)
    end
  end

  def test_script_dispatch_missing_tool
    result = Master::Reach::ScriptDispatch.run(root: Master::ROOT, tool: "no_such_tool", arg: "")
    refute result.ok?
    assert_includes result.message, "missing tool entrypoint"
  end

  def test_repligen_call_uses_tools_wrapper_not_deploy_direct
    tool = Master::Reach::Repligen.new(root: Master::ROOT, agent: FakeAgent.new)
    script = File.join(Master::ROOT, "tools", "repligen.rb")
    assert File.file?(script), "expected tools/repligen.rb wrapper"

    arg = "generate #{Master::Reach::RepligenArg::DEFAULT_VIDEO_MODEL} mist over pier"
    refined = Master::Reach::RepligenArg.refine_generate(arg, agent: tool.instance_variable_get(:@agent))
    refute_equal arg, refined
    assert_match(/mist/i, refined)
  end

  def test_dilla_council_brief_shared
    brief = Master::Voice::Dilla.council_brief
    assert_match(/Dilla|Production DNA/i, brief)
  end
end