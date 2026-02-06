# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/typography"

class TestTypography < Minitest::Test
  def test_format_preserves_code_blocks
    input = "Hello\n```ruby\ncode here\n```\nWorld"
    output = MASTER::Typography.format(input)
    assert_includes output, "```ruby"
    assert_includes output, "code here"
    assert_includes output, "```"
  end

  def test_typeset_converts_smart_quotes
    text = '"hello world"'
    result = MASTER::Typography.typeset(text)
    assert_includes result, '"'
    assert_includes result, '"'
  end

  def test_typeset_converts_em_dashes
    text = "hello -- world"
    result = MASTER::Typography.typeset(text)
    assert_includes result, "—"
  end

  def test_typeset_converts_ellipsis
    text = "hello..."
    result = MASTER::Typography.typeset(text)
    assert_includes result, "…"
  end

  def test_wrap_prose_wraps_long_lines
    text = "word " * 20
    result = MASTER::Typography.wrap_prose(text, width: 40)
    lines = result.split("\n")
    lines.each do |line|
      assert line.length <= 45, "Line too long: #{line.length}"
    end
  end

  def test_wrap_prose_preserves_paragraphs
    text = "First paragraph.\n\nSecond paragraph."
    result = MASTER::Typography.wrap_prose(text)
    assert_includes result, "\n\n"
  end

  def test_split_regions_identifies_code_and_prose
    text = "prose\n```ruby\ncode\n```\nmore prose"
    regions = MASTER::Typography.split_regions(text)
    assert regions.any? { |r| r[:code] }
    assert regions.any? { |r| !r[:code] }
  end
end
