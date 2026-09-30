# frozen_string_literal: true

require_relative "test_helper"

class TestMD < Minitest::Test
  def test_normalize_keeps_fenced_source_exact
    source = "# Title  \n\n* one  \n\n```ruby\nvalue  = 1\n```\n"
    normalized = Master::MD.normalize(source)

    assert_equal "# Title\n\n- one\n\n```ruby\nvalue  = 1\n```\n", normalized
  end

  def test_normalize_recognizes_fences_headings_and_bullets
    source = "### Heading\n* one\n+ two\n```ruby\n* inside\n```\n"

    assert_equal "### Heading\n- one\n- two\n```ruby\n* inside\n```\n", Master::MD.normalize(source)
  end

  def test_markdown_regexes_do_not_match_escaped_text
    refute Master::MD::FENCE.match?("\\`not a fence")
    refute Master::MD::HEADING.match?(" text # not a heading")
  end

  def test_style_reads_rules_yml
    assert_equal "tadao_ando", Master::MD.style.fetch("aesthetic")
  end
  def test_pdf_engine_failure_is_explicit
    refute Master::PDF.available?(command: "master-command-that-does-not-exist")
  end
end
