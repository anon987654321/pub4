# frozen_string_literal: true

require_relative "test_helper"
require "minitest/mock"
require "tmpdir"
require_relative "../checks/support/pixel_match"
require_relative "../checks/lib/rendered/browser_diagnostics"

# pixelmatch's two ideas, ported: a perceptual threshold and anti-aliasing detection, plus the
# changed boxes and the 4x crop a visual repair is judged on.
class TestPixelMatch < Minitest::Test
  Match = Deploy::PixelMatch
  WHITE = [255, 255, 255, 255].freeze
  BLACK = [0, 0, 0, 255].freeze
  GREY = [128, 128, 128, 255].freeze

  def png(path, size)
    width, height = size
    rgba = (0...(width * height)).flat_map { |pos| yield(pos % width, pos / width) }
    File.binwrite(path, Deploy::PngDiff.encode_rgba(width, height, rgba.pack("C*")))
    path
  end

  # A black block on white whose edge column is black, or softened to grey.
  def block(path, soft:)
    png(path, [20, 20]) do |col, _row|
      if col < 9 then BLACK
      elsif col == 9 then soft ? GREY : BLACK
      else WHITE
      end
    end
  end

  def test_a_shade_below_the_threshold_is_not_change
    Dir.mktmpdir do |dir|
      base = png(File.join(dir, "a.png"), [20, 20]) { WHITE }
      noise = png(File.join(dir, "b.png"), [20, 20]) { |col, _row| col.even? ? [252, 252, 252, 255] : WHITE }

      result = Match.compare(baseline_path: base, current_path: noise)

      assert_equal 0, result[:pixel_diff_count]
      assert_empty result[:regions]
    end
  end

  def test_an_edge_resampled_by_one_pixel_is_anti_aliasing_not_change
    Dir.mktmpdir do |dir|
      result = Match.compare(baseline_path: block(File.join(dir, "a.png"), soft: false),
                             current_path: block(File.join(dir, "b.png"), soft: true))

      assert_equal 0, result[:pixel_diff_count]
      assert_equal 20, result[:aliased]
    end
  end

  def test_two_separate_changes_come_back_as_two_boxes_and_a_diff_image
    Dir.mktmpdir do |dir|
      base = png(File.join(dir, "a.png"), [64, 64]) { WHITE }
      changed = png(File.join(dir, "b.png"), [64, 64]) do |col, row|
        (col < 4 && row < 4) || (col > 50 && row > 50) ? BLACK : WHITE
      end
      result = Match.compare(baseline_path: base, current_path: changed, diff_path: File.join(dir, "diff.png"))

      assert_equal 16 + 13 * 13, result[:pixel_diff_count]
      assert_equal [{ x: 0, y: 0, w: 16, h: 16 }, { x: 48, y: 48, w: 16, h: 16 }], result[:regions]
      assert_equal [64, 64], Match.read(result[:pixel_diff_image]).size
    end
  end

  def test_a_crop_is_the_box_enlarged_four_times
    Dir.mktmpdir do |dir|
      image = png(File.join(dir, "a.png"), [32, 32]) { |col, _row| col < 16 ? BLACK : WHITE }
      out = Match.crop(image, { x: 12, y: 12, w: 8, h: 8 }, out: File.join(dir, "crop.png"), pad: 0)
      cropped = Match.read(out)

      assert_equal [32, 32], cropped.size
      assert_equal Match.pack(BLACK), cropped.pixels[15]
      assert_equal Match.pack(WHITE), cropped.pixels[16]
    end
  end

  # The baseline comparison the browser sweep makes is the perceptual one: on origin this
  # anti-aliased edge counted 20 changed pixels, 5% of the frame, and failed as a regression.
  def test_the_baseline_comparison_ignores_anti_aliasing_and_reports_boxes
    Dir.mktmpdir do |dir|
      base = block(File.join(dir, "approved.png"), soft: false)
      soft = block(File.join(dir, "current.png"), soft: true)
      surface = Deploy::GeometryProbe::Surface.new(app: "brgen", label: "core", viewport: "mobile",
                                                   pixel_snapshot: true)

      evidence = Deploy::BrowserDiagnosticsCheck.stub(:visual_baseline_path, base) do
        Deploy::BrowserDiagnosticsCheck.new.send(:pixel_evidence, surface:, screenshot: soft,
                                                                  screenshot_dir: dir, screenshot_error: nil)
      end

      assert_equal "COMPARED", evidence.fetch("status")
      assert_equal 0, evidence.fetch("pixel_diff_count")
      assert_equal [], evidence.fetch("pixel_diff_regions")
    end
  end

  # A capture that never held still for two shots is not compared, and not passed.
  def test_an_unsteady_capture_is_not_compared
    Dir.mktmpdir do |dir|
      base = block(File.join(dir, "approved.png"), soft: false)
      surface = Deploy::GeometryProbe::Surface.new(app: "brgen", label: "core", viewport: "mobile",
                                                   pixel_snapshot: true)
      check = Deploy::BrowserDiagnosticsCheck.new
      check.instance_variable_set(:@still, { attempts: 4, stable: false })

      evidence = Deploy::BrowserDiagnosticsCheck.stub(:visual_baseline_path, base) do
        check.send(:pixel_evidence, surface:, screenshot: base, screenshot_dir: dir, screenshot_error: nil)
      end

      assert_equal "UNSTABLE", evidence.fetch("status")
      assert_match(/changed between every one of 4 screenshots/, evidence.fetch("reason"))
    end
  end
end
