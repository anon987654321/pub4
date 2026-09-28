# frozen_string_literal: true

require "minitest/autorun"

class FormAndOverlaySurfaceContractTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CSS = File.read(File.join(ROOT, "shared/app/assets/stylesheets/_components.scss"))
  HOOK = File.read(File.expand_path("../../OPENBSD/dev/githooks/pre-push", __dir__))

  def test_text_controls_have_a_shared_surface_and_focus_state
    assert_includes CSS, 'input[type="datetime-local"]'
    assert_includes CSS, "min-block-size: var(--tap-min)"
    assert_includes CSS, "border-color: var(--accent)"
    assert_includes CSS, ':not(.btn):user-invalid'
  end

  def test_unclassified_submit_controls_cannot_fall_back_to_ua_buttons
    assert_includes CSS, 'input[type="submit"]:not(.btn):not([class])'
    assert_includes CSS, 'button[type="submit"]:not(.btn):not([class])'
  end

  def test_native_dialog_and_popover_have_shared_tokens
    assert_includes CSS, "dialog::backdrop"
    assert_includes CSS, "[popover]"
    assert_includes CSS, "max-block-size: calc(100dvh"
    assert_includes CSS, "var(--scrim-55)"
  end

  def test_pre_push_regenerates_snapshots_before_publishing
    assert_includes HOOK, "MASTER/tools/snapshot.rb"
    assert_includes HOOK, "snapshot regeneration failed; push refused"
  end
end
