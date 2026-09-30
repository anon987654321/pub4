# frozen_string_literal: true

require_relative "test_helper"

class TestMD < Minitest::Test
  def test_normalize_keeps_fenced_source_exact
    source = "# Title  \n\n* one  \n\n```ruby\nvalue  = 1\n```\n"
    normalized = Master::MD.normalize(source)

    assert_equal "# Title\n\n- one\n\n```ruby\nvalue  = 1\n```\n", normalized
  end

  def test_style_reads_rules_yml
    assert_equal "tadao_ando", Master::MD.style.fetch("aesthetic")
  end
  def test_pdf_engine_failure_is_explicit
    refute Master::PDF.available?(command: "master-command-that-does-not-exist")
  end
end
