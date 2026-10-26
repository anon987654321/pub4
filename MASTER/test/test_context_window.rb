# frozen_string_literal: true

require_relative "test_helper"
# Boot loads the gem in configure_providers!; the registry half of the test needs it.
require "ruby_llm"
require "master"

class TestContextWindow < Minitest::Test
  def test_public_surface_stays_below_god_class_threshold
    assert_operator Master::CLI::ContextWindow.public_instance_methods(false).size, :<=, 10
  end

  # A fake agent that lets a turn append while it is "summarising".
  class SlowAgent
    attr_reader :context
    def initialize(&during) = @during = during
    def ask(_prompt, context:)
      @context = context
      @during&.call
      "- summary"
    end
  end

  def session
    @session ||= Master::Trace::Session.new(root: Dir.mktmpdir("ctx-window"))
  end

def daily_logs(visitor:)
  Dir.mktmpdir("ctx-daily") do |root|
    10.times { |i| session.add_message(role: :user, content: "turn #{i}") }
    Fiber[:master_visitor] = visitor
    Master::CLI::ContextWindow.new(session:, agent: SlowAgent.new, root:).send(:compact!, :hard)
    return Dir.glob(File.join(root, ".master", "daily", "*.md")).map { |file| File.stat(file).mode & 0o777 }
  ensure
    Fiber[:master_visitor] = nil
  end
end

# A visitor's conversation is not the operator's day; the operator's log is owner-only.
def test_only_the_operators_compactions_reach_the_daily_log
  assert_empty daily_logs(visitor: true)
  assert_equal [0o600], daily_logs(visitor: nil)
end

  def test_compaction_summarises_a_prefix_and_keeps_the_tail_and_late_turns
    10.times { |i| session.add_message(role: :user, content: "turn #{i}") }
    agent = SlowAgent.new { session.add_message(role: :user, content: "late turn") }
    window = Master::CLI::ContextWindow.new(session:, agent:)

    assert window.send(:compact!, :hard).ok?

    assert_equal 6, agent.context.size, "the last four messages are not sent for summary"
    contents = session.messages.map { |m| m[:content] }
    assert_match(/Context compacted/, contents.first)
    assert_equal ["turn 6", "turn 7", "turn 8", "turn 9", "late turn"], contents.drop(1)
  end

  def test_compaction_keeps_decisions_files_and_open_work_structured
    6.times { |i| session.add_message(role: :user, content: "turn #{i}") }
    agent = Object.new
    agent.define_singleton_method(:ask) do |_prompt, context:|
      raise "unexpected context size" unless context.size == 2

      JSON.generate(
        goal: "repair MASTER",
        decisions: ["keep one execution slot"],
        facts: ["vm23 is the production host"],
        files: ["MASTER/lib/ops/control_plane.rb"],
        open_work: ["run the live check"],
        constraints: ["no GitHub Actions"],
        uncertainty: ["browser proof remains pending"],
      )
    end
    window = Master::CLI::ContextWindow.new(session:, agent:)

    assert_predicate window.send(:compact!, :hard), :ok?
    body = session.messages.first[:content]
    assert_match(/schema 1/, body)
    assert_match(/decisions:\n- keep one execution slot/, body)
    assert_match(/files:\n- MASTER\/lib\/ops\/control_plane\.rb/, body)
    assert_match(/open_work:\n- run the live check/, body)
  end

  def test_the_providers_input_count_raises_pressure_past_the_estimate
    session.add_message(role: :user, content: "short")
    agent = SlowAgent.new
    window = Master::CLI::ContextWindow.new(session:, agent:, model_context: 1_000)
    assert_equal :ok, window.check_and_compact!.value

    session.record_input_tokens(950)

    assert_equal :compacted, window.check_and_compact!.value
    assert_equal 0, session.token_pressure - session.token_est, "compaction clears the measured count"
  end

  def test_models_yml_states_a_window_and_the_registry_fills_the_rest
    assert_equal 64_000, Master.context_window("deepseek-chat")
    assert_equal 200_000, Master.context_window("claude-cli:claude-opus-5-5"), "a CLI lane keeps its stated window"
    assert_equal RubyLLM.models.find("x-ai/grok-4.3").context_window, Master.context_window("x-ai/grok-4.3")
    assert_equal Master::DEFAULT_CONTEXT_WINDOW, Master.context_window("nobody/never-listed")
  end
end
