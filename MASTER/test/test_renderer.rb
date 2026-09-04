# frozen_string_literal: true

require_relative "test_helper"

class TestRenderer < Minitest::Test
  class FakeRenderer < Master::Voice::Renderer
    def dmesg_lines
      Array.new(self.class::BOOT_DMESG_LINES + 2) { |i| "boot line #{i}" }.first(self.class::BOOT_DMESG_LINES)
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

  def test_boot_dmesg_is_capped_at_ten_lines
    assert_equal 10, Master::Voice::Renderer::BOOT_DMESG_LINES
    assert_equal 10, FakeRenderer.new(config: {}).dmesg_lines.size
  end

  def test_splash_keeps_multiline_boot_shape
    lines = FakeRenderer.new(config: {}).splash("model").lines

    assert_operator lines.size, :>, 10
    assert_operator lines.count { |line| line.include?("boot line") }, :>=, 2
    assert_operator lines.count { |line| line.include?("boot line") }, :<=, 10
  end

  def test_prompt_line_state_shows_context_usage
    state, prompt = FakeRenderer.new(config: {}).prompt_line("model", "idle", tokens: 45_000)

    assert_includes strip_ansi(state), "ctx 45.0k/128.0k"
    assert_match(/[%$] \z/, strip_ansi(prompt))
  end

  # A dmesg is legible on a serial console: no box drawing, no arrows, no
  # check marks, nothing that a pipe or a 7-bit terminal turns into gibberish.
  def test_splash_is_plain_ascii_in_dmesg_shape
    lines = FakeRenderer.new(config: {}).splash("model").lines.map { |l| strip_ansi(l).chomp }
    filled = lines.reject(&:empty?)

    assert_match(/\AMASTER \S+ \(CONSTITUTIONAL\) #\d+: /, filled.first)
    assert_match(/\A {4}\w+@\S+:\//, filled[1])
    assert(filled.any? { |line| line.start_with?("root on master0 (") })
    assert_empty filled.grep(/[^\x20-\x7e]/), "the boot must stay plain ASCII"
  end

  def strip_ansi(text)
    text.to_s.gsub(/\e\[[0-9;]*m/, "")
  end
end
