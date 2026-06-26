# frozen_string_literal: true

require_relative "../test_helper"

class TestMotionLoraPresets < Minitest::Test
  def test_all_six_presets_registered
    assert_equal 6, Master::Reach::MotionLoraPresets.names.size
    assert_includes Master::Reach::MotionLoraPresets.names, "gentle_crane_down_reveal"
  end

  def test_resolve_slow_dolly_preset
    resolved = Master::Reach::MotionLoraPresets.resolve("slow_dolly_push_in")
    assert resolved
    assert_match(/slow_cinematic_dolly_push_in/, resolved[:motion_lora])
    assert_in_delta 0.75, resolved[:motion_lora_weight]
    assert_match(/dolly push-in/i, resolved[:camera_phrase])
  end

  def test_resolve_stack_combo
    stack = Master::Reach::MotionLoraPresets.resolve_stack("spiraling_push_in")
    assert_equal 2, stack.size
    assert_match(/dolly_push_in/, stack[0][:motion_lora])
    assert_match(/orbit_tracking/, stack[1][:motion_lora])
    assert_in_delta 0.7, stack[0][:weight]
    assert_in_delta 0.5, stack[1][:weight]
  end

  def test_apply_sets_defaults_without_overriding_explicit_lora
    opts = {
      motion_lora: "custom.safetensors",
      motion_lora_weight: nil,
      motion_lora_2: nil,
      motion_lora_2_weight: nil,
      camera_phrase: nil,
    }
    Master::Reach::MotionLoraPresets.apply!(opts, preset_name: "slow_dolly_push_in")
    assert_equal "custom.safetensors", opts[:motion_lora]
    assert_in_delta 0.75, opts[:motion_lora_weight]
    assert_match(/dolly push-in/i, opts[:camera_phrase])
  end

  def test_caption_template_substitutes_subject
    caption = Master::Reach::MotionLoraPresets.caption_for(
      "slow_dolly_push_in",
      subject: "ZIKI girl in neon alley"
    )
    assert_includes caption, "ZIKI girl in neon alley"
    assert_match(/dolly push-in/i, caption)
  end
end