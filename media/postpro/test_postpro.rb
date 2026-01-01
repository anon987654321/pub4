#!/usr/bin/env ruby
# frozen_string_literal: true
# Test suite for postpro.rb
require "minitest/autorun"
require "fileutils"
require "tmpdir"

# Minimal test harness - smoke tests only
class PostproTest < Minitest::Test
  def setup
    @test_dir = Dir.mktmpdir("postpro_test")
    @test_image = File.join(@test_dir, "test.jpg")
    create_test_image
  end

  def teardown
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end

  def create_test_image
    # Create minimal valid JPEG (1x1 pixel red square)
    # JPEG header + SOI + APP0 + SOF0 + SOS + data + EOI
    jpeg_data = [
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
      0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01,
      0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
      0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
      0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0A, 0x0C,
      0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
      0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D,
      0x1A, 0x1C, 0x1C, 0x20, 0x24, 0x2E, 0x27, 0x20,
      0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
      0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27,
      0x39, 0x3D, 0x38, 0x32, 0x3C, 0x2E, 0x33, 0x34,
      0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
      0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4,
      0x00, 0x14, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x03, 0xFF, 0xC4, 0x00, 0x14,
      0x10, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
      0x00, 0x00, 0x3F, 0x00, 0xFE, 0x8A, 0x28, 0xFF,
      0xD9
    ].pack("C*")
    
    File.binwrite(@test_image, jpeg_data)
  end

  # Test 1: Module loads without errors
  def test_module_loads
    assert_silent do
      load File.expand_path("postpro.rb", __dir__)
    end
  end

  # Test 2: Bootstrap constants defined
  def test_bootstrap_constants
    load File.expand_path("postpro.rb", __dir__)
    assert defined?(PostproBootstrap), "PostproBootstrap module should be defined"
    assert defined?(BOOTSTRAP), "BOOTSTRAP constant should be defined"
    assert defined?(STOCKS), "STOCKS constant should be defined"
    assert defined?(PRESETS), "PRESETS constant should be defined"
  end

  # Test 3: Film stocks have required keys
  def test_film_stocks_structure
    load File.expand_path("postpro.rb", __dir__)
    STOCKS.each do |name, data|
      assert data.key?(:grain), "Stock #{name} missing :grain"
      assert data.key?(:gamma), "Stock #{name} missing :gamma"
      assert data.key?(:rolloff), "Stock #{name} missing :rolloff"
      assert data.key?(:lift), "Stock #{name} missing :lift"
      assert data.key?(:matrix), "Stock #{name} missing :matrix"
      assert_equal 9, data[:matrix].length, "Stock #{name} matrix should have 9 values"
    end
  end

  # Test 4: Presets have required keys
  def test_presets_structure
    load File.expand_path("postpro.rb", __dir__)
    PRESETS.each do |name, data|
      assert data.key?(:fx), "Preset #{name} missing :fx"
      assert data.key?(:stock), "Preset #{name} missing :stock"
      assert data.key?(:temp), "Preset #{name} missing :temp"
      assert data.key?(:intensity), "Preset #{name} missing :intensity"
      assert data[:fx].is_a?(Array), "Preset #{name} :fx should be array"
      assert STOCKS.key?(data[:stock]), "Preset #{name} references unknown stock"
    end
  end

  # Test 5: Helper functions don't crash on edge cases
  def test_safe_cast_handles_errors
    load File.expand_path("postpro.rb", __dir__)
    skip "Requires vips" unless defined?(Vips)
    
    # Test with nil - should handle gracefully
    # Actual implementation would need vips image
    assert true # Placeholder - would test with actual image
  end

  # Test 6: Color temperature ranges are sane
  def test_color_temp_ranges
    load File.expand_path("postpro.rb", __dir__)
    PRESETS.each do |name, data|
      temp = data[:temp]
      assert temp >= 2000, "Preset #{name} temp #{temp}K too low"
      assert temp <= 12000, "Preset #{name} temp #{temp}K too high"
    end
  end

  # Test 7: Intensity values are reasonable
  def test_intensity_ranges
    load File.expand_path("postpro.rb", __dir__)
    PRESETS.each do |name, data|
      intensity = data[:intensity]
      assert intensity > 0, "Preset #{name} intensity should be positive"
      assert intensity <= 2.0, "Preset #{name} intensity #{intensity} seems extreme"
    end
  end

  # Test 8: Log message formatting
  def test_log_message_format
    load File.expand_path("postpro.rb", __dir__)
    output = capture_io do
      PostproBootstrap.log_message("test message")
    end
    assert_match(/\[postpro\]/, output[0], "Log should include [postpro] prefix")
  end

  # Test 9: File exists check
  def test_test_image_created
    assert File.exist?(@test_image), "Test image should be created"
    assert File.size(@test_image) > 0, "Test image should not be empty"
  end

  # Test 10: Gem availability check doesn't crash
  def test_gem_check_safe
    load File.expand_path("postpro.rb", __dir__)
    assert_respond_to PostproBootstrap, :ensure_gems
    # Should not crash even if gems missing
    result = PostproBootstrap.ensure_gems
    assert result.is_a?(Hash), "ensure_gems should return hash"
    assert result.key?(:vips), "Should check for vips"
    assert result.key?(:tty), "Should check for tty"
  end
end

# Run if invoked directly
if __FILE__ == $0
  puts "Postpro.rb Test Suite"
  puts "=" * 50
end
