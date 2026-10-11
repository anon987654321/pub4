# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../replicate/lora/_toolkit/preflight"

class PreflightJpegMarkerTest < Minitest::Test
  SOF = [0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x20, 0x00, 0x30].freeze

  def jpeg_size(bytes)
    Preflight.jpeg_size(StringIO.new(bytes.pack("C*")))
  end

  def test_tem_marker_has_no_segment_length
    bytes = [0xFF, 0xD8, 0xFF, 0x01] + SOF

    assert_equal [48, 32], jpeg_size(bytes)
  end

  def test_end_of_image_stops_the_marker_scan
    bytes = [0xFF, 0xD8, 0xFF, 0xD9] + SOF

    assert_nil jpeg_size(bytes)
  end

  def test_nested_start_of_image_is_rejected
    bytes = [0xFF, 0xD8, 0xFF, 0xD8] + SOF

    assert_nil jpeg_size(bytes)
  end
end
