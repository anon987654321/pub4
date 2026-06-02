# frozen_string_literal: true

require_relative "test_helper"

class TestRenderer < Minitest::Test
  class FakeRenderer < Master::Voice::Renderer
    def dmesg_lines
      Array.new(9) { |i| "boot line #{i}" }.first(self.class::BOOT_DMESG_LINES)
    end

    def git_rev = "test"
    def soul_version = "test"
    def imports_loaded = []
    def active_orders_count = 0
  end

  def test_boot_dmesg_is_capped_at_five_lines
    assert_equal 5, Master::Voice::Renderer::BOOT_DMESG_LINES
    assert_equal 5, FakeRenderer.new(config: {}).dmesg_lines.size
  end

  def test_splash_keeps_multiline_boot_shape
    lines = FakeRenderer.new(config: {}).splash("model").lines

    assert_operator lines.size, :>, 5
    assert_operator lines.count { |line| line.include?("boot line") }, :>=, 2
    assert_operator lines.count { |line| line.include?("boot line") }, :<=, 5
  end
end
