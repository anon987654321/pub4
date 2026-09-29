# frozen_string_literal: true

require "test_helper"
require_relative "../lib/cli/routing/model_router"

class TestModelRouterConstrainedCapability < Minitest::Test
  FakePool = Struct.new(:seen) do
    def select(ids, task_type:)
      self.seen = [ids, task_type]
      ids.first
    end
  end

  FakeMap = Struct.new(:best) do
    def best_model_for(task)
      task == :council ? best : nil
    end
  end

  def test_constrained_routing_promotes_empirical_model_inside_quality_floor
    router = Master::CLI::Routing::ModelRouter.allocate
    router.instance_variable_set(:@rules, {
      "operation_constraints" => {
        "council" => { "min_quality" => 0.88, "preferred_tier" => "strong" },
      },
      "models" => {
        "strong" => [
          { "id" => "static", "score" => { "quality" => 0.99 } },
          { "id" => "empirical", "score" => { "quality" => 0.90 } },
        ],
      },
    })
    pool = FakePool.new
    router.instance_variable_set(:@compute_pool, pool)
    router.instance_variable_set(:@capability_map, FakeMap.new("empirical"))
    router.define_singleton_method(:healthy) { |models| models }

    selected = router.send(:constrained_for, operation: :council)

    assert_equal "empirical", selected
    assert_equal [["empirical", "static"], :council], pool.seen
  end
end
