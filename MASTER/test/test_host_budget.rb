# frozen_string_literal: true

require "test_helper"
require "ground/host_budget"

class TestHostBudget < Minitest::Test
  def test_repo_wide_request_detects_full_tree_prompt
    text = "analyze every single file in MASTER and DEPLOY recursively and autofix gaps"
    assert Master::Ground::HostBudget.repo_wide_request?(text)
  end

  def test_repo_wide_request_ignores_bounded_scan
    refute Master::Ground::HostBudget.repo_wide_request?("/scan lib")
  end

  def test_refuse_heavy_prompt_when_constrained
    Master::Ground::HostBudget.stub(:constrained?, true) do
      msg = Master::Ground::HostBudget.refuse_heavy_prompt?("analyze all files recursively")
      assert_match(/host budget/, msg)
      assert_match(/OOM/, msg)
    end
  end

  def test_refuse_heavy_prompt_passes_small_prompt_on_constrained_host
    Master::Ground::HostBudget.stub(:constrained?, true) do
      assert_nil Master::Ground::HostBudget.refuse_heavy_prompt?("/status")
    end
  end
end