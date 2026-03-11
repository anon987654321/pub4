# frozen_string_literal: true

require_relative "test_helper"

class TestExecFlowDeepTraces < Minitest::Test
  def setup
    setup_db
  end

  def teardown
    teardown_db
  end

  def test_executor_flow_enriches_lint_trace_and_security_veto
    executor_result = MASTER::Result.ok(
      response: "done",
      steps: [
        { tool: "council_review", result: "security REJECT due to unsafe auth path" }
      ]
    )

    lint_stage = Object.new
    def lint_stage.call(_input)
      MASTER::Result.ok(axiom_violations: ["ONE_SOURCE"], zsh_violations: ["sudo"])
    end

    MASTER::Executor.stub(:call, executor_result) do
      MASTER::Stages::Lint.stub(:new, lint_stage) do
        result = MASTER::Pipeline.new(mode: :executor).call(text: "safe input")

        assert result.ok?, result.error
        assert_equal ["ONE_SOURCE"], result.value[:axiom_violations]
        assert_equal ["sudo"], result.value[:zsh_violations]
        assert_equal true, result.value[:council_security_veto]
      end
    end
  end

  def test_executor_error_short_circuits_before_lint
    lint_stage = Object.new
    def lint_stage.call(_input)
      raise "lint should not run"
    end

    MASTER::Executor.stub(:call, MASTER::Result.err("boom", category: :infrastructure)) do
      MASTER::Stages::Lint.stub(:new, lint_stage) do
        result = MASTER::Pipeline.new(mode: :executor).call(text: "safe input")

        assert result.err?
        assert_equal "boom", result.error
      end
    end
  end

  def test_normalize_result_strips_tool_blocks_for_clean_ux
    raw = MASTER::Result.ok(
      response: <<~TEXT
        Here is what I did:

        ```sh
        file_read "lib/a.rb"
        ```

        Final answer visible to user.
      TEXT
    )

    result = MASTER::Pipeline.new(mode: :executor).normalize_result(raw, "prompt")

    assert result.ok?
    assert_includes result.value[:rendered], "Final answer visible to user."
    refute_includes result.value[:rendered], "file_read"
  end
end
