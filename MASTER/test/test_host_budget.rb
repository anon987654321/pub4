# frozen_string_literal: true

require "open3"
require "yaml"

require "test_helper"
require "ground/host_budget"

class TestHostBudget < Minitest::Test
  def test_repo_wide_request_detects_full_tree_prompt
    text = "analyze every single file in MASTER and OPERATOR recursively and autofix gaps"
    assert Master::Ground::HostBudget.repo_wide_request?(text)
  end

  def test_repo_wide_request_ignores_bounded_scan
    refute Master::Ground::HostBudget.repo_wide_request?("/fix lib")
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
  # HostBudget measures the host; OPENBSD/vm_resource.yml declares it. The two
  # must agree that the declared box is constrained, or vm23 boots with TTS, the
  # boot scan and the background loops on.
  def test_the_declared_vm_is_a_constrained_host
    budget = Master::Ground::HostBudget
    previous = budget.instance_variable_get(:@total_mem_mb)
    budget.instance_variable_set(:@total_mem_mb, Integer(declared_vm.fetch("ram_mb")))

    assert budget.constrained?
  ensure
    budget.instance_variable_set(:@total_mem_mb, previous)
  end

  # RuntimeCatalog reads the same file for the face's Falcon worker budget; a
  # wrong path falls back to FALCON_COUNT without a word, so FALCON_COUNT is set
  # to a value the file does not hold.
  def test_the_web_boot_payload_reads_the_declared_worker_budget
    previous = ENV["FALCON_COUNT"]
    ENV["FALCON_COUNT"] = "97"

    assert_equal declared_vm.dig("limits", "master_falcon_workers"),
                 Master::Ground::RuntimeCatalog.web_boot_payload_minimal[:falcon_worker_budget]
  ensure
    ENV["FALCON_COUNT"] = previous
  end

  private

  def declared_vm
    YAML.safe_load_file(File.join(Master::REPO_ROOT, "OPENBSD", "vm_resource.yml"))
  end
end
