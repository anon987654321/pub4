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
    @pool = Master::CLI::Routing::ComputePool.new(router: Router.new, root: Dir.mktmpdir)
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

  def test_task_strengths_boost_matching_capabilities_only
    @pool.instance_variable_set(:@rules, {
      "task_strengths" => {
        "code_generation" => ["coding"],
        "architecture" => ["reasoning", "long_context", "coding"],
      },
    })
    candidate = Master::CLI::Routing::ComputePool::Candidate.new(id: "deepseek-coder")

    assert_in_delta 1.04, @pool.send(:task_factor, candidate, :code_generation), 0.001
    assert_in_delta 1.08, @pool.send(:task_factor, candidate, :architecture), 0.001
    assert_equal 1.0, @pool.send(:task_factor, candidate, :unknown_task)
  end

  def test_ollama_remains_local_fallback_only
    policy = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
    local_ids = policy.fetch("models").fetch("local").map { |row| row.fetch("id") }

    assert_includes local_ids, "ollama:gemma3:4b"
    %w[default primary strong].each do |tier|
      ids = policy.fetch("models").fetch(tier).map { |row| row.fetch("id") }
      refute_includes ids, "ollama:gemma3:4b", "#{tier} must not promote the constrained Ollama lane"
    end
  end

  def test_task_strengths_change_the_actual_rank_with_equal_base_scores
    @pool.instance_variable_set(:@rules, {
      "routes" => {},
      "models" => {},
      "task_strengths" => {
        "code_generation" => ["coding"],
        "chitchat" => ["fast"],
      },
    })
    ids = %w[openrouter/deepseek-coder:free openrouter/gemini-flash:free]
    candidate = lambda do |id|
      Master::CLI::Routing::ComputePool::Candidate.new(
        id:,
        quality: 1.0,
        speed: 1.0,
        cost: 1.0,
        context_window: 128_000,
        availability: 1.0,
        tool_support: 1.0,
        success_rate: 1.0,
        latency_factor: 1.0,
        score: { "quality" => 1.0, "speed" => 1.0, "cost" => 1.0 },
      )
    end

    @pool.stub(:candidate, candidate) do
      assert_equal ids.first, @pool.select(ids, task_type: :code_generation)
      assert_equal ids.last, @pool.select(ids, task_type: :chitchat)
    end
  end

  def test_models_configuration_declares_task_specific_strengths
    policy = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
    strengths = policy.fetch("task_strengths")

    assert_includes strengths.fetch("code_generation"), "coding"
    assert_includes strengths.fetch("architecture"), "reasoning"
    assert_includes strengths.fetch("chitchat"), "fast"
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
end
    policy = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
    strengths = policy.fetch("task_strengths")

    assert_includes strengths.fetch("code_generation"), "coding"
    assert_includes strengths.fetch("architecture"), "reasoning"
    assert_includes strengths.fetch("chitchat"), "fast"
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
end
    policy = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
    strengths = policy.fetch("task_strengths")

    assert_includes strengths.fetch("code_generation"), "coding"
    assert_includes strengths.fetch("architecture"), "reasoning"
    assert_includes strengths.fetch("chitchat"), "fast"
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
end
    policy = Master.load_yaml(File.join(Master::ROOT, "data", "models.yml"))
    strengths = policy.fetch("task_strengths")

    assert_includes strengths.fetch("code_generation"), "coding"
    assert_includes strengths.fetch("architecture"), "reasoning"
    assert_includes strengths.fetch("chitchat"), "fast"
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
end
