# frozen_string_literal: true

require_relative "test_helper"

# TribunalFeedback renders a council deliberation for /tribunal: the judge's
# verdict first, vetoes only from jurors entitled to cast one, then each juror
# on one line. StreamAccumulator is the streaming reply's buffer.
class TestCliTribunalFeedback < Minitest::Test
  Bus = Struct.new(:events) do
    def publish(name, **payload) = events << [name, payload]
  end

  FEEDBACK = [
    { persona: "Ada", role: "Security", axiom: "ROBUSTNESS", veto_role: true, confidence: 0.9,
      feedback: "VETO: shells out with user input\nsecond line" },
    { persona: "Bob", role: "Style", veto_role: false, confidence: 0.5, feedback: "VETO: not mine to cast" },
    { persona: "Judge", role: "Synthesis", feedback: "  Revise before merge.  " },
  ].freeze

  def test_verdict_vetoes_and_jurors_in_that_order
    bus = Bus.new([])
    text = Master::CLI::TribunalFeedback.new(FEEDBACK, event_bus: bus).render

    assert_equal <<~TEXT.chomp, text
      verdict: Revise before merge.

      vetoes:
        Ada: shells out with user input second line

      jurors:
        [ROBUSTNESS] Ada (Security): VETO: shells out with user input second line
        Bob (Style): VETO: not mine to cast
    TEXT
    assert_equal [["tribunal:rendered", { jurors: 2, vetoes: 1, judge: true, confidence: 0.7 }]], bus.events
  end

  def test_the_full_render_marks_who_may_veto
    full = Master::CLI::TribunalFeedback.new(FEEDBACK).render_full

    assert_includes full, "Ada (Security) [VETO ELIGIBLE]:\nVETO: shells out"
    assert_includes full, "Bob (Style):\nVETO: not mine"
    assert_equal 3, full.split("\n\n---\n\n").size
  end

  def test_no_judge_means_no_verdict_line
    text = Master::CLI::TribunalFeedback.new([FEEDBACK[1]]).render

    refute_match(/verdict/, text)
    refute_match(/vetoes/, text)
  end

  Chunk = Struct.new(:content)

  def test_the_accumulator_forwards_and_buffers_text_and_skips_empty_chunks
    seen = []
    buffer = +""
    acc = Master::CLI::StreamAccumulator.new(buffer) { |text| seen << text }
    [Chunk.new("Hel"), Chunk.new(nil), "lo"].each { |chunk| acc.call(chunk) }

    assert_equal "Hello", buffer
    assert_equal %w[Hel lo], seen
  end
end
