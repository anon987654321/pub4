# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/fix/surface_evidence"

class TestSurfaceEvidenceContract < Minitest::Test
  def evidence = Master::Fix::SurfaceEvidence.allocate

  def capture_row(overrides = {})
    {
      "rendered_status" => "assessed_clean",
      "screenshot_sha256" => "a" * 64,
      "geometry_sha256" => "b" * 64,
      "element_count" => 12,
    }.merge(overrides)
  end

  def test_rendered_capture_requires_screenshot_geometry_and_element_receipt
    assert evidence.send(:valid_rendered_capture?, capture_row)
    refute evidence.send(:valid_rendered_capture?, capture_row("screenshot_sha256" => nil))
    refute evidence.send(:valid_rendered_capture?, capture_row("geometry_sha256" => "missing"))
    refute evidence.send(:valid_rendered_capture?, capture_row("element_count" => "unknown"))
    refute evidence.send(:valid_rendered_capture?, capture_row("element_count" => -1))
    refute evidence.send(:valid_rendered_capture?, capture_row("rendered_status" => "inconclusive"))
  end

  def test_media_inventory_does_not_ignore_symlinked_assets
    inventory = {
      "records" => [
        ["public/logo.svg", "file", 120],
        ["public/private-logo.png", "symlink", 0],
        ["README.md", "file", 50],
      ]
    }

    rows = evidence.send(:recognized_asset_records, inventory)

    assert_equal [["public/logo.svg", "file", 120], ["public/private-logo.png", "symlink", 0]], rows
  end

  def test_compact_visual_evidence_keeps_geometry_receipt_without_page_content
    row = capture_row.merge("id" => "surface-1", "url" => "https://private.invalid/path?token=secret")
    compact = evidence.send(:compact_visual_row, row)

    assert_equal "b" * 64, compact.fetch("geometry_sha256")
    assert_equal 12, compact.fetch("element_count")
    refute compact.to_s.include?("private.invalid")
    refute compact.to_s.include?("secret")
  end
end
