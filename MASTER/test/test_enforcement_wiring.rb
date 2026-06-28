# frozen_string_literal: true

require_relative "test_helper"

class TestEnforcementWiring < Minitest::Test
  FakeInjectionGuard = Struct.new(:result) do
    def scan(*) = result
  end

  FakeRenderer = Struct.new(:calls) do
    def render(text, mode:) = "#{mode}:#{text}"
  end

  def test_guard_enforces_explicit_evidence_metadata
    evidence = Master::Ground::Evidence.new(
      {
        "sources" => { "test_pass" => { "trust" => 0.95 } },
        "required_for" => ["modification"],
        "combine" => { "min_total_trust" => 0.75 },
      },
      root: Dir.pwd,
    )
    stage = Master::Now::Stages::Guard.new(
      governor: nil,
      injection_guard: FakeInjectionGuard.new(Master::Result.ok(:clean)),
      evidence:,
    )
    ctx = Master::Now::PipelineContext.build(
      user_message: "change it",
      message: "change it",
      metadata: { evidence_action: "modification", evidence_sources: [{ type: "test_pass" }] },
    )

    assert stage.call(ctx).err?
  end

  def test_render_annotates_blocking_findings
    checker = Master::Judge::OutputCheck.new("hallucination" => ["created phantom"])
    renderer = FakeRenderer.new([])
    stage = Master::Now::Stages::Render.new(renderer:, output_check: checker)
    ctx = Master::Now::PipelineContext.build(user_message: "x", output: "created phantom")
    result = stage.call(ctx)

    assert result.ok?
    assert_match(/output warning: hallucination/, result.value!.rendered)
    assert_equal 1, result.value!.output_findings.size
  end
end
