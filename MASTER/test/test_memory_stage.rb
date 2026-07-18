# frozen_string_literal: true

require_relative "test_helper"
require "master"

# Guards Master::CLI::Stages::Memory against the silent-death regression where
# `text` was undefined in #call, raising NameError on every turn and swallowing
# it as a memory:error event so nothing was ever remembered.
class TestMemoryStage < Minitest::Test
  # Records remember calls and lets the stage run without a real store.
  class FakeMemory
    attr_reader :saved

    def initialize = @saved = []
    def remember(key, value, type: "general") = @saved << { key:, value:, type: }
  end

  # Captures published events so we can assert no error was swallowed.
  class FakeBus
    attr_reader :events

    def initialize = @events = []
    def publish(event, **payload) = @events << [event, payload]
  end

  def setup
    @memory = FakeMemory.new
    @bus    = FakeBus.new
    @stage  = Master::CLI::Stages::Memory.new(memory: @memory, event_bus: @bus)
  end

  def test_extracts_and_remembers_user_text
    ctx = Master::CLI::PipelineContext.build(user_message: "I prefer terse replies.")
    result = @stage.call(ctx)
    assert result.ok?
    refute_includes @bus.events.map(&:first), "memory:error"
    assert @memory.saved.any? { |m| m[:value].include?("terse replies") }, "expected preference remembered"
  end

  def test_no_error_event_on_plain_message
    @stage.call(Master::CLI::PipelineContext.build(user_message: "what is the time"))
    assert_empty @bus.events.select { |event, _| event == "memory:error" }
  end

  def test_records_episode_when_voice_present
    ctx = Master::CLI::PipelineContext.build(user_message: "hello there", voice: "ms-MY-OsmanNeural", rendered: "hi back")
    @stage.call(ctx)
    assert @memory.saved.any? { |m| m[:key].start_with?("episode_") }, "expected voice episode recorded"
  end
end
