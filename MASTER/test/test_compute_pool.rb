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
