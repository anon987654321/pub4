# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/stages/enhance"
require_relative "../lib/cli/skills"

class EnhanceStageTest < Minitest::Test
  class Agent
    attr_reader :input

    def initialize(response)
      @response = response
    end

    def ask_once(input, **)
      @input = input
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

    result = stage.call(ctx("please explain this method to me carefully"))

    assert result.ok?
    assert_equal "please explain this method to me carefully", result.value!.message
    refute result.value!.key?(:original_message)
  end

  def test_changed_nonempty_editor_output_replaces_the_message
    stage = Master::CLI::Stages::Enhance.new(
      agent: Agent.new('{"enhanced":"explain this","changed":true}'),
    )

    result = stage.call(ctx("please explain this method to me carefully"))

    assert result.ok?
    assert_equal "explain this", result.value!.message
    assert_equal "please explain this method to me carefully", result.value!.original_message
  end

  def test_changed_false_editor_output_keeps_the_original_message
    stage = Master::CLI::Stages::Enhance.new(
      agent: Agent.new('{"enhanced":"ignored","changed":false}'),
    )

    result = stage.call(ctx("please explain this method to me carefully"))

    assert result.ok?
    assert_equal "please explain this method to me carefully", result.value!.message
  end
  class EventBus
    attr_reader :events

    def initialize = @events = []
    def publish(name, payload = {}) = @events << [name, payload]
  end

  def skill_runtime(root, bus)
    data_dir = File.join(root, "data")
    FileUtils.mkdir_p(data_dir)
    File.write(File.join(data_dir, "patterns.yml"), <<~YAML)
      skills_registry:
        skills:
          - name: repair-skill
            description: Repair workflow
            triggers: ["repair this code"]
            body: "Run focused tests and preserve unrelated changes."
    YAML
    Master::CLI::Skills.new(root:, event_bus: bus, approval_path: File.join(root, "approvals.yml")).tap(&:discover!)
  end

  def test_eligible_skill_is_not_lost_when_editor_returns_changed_false
    Dir.mktmpdir do |root|
      bus = EventBus.new
      skills = skill_runtime(root, bus)
      agent = Agent.new('{"enhanced":"ignored","changed":false}')
      stage = Master::CLI::Stages::Enhance.new(agent:, event_bus: bus, skills:)

      result = stage.call(ctx("Please help me repair this code today."))

      assert result.ok?
      assert_equal "Please help me repair this code today.", agent.input
      assert_includes result.value!.message, "[skill: repair-skill]"
      assert_includes result.value!.message, "Run focused tests and preserve unrelated changes."
      assert_equal 1, bus.events.count { |name, _| name == "skills:triggered" },
                   "the skills registry owns the trigger receipt; the stage must not emit a duplicate"
    end
  end

  def test_editor_cannot_rewrite_or_remove_the_skill_body
    Dir.mktmpdir do |root|
      bus = EventBus.new
      skills = skill_runtime(root, bus)
      agent = Agent.new('{"enhanced":"Summarize the repair request.","changed":true}')
      stage = Master::CLI::Stages::Enhance.new(agent:, event_bus: bus, skills:)

      result = stage.call(ctx("Please help me repair this code today."))

      assert result.ok?
      assert_equal "Please help me repair this code today.", agent.input
      assert_equal "Summarize the repair request.", result.value!.message.lines.first.strip
      assert_includes result.value!.message, "Run focused tests and preserve unrelated changes."
      assert_equal "Please help me repair this code today.", result.value!.original_message
    end
  end


end
