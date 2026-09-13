# frozen_string_literal: true

require_relative "test_helper"

# `/scan face` resolves to web/public (CLI::Scan::Request::TARGET_ALIASES). The
# generated face bundles sit there, and a scan rooted at that directory must
# skip them exactly as a scan rooted at MASTER or the repo does.
class TestScanPathFilter < Minitest::Test
  Scanner = Master::Review::Scan::Scanner
  PUBLIC = File.join(Master::ROOT, "web", "public")

  def test_the_face_alias_points_at_the_face_sources
    assert_equal PUBLIC, Master::CLI::Scan::Request::TARGET_ALIASES.fetch("face")
  end

  def test_generated_bundles_are_skipped_from_every_root
    Master::Review::Scan::PathFilter::GENERATED_FACE_BUNDLES.each do |bundle|
      path = File.join(Master::ROOT, bundle)
      [PUBLIC, File.join(Master::ROOT, "web"), Master::ROOT, Master::REPO_ROOT].each do |root|
        assert Scanner.skip_path?(path, root:), "#{bundle} is scanned from #{root}"
      end
    end
  end

  def test_compiled_assets_are_skipped_from_the_face_root
    assert Scanner.skip_path?(File.join(PUBLIC, "assets", "face-abc123.js"), root: PUBLIC)
  end

  def test_an_authored_face_source_is_still_scanned
    refute Scanner.skip_path?(File.join(PUBLIC, "visual_bridge.js"), root: PUBLIC)
    refute Scanner.skip_path?(File.join(PUBLIC, "visual_bridge.js"), root: Master::ROOT)
  end

  def test_a_path_outside_master_is_judged_by_its_own_root
    rails_file = File.join(Master::REPO_ROOT, "RAILS", "brgen", "app", "models", "post.rb")
    refute Scanner.skip_path?(rails_file, root: Master::REPO_ROOT)
  end
end
