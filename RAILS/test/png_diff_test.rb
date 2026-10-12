# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../MASTER/gates/support/png_diff"

class PngDiffTest < Minitest::Test
  def write_png(dir, name, width, height, pixels)
    path = File.join(dir, name)
    File.binwrite(path, Deploy::PngDiff.encode_rgba(width, height, pixels.pack("C*")))
    path
  end

  def test_counts_changed_pixels_and_writes_a_heatmap
    Dir.mktmpdir("png-diff") do |dir|
      base = write_png(dir, "base.png", 2, 2, [
        0, 0, 0, 255, 0, 0, 0, 255,
        0, 0, 0, 255, 0, 0, 0, 255
      ])
      current = write_png(dir, "current.png", 2, 2, [
        255, 255, 255, 255, 0, 0, 0, 255,
        0, 0, 0, 255, 0, 0, 0, 255
      ])
      heatmap = File.join(dir, "diff.png")

      result = Deploy::PngDiff.compare(baseline_path: base, current_path: current, diff_path: heatmap)

      assert_equal :compared, result[:status]
      assert_equal 1, result[:pixel_diff_count]
      assert_equal 0.25, result[:pixel_diff_ratio]
      assert_equal heatmap, result[:pixel_diff_image]
      image = Deploy::PngDiff.decode(File.binread(heatmap))
      assert_equal [2, 2, 4], image.values_at(:width, :height, :channels)
    end
  end

  def test_identical_images_report_zero_drift_and_no_heatmap
    Dir.mktmpdir("png-diff") do |dir|
      pixels = Array.new(3 * 2 * 4, 127)
      base = write_png(dir, "base.png", 3, 2, pixels)
      current = write_png(dir, "current.png", 3, 2, pixels)

      result = Deploy::PngDiff.compare(baseline_path: base, current_path: current,
                                       diff_path: File.join(dir, "diff.png"))

      assert_equal 0, result[:pixel_diff_count]
      assert_equal 0.0, result[:pixel_diff_ratio]
      assert_nil result[:pixel_diff_image]
      refute File.exist?(File.join(dir, "diff.png"))
    end
  end

  def test_dimension_mismatch_is_explicit_and_never_compared_as_a_pass
    Dir.mktmpdir("png-diff") do |dir|
      base = write_png(dir, "base.png", 2, 2, Array.new(16, 0))
      current = write_png(dir, "current.png", 3, 2, Array.new(24, 0))

      result = Deploy::PngDiff.compare(baseline_path: base, current_path: current)

      assert_equal :dimension_mismatch, result[:status]
      assert_equal [2, 2], result[:baseline_dimensions]
      assert_equal [3, 2], result[:current_dimensions]
      assert_nil result[:pixel_diff_count]
    end
  end

  def test_corrupt_png_is_rejected
    Dir.mktmpdir("png-diff") do |dir|
      path = write_png(dir, "broken.png", 1, 1, [1, 2, 3, 255])
      bytes = File.binread(path)
      bytes.setbyte(bytes.bytesize - 1, bytes.getbyte(bytes.bytesize - 1) ^ 0xff)
      File.binwrite(path, bytes)

      assert_raises(Deploy::PngDiff::InvalidPng) { Deploy::PngDiff.decode(File.binread(path)) }
    end
  end
end
