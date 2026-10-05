# frozen_string_literal: true

require_relative "test_helper"
require "fix/fix_loop/pass_runner"

class TestLlmStageFailure < Minitest::Test
  def test_semantic_adapter_load_failure_is_not_silently_dropped
    runner = Master::Fix::FixLoop::PassRunner.allocate
    Master::Fix::FixLoop::PassRunner.stub_const(:LlmStage, Master::Fix::FixLoop::PassRunner::LlmStage) do
      Master::Law.stub(:rules, {}) do
        Law.stub(:rules, {}) do
          Law.stub(:load_all, ->(_dir) { raise "law registry exploded" }) do
            error = assert_raises(RuntimeError) do
              runner.send(:semantic_rule_adapters, { "SEMANTIC_FAILURE" => [{}] }, [])
            end
            assert_match(/semantic rule adapter load failed/, error.message)
          end
        end
      end
    end
  end
end
