# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/master"

class TestFileHygiene < Minitest::Test
  def test_strip_crlf
    assert_equal "hello\nworld\n", MASTER::FileHygiene.strip_crlf("hello\r\nworld\r\n")
  end

  def test_strip_trailing_whitespace
    assert_equal "hello\nworld", MASTER::FileHygiene.strip_trailing_whitespace("hello   \nworld  ")
  end

  def test_strip_bom
    bom = "\xEF\xBB\xBFhello"
    assert_equal "hello", MASTER::FileHygiene.strip_bom(bom)
  end

  def test_strip_zero_width
    text = "hello\u200Bworld"
    assert_equal "helloworld", MASTER::FileHygiene.strip_zero_width(text)
  end

  def test_ensure_final_newline
    assert_equal "hello\n", MASTER::FileHygiene.ensure_final_newline("hello")
    assert_equal "hello\n", MASTER::FileHygiene.ensure_final_newline("hello\n")
  end

  def test_clean_full_pipeline
    dirty = "\xEF\xBB\xBFhello   \r\nworld\u200B  \r\n"
    clean = MASTER::FileHygiene.clean(dirty)
    assert_equal "hello\nworld\n", clean
    refute clean.include?("\r")
    refute clean.include?("\u200B")
  end
end
