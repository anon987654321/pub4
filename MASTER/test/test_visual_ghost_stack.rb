# frozen_string_literal: true

require_relative "test_helper"

class VisualGhostStackContractTest < Minitest::Test
  PATH = File.expand_path("../lib/fix/visual_ghost_stack.rb", __dir__)

  def source = File.read(PATH)

  def test_history_is_persistent_but_bounded
    assert_includes source, 'File.join(@root, "MASTER", ".master", "visual_evidence"'
    assert_includes source, "HISTORY_LIMIT = 5"
    assert_includes source, "prune(history)"
    assert_includes source, "@run_id"
    assert_includes source, 'Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")'
  end

  def test_pass_number_cannot_overwrite_a_previous_fix_run
    assert_includes source, 'stem = "#{safe_slug(@run_id)}-pass-#{format("%06d", pass.to_i)}"'
    refute_includes source, 'format("pass-%06d.png", pass.to_i)'
  end

  def test_visual_stack_is_aligned_and_uses_low_opacity_history
    assert_includes source, "position:absolute;inset:0"
    assert_includes source, "GHOST_OPACITIES = [ 0.04, 0.06, 0.08, 0.12 ]"
    assert_includes source, "CURRENT_OPACITY = 0.72"
    assert_includes source, "GHOST_OPACITIES = [ 0.04, 0.06, 0.09, 0.12 ]"
    assert_includes source, 'class="#{class_name}"'
    assert_includes source, "mix-blend-mode:difference"
  end

  def test_geometry_drift_is_part_of_visual_evidence
    assert_includes source, "DIFF_TOLERANCE_PX = 0.5"
    assert_includes source, '"frect"'
    assert_includes source, '"font_size"'
    assert_includes source, '"line_height"'
    assert_includes source, '"structural"'
  end

  def test_visual_evidence_has_registration_and_grid_diagnostics
    assert_includes source, "REGISTRATION_GRID_PX = 8"
    assert_includes source, "MAX_GEOMETRY_MARKERS = 24"
    assert_includes source, "render_geometry"
    assert_includes source, "geometry registration"
    assert_includes source, "render_grid"
    assert_includes source, "render_focus"
    assert_includes source, "FOCUS_SCALE = 2"
    assert_includes source, "registration grid"
    assert_includes source, "png_dimensions"
    assert_includes source, "previous box"
    assert_includes source, "current box"
  end

  def test_visual_pass_and_contact_sheet_consume_the_evidence
    visual_pass = File.read(File.expand_path("../lib/fix/visual_pass.rb", __dir__))
    contact_sheet = File.read(File.expand_path("../lib/fix/visual_contact_sheet.rb", __dir__))
    assert_includes visual_pass, 'require_relative "visual_ghost_stack"'
    assert_includes visual_pass, "@ghost_stack.capture"
    assert_includes visual_pass, "persistent ghost stack"
    assert_includes contact_sheet, "visual_evidence_items"
    assert_includes contact_sheet, "newest vs previous difference"
    assert_includes contact_sheet, "geometry"
    assert_includes contact_sheet, "grid"
  end
end
