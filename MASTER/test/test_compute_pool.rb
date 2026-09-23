# frozen_string_literal: true

require_relative "test_helper"

class TestComputePool < Minitest::Test
  class Router
    def reachable?(id)
      id != "down"
    end

    def tool_capable?(id)
      id.include?("qwen") || id.include?("claude")
    end

    def pool(wait: false)
      ["ollama:qwen3.5:27b"]
    end

    def lane_label(id)
      id.start_with?("ollama:") ? "local" : "paid"
    end
  end

  def setup
    @pool = Master::Core::Routing::ComputePool.new(router: Router.new)
  end

  def test_ranks_reachable_models
    ids = ["ollama:qwen3.5:27b", "down"]
    assert_equal ["ollama:qwen3.5:27b"], @pool.rank(ids)
  end

  def test_records_success_and_failure
    @pool.record(model: "ollama:qwen3.5:27b", status: :success, latency_ms: 100)
    @pool.record(model: "ollama:qwen3.5:27b", status: :failure, error: "timeout")
    stat = @pool.snapshot.fetch("ollama:qwen3.5:27b")
    assert_equal 2, stat[:calls]
    assert_equal 1, stat[:successes]
    assert_equal 1, stat[:failures]
  end
end

  def test_snapshot_is_independent
    @pool.record(model: "ollama:qwen3.5:27b", status: :success, latency_ms: 100)
    copy = @pool.snapshot
    copy.fetch("ollama:qwen3.5:27b")[:calls] = 99

    assert_equal 1, @pool.snapshot.fetch("ollama:qwen3.5:27b")[:calls]
  end

  def test_inventory_reports_live_models_and_telemetry
    @pool.record(model: "ollama:qwen3.5:27b", status: :success, latency_ms: 100)

    row = @pool.inventory(task_type: :code_generation).first

    assert_equal "ollama:qwen3.5:27b", row[:id]
    assert_equal 1, row[:rank]
    assert_equal "local", row[:lane]
    assert_equal 1.0, row[:success_rate]
    assert_equal 100.0, row[:latency_ms]
    assert_equal :available, row[:quota_state]
  end
