# frozen_string_literal: true

require_relative "test_helper"

class HostileCouncilPromptsTest < Minitest::Test
  def test_juror_prompt_exposes_self_falsification
    source = File.read(File.expand_path("../lib/review/council/deliberation_prompt_builder.rb", __dir__))
    council = File.read(File.expand_path("../data/council.yml", __dir__))
    assert_includes source, "HOSTILE SELF-TEST"
    assert_includes source, "what evidence would falsify your criticism"
    assert_includes council, "%{hostile_block}"
  end

  def test_solution_generation_attacks_the_field_before_cherry_pick
    source = File.read(File.expand_path("../lib/review/council/critique.rb", __dir__))
    assert_includes source, "SOLUTION RED-TEAM"
    assert_includes source, "hidden assumption"
    assert_includes source, "smallest deletion"
    assert_includes source, "counterexample state"
    assert_includes source, "invert that assumption"
  end

  def test_visual_fix_adds_visual_counterfactuals
    source = File.read(File.expand_path("../lib/fix/visual_pass.rb", __dir__))
    assert_includes source, "HOSTILE VISUAL AUDIT"
    assert_includes source, "font loading"
    assert_includes source, "adversarial user"
    assert_includes source, "Only promote a hostile observation"
  end
end
