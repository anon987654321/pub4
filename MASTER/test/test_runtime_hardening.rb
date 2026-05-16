# frozen_string_literal: true

require_relative "test_helper"

class RuntimeHardeningTest < Minitest::Test
  def test_execute_propagates_handler_error
    stage = Master::Now::Stages::Execute.new
    err = Master::Result.err("boom", category: :provider_error)
    result = stage.call(handler: ->(_ctx) { err })

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
end
