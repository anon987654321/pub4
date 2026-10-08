# frozen_string_literal: true

require_relative "test_helper"

class CouncilVisualEvidenceTest < Minitest::Test
  def test_judge_receives_the_rendered_image
    agent = Object.new
    seen = nil
    agent.define_singleton_method(:ask) do |_prompt, image: nil, **|
      seen = image
      "judge"
    end

    delib = Master::Review::Council::Deliberation.new(
      personas: [],
      agent:,
      judge_enabled: true,
    )
    delib.define_singleton_method(:build_judge_prompt) { |**| "judge this" }

    delib.send(
      :judge,
      feedback: [],
      code: "x = 1",
      context: nil,
      image: { path: "/tmp/ui.png", mime: "image/png" },
    )

    assert_equal "/tmp/ui.png", seen[:path]
  end
end
