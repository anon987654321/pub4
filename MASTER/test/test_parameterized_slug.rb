# frozen_string_literal: true

require_relative "test_helper"
require "master"

class TestParameterizedSlug < Minitest::Test
  def test_dense_slug_strips_filler
    assert_equal "crawl_browser", Master::Ground::ParameterizedSlug.dense_slug("misc_crawl_browser_helper")
  end

  def test_filler_only_detected
    assert Master::Ground::ParameterizedSlug.filler_only?("misc_util_helper")
    refute Master::Ground::ParameterizedSlug.filler_only?("domain_alignment_gate")
  end

  def test_fold_target_for_support_suffix
    assert_equal "crawl", Master::Ground::ParameterizedSlug.fold_target("crawl_support")
  end
end
