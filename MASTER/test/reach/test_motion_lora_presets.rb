# frozen_string_literal: true

require_relative "../test_helper"

class TestMotionLoraPresets < Minitest::Test
  def test_names_include_slow_dolly
    assert_includes Master::Reach::MotionLoraPresets.names, "slow_dolly_push_in"
  end

  def test_caption_substitutes_subject
    caption = Master::Reach::MotionLoraPresets.caption_for("slow_dolly_push_in", subject: "ZIKI girl")
    assert_includes caption, "ZIKI girl"
  end
end