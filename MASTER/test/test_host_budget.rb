# frozen_string_literal: true

require "open3"

require "test_helper"
require "ground/host_budget"

class TestHostBudget < Minitest::Test
  def test_repo_wide_request_detects_full_tree_prompt
    text = "analyze every single file in MASTER and OPERATOR recursively and autofix gaps"
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

  def test_suspended_ruby_pids_parses_stopped_cli
    fake = <<~PS
      60670 Tpu /usr/local/bin/ruby bin/cli
      22489 S ruby34: http://127.0.0.1:53187
      63744 T /usr/local/bin/ruby34 tts-worker
    PS
    Open3.stub(:capture2, [fake, nil]) do
      pids = Master::Ground::HostBudget.suspended_ruby_pids(user: "dev")
      assert_includes pids, 60_670
      assert_includes pids, 63_744
      refute_includes pids, 22_489
    end
  end
end
