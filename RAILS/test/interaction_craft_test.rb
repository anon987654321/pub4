# frozen_string_literal: true

require "minitest/autorun"

class TestRailsInteractionCraft < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  SHARED = File.join(ROOT, "RAILS", "__shared")
  STACK = File.join(SHARED, "app", "assets", "stylesheets", "_stack.scss")
  CRAFT = File.join(SHARED, "app", "assets", "stylesheets", "_interaction_craft.scss")
  BUTTONS = File.join(SHARED, "app", "assets", "stylesheets", "_buttons.scss")
  MODAL = File.join(SHARED, "app", "assets", "stylesheets", "_modal.scss")
  HAPTICS = File.join(SHARED, "frontend", "haptics_controller.js")
  SHEET = File.join(SHARED, "frontend", "bottom_sheet_controller.js")
  TOAST = File.join(SHARED, "app", "views", "shared", "_toast.html.erb")

  def test_shared_interaction_craft_is_forwarded
    stack = File.read(STACK)
    assert_includes stack, '@forward "interaction_craft";'
    assert File.file?(CRAFT)
  end

  def test_press_feedback_is_compositor_safe_and_touch_friendly
    css = File.read(CRAFT)
    assert_includes css, "touch-action: manipulation;"
    assert_includes css, "transform var(--duration-m3-short)"
    assert_includes css, "@media (prefers-reduced-motion: reduce)"
    assert_includes css, "stroke-dashoffset: 0;"
    refute_match(/box-shadow\s*:/, css)
    refute_match(/backdrop-filter\s*:/, css)
  end

  def test_buttons_use_early_physical_feedback_tokens
    css = File.read(BUTTONS)
    assert_includes css, "touch-action: manipulation;"
    assert_includes css, "transform var(--duration-m3-short) var(--ease-m3-spring)"
    assert_includes css, ".btn:active"
  end

  def test_bottom_sheet_uses_shared_spring_tokens_and_pointer_capture
    css = File.read(MODAL)
    js = File.read(SHEET)
    assert_includes css, "transform var(--duration-m3-short) var(--ease-spring)"
    assert_includes js, "setPointerCapture"
    assert_includes js, "releasePointerCapture"
  end

  def test_haptics_has_an_early_press_signal
    js = File.read(HAPTICS)
    assert_includes js, "press()"
    assert_includes js, "this.#vibrate(10)"
  end

  def test_success_toast_has_a_static_and_animated_state
    erb = File.read(TOAST)
    assert_includes erb, 'variant == "success"'
    assert_includes erb, 'class="interaction-success"'
    assert_includes erb, 'class="interaction-success__check"'
    assert_includes erb, 'role="status"'
  end
end
