# frozen_string_literal: true

require_relative "test_helper"

class TestCapabilityMap < Minitest::Test
  def setup
    @map = Master::Core::Routing::CapabilityMap.new
  end

  def test_recording_outcomes
    @map.record_outcome("gemma", :coding, true, { latency: 1.2 })
    @map.record_outcome("gemma", :coding, false, { latency: 1.5 })
    
    assert_equal 0.5, @map.success_rate("gemma", :coding)
    assert_equal 1.35, @map.scores["gemma"][:coding][:metrics][:latency]
  end

  def test_best_model_selection
    @map.record_outcome("gemma", :coding, true)
    @map.record_outcome("qwen", :coding, false)
    
    assert_equal "gemma", @map.best_model_for(:coding)
  end
end
