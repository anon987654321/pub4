# frozen_string_literal: true

require_relative "test_helper"

class TestEnforcementWiring < Minitest::Test
  FakeRenderer = Struct.new(:calls) do
    def render(text, mode:) = "#{mode}:#{text}"
  end

  def test_render_annotates_blocking_findings
    checker = Master::Review::OutputCheck.new("hallucination" => ["created phantom"])
    renderer = FakeRenderer.new([])
    stage = Master::CLI::Stages::Render.new(renderer:, output_check: checker)
    ctx = Master::CLI::PipelineContext.build(user_message: "x", output: "created phantom")
    result = stage.call(ctx)

    assert result.ok?
    assert_match(/output warning: hallucination/, result.value!.rendered)
    assert_equal 1, result.value!.output_findings.size
  end
end
