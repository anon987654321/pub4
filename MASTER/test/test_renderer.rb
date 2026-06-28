# frozen_string_literal: true

require_relative "test_helper"

class TestRenderer < Minitest::Test
  class FakeRenderer < Master::Voice::Renderer
    def dmesg_lines
      Array.new(9) { |i| "boot line #{i}" }.first(self.class::BOOT_DMESG_LINES)
    end

    def git_rev
      "test"
    end

    def soul_version
      "test"
    end

    def imports_loaded
      []
    end

    def active_orders_count
      0
    end
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

  def test_prompt_line_shows_context_usage
    line = FakeRenderer.new(config: {}).prompt_line("model", "idle", tokens: 45_000).first

    assert_includes line, "ctx:"
    assert_includes line, "/128.0k"
  end
end
