# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/stages/enhance"

class EnhanceStageTest < Minitest::Test
  class Agent
    def initialize(response)
      @response = response
    end

    def ask_once(*)
      @response
    end
  end

  def ctx(message)
    Master::CLI::PipelineContext.build(user_message: message, intent: :llm, message:)
  end

  def test_changed_empty_editor_output_preserves_the_original_message
    stage = Master::CLI::Stages::Enhance.new(
      agent: Agent.new('{"enhanced":"","changed":true}'),
    )

    result = stage.call(ctx("please explain this carefully"))

    assert result.ok?
    assert_equal "please explain this carefully", result.value!.message
    refute result.value!.key?(:original_message)
  end

  def test_changed_nonempty_editor_output_replaces_the_message
    stage = Master::CLI::Stages::Enhance.new(
      agent: Agent.new('{"enhanced":"explain this","changed":true}'),
    )

    result = stage.call(ctx("please explain this carefully"))

    assert result.ok?
    assert_equal "explain this", result.value!.message
    assert_equal "please explain this carefully", result.value!.original_message
  end

  def test_changed_false_editor_output_keeps_the_original_message
    stage = Master::CLI::Stages::Enhance.new(
      agent: Agent.new('{"enhanced":"ignored","changed":false}'),
    )

    result = stage.call(ctx("please explain this carefully"))

    assert result.ok?
    assert_equal "please explain this carefully", result.value!.message
  end
end
