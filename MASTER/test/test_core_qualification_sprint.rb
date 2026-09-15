# frozen_string_literal: true

require "minitest/autorun"
module Master; module Core; module Routing; end; end; end
module Master; module Core; module Execution; end; end; end

require_relative "../lib/core/routing/capability/capability_map"
require_relative "../lib/core/execution/bench/master_bench"
require_relative "../lib/core/execution/bench/qualification/qualification_runner"

class TestQualificationSprint < Minitest::Test
  def setup
    @cap_map = Master::Core::Routing::CapabilityMap.new
    @bench = Master::Core::Execution::MasterBench.new
    # Add some test cases to the bench
    @bench.add_case("Fix Rails Controller", ->(res) { res == :success ? 1.0 : 0.0 })
    @bench.add_case("Refactor Model", ->(res) { res == :success ? 1.0 : 0.0 })
  end

  def test_qualification_flow
    models = ["glm-5.2", "kimi-k2", "deepseek-v4"]
    
    models.each do |m_id|
      runner = Master::Core::Execution::QualificationRunner.new(m_id, @bench, @cap_map)
      result = runner.run
      
      assert_equal m_id, result[:model]
      assert_kind_of Float, result[:overall_score]
      assert @cap_map.scores.key?(m_id)
    end
  end
end
