# frozen_string_literal: true

require_relative "test_helper"

# Integration test - verifies runtime method existence
# This catches issues like the missing LLM.select_model that syntax checks miss
class TestIntegration < Minitest::Test
  def test_llm_public_methods_exist
    # Methods that must be callable
    assert MASTER::LLM.respond_to?(:ask), "LLM.ask must exist"
    assert MASTER::LLM.respond_to?(:pick), "LLM.pick must exist"
    assert MASTER::LLM.respond_to?(:select_available_model), "LLM.select_available_model must exist"
    assert MASTER::LLM.respond_to?(:tier), "LLM.tier must exist"
    assert MASTER::LLM.respond_to?(:budget_remaining), "LLM.budget_remaining must exist"
    assert MASTER::LLM.respond_to?(:circuit_closed?), "LLM.circuit_closed? must exist"
    assert MASTER::LLM.respond_to?(:record_cost), "LLM.record_cost must exist"
    assert MASTER::LLM.respond_to?(:models), "LLM.models must exist"
    assert MASTER::LLM.respond_to?(:model_tiers), "LLM.model_tiers must exist"
  end

  def test_executor_exists_and_callable
    assert defined?(MASTER::Executor), "Executor class must exist"
    assert MASTER::Executor.respond_to?(:call), "Executor.call must exist"
    
    executor = MASTER::Executor.new
    assert executor.respond_to?(:call), "Executor instance must have call method"
  end

  def test_pipeline_modes
    pipeline = MASTER::Pipeline.new(mode: :executor)
    assert pipeline.respond_to?(:call), "Pipeline must have call method"
    
    pipeline_stages = MASTER::Pipeline.new(mode: :stages)
    assert pipeline_stages.respond_to?(:call), "Pipeline stages mode must work"
  end

  def test_chamber_has_ideate
    chamber = MASTER::Chamber.new(llm: MASTER::LLM)
    assert chamber.respond_to?(:ideate), "Chamber must have ideate method"
    assert chamber.respond_to?(:deliberate), "Chamber must have deliberate method"
    assert chamber.respond_to?(:council_review), "Chamber must have council_review method"
  end

  def test_auto_fixer_exists
    assert defined?(MASTER::AutoFixer), "AutoFixer class must exist"
    fixer = MASTER::AutoFixer.new(mode: :conservative)
    assert fixer.respond_to?(:fix), "AutoFixer must have fix method"
    assert fixer.respond_to?(:rollback), "AutoFixer must have rollback method"
  end

  def test_web_module_exists
    assert defined?(MASTER::Web), "Web module must exist"
    assert MASTER::Web.respond_to?(:browse), "Web.browse must exist"
  end

  def test_speech_module_exists
    assert defined?(MASTER::Speech), "Speech module must exist"
    assert MASTER::Speech.respond_to?(:speak), "Speech.speak must exist"
    assert MASTER::Speech.respond_to?(:stream), "Speech.stream must exist"
    assert MASTER::Speech.respond_to?(:best_engine), "Speech.best_engine must exist"
  end

  def test_quality_gates_exist
    assert defined?(MASTER::Framework::QualityGates), "QualityGates must exist"
    assert MASTER::Framework::QualityGates.respond_to?(:check_gate), "QualityGates.check_gate must exist"
    assert MASTER::Framework::QualityGates.respond_to?(:gates), "QualityGates.gates must exist"
  end

  def test_result_pattern_used
    # Verify Result is used consistently
    result_ok = MASTER::Result.ok(test: true)
    assert result_ok.ok?, "Result.ok should be ok"
    assert_equal({ test: true }, result_ok.value)

    result_err = MASTER::Result.err("test error")
    assert result_err.err?, "Result.err should be err"
    assert_equal "test error", result_err.error
  end

  def test_all_requires_load
    # This test passes if we get here - master.rb loaded all requires
    assert defined?(MASTER::VERSION), "VERSION must be defined"
    assert defined?(MASTER::Pipeline), "Pipeline must be defined"
    assert defined?(MASTER::LLM), "LLM must be defined"
    assert defined?(MASTER::DB), "DB must be defined"
    assert defined?(MASTER::Session), "Session must be defined"
    assert defined?(MASTER::UI), "UI must be defined"
  end

  def test_commands_dispatch
    # Test that command dispatch handles known commands
    pipeline = MASTER::Pipeline.new
    
    # These should not raise
    result = MASTER::Commands.dispatch("help", pipeline: pipeline)
    assert_nil result, "help should return nil (output handled internally)"
    
    result = MASTER::Commands.dispatch("status", pipeline: pipeline)
    assert_nil result, "status should return nil"
    
    result = MASTER::Commands.dispatch("exit", pipeline: pipeline)
    assert_equal :exit, result, "exit should return :exit symbol"
  end

  def test_stages_exist
    stages = %i[Intake Compress Guard Route Council Ask Lint Render]
    stages.each do |stage|
      assert defined?(MASTER::Stages.const_get(stage)), "Stage #{stage} must exist"
      instance = MASTER::Stages.const_get(stage).new
      assert instance.respond_to?(:call), "Stage #{stage} must have call method"
    end
  end

  def test_dmesg_works
    assert defined?(MASTER::Dmesg), "Dmesg must exist"
    # Should not raise
    MASTER::Dmesg.log("test", message: "integration test")
  end

  def test_swarm_uses_new_api
    swarm = MASTER::Swarm.new(size: 2)
    assert swarm.respond_to?(:generate), "Swarm must have generate method"
  end

  def test_code_review_uses_new_api
    assert MASTER::CodeReview.respond_to?(:analyze), "CodeReview.analyze must exist"
    assert MASTER::CodeReview.respond_to?(:opportunities), "CodeReview.opportunities must exist"
  end
end
