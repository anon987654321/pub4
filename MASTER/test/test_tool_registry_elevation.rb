# frozen_string_literal: true

require "test_helper"

class ToolRegistryElevationTest < Minitest::Test
  class RegistryHarness
    include Master::Review::LLMDispatcher::ToolRegistry

    attr_accessor :tools, :tool_registry, :config, :model_router, :session, :bus

    def initialize
      @tools = [Master::Io::Shell.allocate, Master::Io::ReadFile.allocate]
      @tool_registry = {
        "Shell" => { "tier" => "dangerous" },
        "ReadFile" => { "tier" => "safe" },
      }
      @config = Data.define(:model).new("test/model")
      @model_router = Class.new do
        def tier_for_model(_) = "standard"
      end.new
      @session = Data.define(:topic, :messages).new(nil, [])
      @bus = nil
    end

    def tool_capable?(_) = true
  end

  def test_llm_tools_cache_is_partitioned_by_elevation
    harness = RegistryHarness.new

    Fiber[:master_visitor] = false
    Fiber[:master_elevated] = true
    elevated = harness.send(:llm_tools, "test/model").map { |tool| tool.class.name }

    Fiber[:master_elevated] = false
    standard = harness.send(:llm_tools, "test/model").map { |tool| tool.class.name }

    assert_includes elevated, "Master::Io::LLM::Shell"
    refute_includes standard, "Master::Io::LLM::Shell"
    assert_includes standard, "Master::Io::LLM::ReadFile"
  ensure
    Fiber[:master_visitor] = nil
    Fiber[:master_elevated] = nil
    Fiber[:master_paired] = nil
  end

  def test_paired_visitor_does_not_receive_shell
    harness = RegistryHarness.new
    Fiber[:master_visitor] = true
    Fiber[:master_paired] = true
    names = harness.send(:llm_tools, "test/model").map { |tool| tool.class.name }

    refute_includes names, "Master::Io::LLM::Shell"
  ensure
    Fiber[:master_visitor] = nil
    Fiber[:master_paired] = nil
  end
end
