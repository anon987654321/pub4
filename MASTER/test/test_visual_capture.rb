# frozen_string_literal: true

require_relative "test_helper"
require_relative "../tools/visual_capture"

class TestVisualCapture < Minitest::Test
  def test_named_and_custom_viewports_are_explicit
    assert_equal [390, 844], MasterVisualCapture.parse_viewport("mobile")
    assert_equal [375, 812], MasterVisualCapture.parse_viewport("375x812")
  end

  def test_viewport_rejects_invalid_dimensions
    error = assert_raises(OptionParser::InvalidArgument) do
      MasterVisualCapture.parse_viewport("0x812")
    end
    assert_match(/viewport must be NAME or WIDTHxHEIGHT/, error.message)
  end

  def test_seed_is_deterministic
    assert_equal MasterVisualCapture.seed_for("master/chat@mobile"),
                 MasterVisualCapture.seed_for("master/chat@mobile")
    refute_equal MasterVisualCapture.seed_for("master/chat@mobile"),
                 MasterVisualCapture.seed_for("master/chat@desktop")
  end

  def test_freeze_script_replaces_random_and_date
    script = MasterVisualCapture.freeze_script(123)
    assert_includes script, "Math.random = random"
    assert_includes script, "window.Date = FixedDate"
    assert_includes script, "1767225600000"
  end
end
