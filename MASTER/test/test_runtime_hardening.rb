# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

class RuntimeHardeningTest < Minitest::Test
  FakeConfig = Struct.new(:model) do
    def [](key)
      key.to_s == "model" ? model : nil
    end
  end

  def test_execute_propagates_handler_error
    stage = Master::Now::Stages::Execute.new
    err = Master::Result.err("boom", category: :provider_error)
    ctx = Master::Now::PipelineContext.build(user_message: "test", handler: ->(_ctx) { err })
    result = stage.call(ctx)

    assert_instance_of Master::Result::Err, result
    assert_equal :provider_error, result.category
    assert_equal "boom", result.message
  end

  def test_circuit_breaker_honors_configured_rate_limit_category
    breaker = Master::Reach::CircuitBreaker.new(budget_max: 0, req_max: 1, rate_window_s: 60)

    breaker.check_rate!
    error = assert_raises(Master::Reach::CircuitBreaker::CircuitError) { breaker.check_rate! }

    assert_equal :rate_limit, error.category
    assert_match(/1 req\/min/, error.message)
  end

  def test_circuit_breaker_registry_does_not_increment_unselected_model_bucket
    registry = Master::Reach::CircuitBreakerRegistry.new(budget_max: 0, req_max: 1)
    model_a = registry.for("model-a")
    model_b = registry.for("model-b")

    registry.check_rate!("model-a")

    assert_raises(Master::Reach::CircuitBreaker::CircuitError) { model_a.check_rate! }
    model_b.check_rate!
  end

  def test_semantic_cache_restores_error_category_as_symbol
    Dir.mktmpdir do |dir|
      cache = Master::Reach::SemanticCache.new(root: dir, ttl: 60)
      first = cache.fetch("prompt", "model") { Master::Result.err("upstream", category: :provider_error) }
      second = cache.fetch("prompt", "model") { Master::Result.ok("should not run") }

      assert_instance_of Master::Result::Err, first
      assert_instance_of Master::Result::Err, second
      assert_equal :provider_error, second.category
      assert_equal "upstream", second.message
    end
  end


  def test_semantic_cache_persists_llm_manifest_for_restart
    Dir.mktmpdir do |dir|
      cache = Master::Reach::SemanticCache.new(root: dir)
      first = cache.fetch("prompt", "model") { Master::Result.ok("cached") }
      FileUtils.rm_rf(File.join(dir, ".master", "cache"))
      restarted = Master::Reach::SemanticCache.new(root: dir)
      second = restarted.fetch("prompt", "model") { Master::Result.ok("miss") }

      assert_equal "cached", first.value!
      assert_equal "cached", second.value!
      assert File.file?(File.join(dir, ".master", "llm_cache.yml"))
    end
  end

  def test_model_router_uses_provider_health_to_avoid_unhealthy_primary
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "data"))
      File.write(File.join(dir, "data", "models.yml"), <<~YAML)
        routing:
          enabled: true
        weights:
          quality: 1.0
          speed: 1.0
          cost: 1.0
        routes:
          exploration: cheap
          fallback_default: cheap
        models:
          cheap:
            - id: flaky-free
              score: { quality: 1.0, speed: 1.0, cost: 1.0 }
            - id: steady-free
              score: { quality: 0.8, speed: 1.0, cost: 1.0 }
      YAML
      health = Master::Now::Routing::ProviderHealth.new(path: File.join(dir, "provider_health.ndjson"))
      4.times { health.record(model: "flaky-free", status: :provider_error) }

      router = Master::Now::Routing::ModelRouter.new(
        config: FakeConfig.new("fallback-model"), root: dir, provider_health: health
      )

      assert_equal "steady-free", router.preferred(task_type: :exploration)
    end
  end
end
