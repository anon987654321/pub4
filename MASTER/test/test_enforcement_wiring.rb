# frozen_string_literal: true

require_relative "test_helper"

class TestEnforcementWiring < Minitest::Test
  FakeRenderer = Struct.new(:calls) do
    def render(text, mode:) = "#{mode}:#{text}"
    def output_context(_mode) = :routine
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

  # Both directions, because the guard was inert for as long as it was: a
  # reply that claims work with no evidence must reach the annotation, and one
  # that shows its work must not.
  def test_render_annotates_an_unevidenced_completion_claim
    result = render_through_guard("I removed the dead file.")

    assert_match(/output warning: evidence_contract/, result.value!.rendered)
    assert_equal ["completion claim without command output"],
                 result.value!.output_findings.map(&:pattern)
  end

  def test_render_leaves_an_evidenced_reply_alone
    result = render_through_guard("I removed the dead file.\n$ git rm lib/x.rb\nexit code: 0")

    refute_match(/output warning/, result.value!.rendered)
    assert_empty result.value!.output_findings
  end

  # Ground::Tool::Protocol's two predicates reach a caller only here.
  def test_render_annotates_a_shell_block_offered_as_execution
    result = render_through_guard("I ran it.\n```sh\nrake test\n```")

    assert_includes result.value!.output_findings.map(&:pattern),
                    "shell block presented as execution"
  end

  private

  def render_through_guard(text)
    stage = Master::CLI::Stages::Render.new(
      renderer: FakeRenderer.new([]),
      output_guard: Master::Voice::OutputGuard.new,
    )
    stage.call(Master::CLI::PipelineContext.build(user_message: "x", output: text))
  end
end
