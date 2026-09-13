# frozen_string_literal: true

require_relative "test_helper"
require "unwrap_error"

class TestPhantomRecovery < Minitest::Test
  class FakeBus
    attr_reader :events

    def initialize
      @events = []
    end

    def publish(event, payload = {})
      @events << [event, payload]
    end
  end

  # Every scope these tests touch, not just :default. The occurrence counter is
  # per-scope process state and Minitest randomises order, so resetting one
  # scope left test_handle_escalates_then_halts able to inherit a count of 3
  # from a neighbour and halt on its first call.
  SCOPES = %i[default test clean ladder style mixed].freeze

  def setup
    SCOPES.each { |scope| Master::PhantomRecovery.reset!(scope:) }
  end

  # A real malfunction, not a phrasing complaint. These tests used "I'll help
  # you with that task now." — gaslighting_preamble, now style_only — so they
  # exercised the ladder with the one detector that must never reach it.
  MALFUNCTION = "the quick brown fox jumps over the lazy dog and keeps going " * 4

  def test_handle_escalates_then_halts
    bus = FakeBus.new
    text = MALFUNCTION

    first = Master::PhantomRecovery.handle(text, bus:, scope: :test)
    assert_equal :discard, first[:action]

    second = Master::PhantomRecovery.handle(text, bus:, scope: :test)
    assert_equal :escalate, second[:action]

    third = Master::PhantomRecovery.handle(text, bus:, scope: :test)
    assert_equal :halt, third[:action]
    assert bus.events.any? { |event, _| event == "phantom:halt" }
  end

  def test_clean_text_continues
    bus = FakeBus.new
    result = Master::PhantomRecovery.handle("Done. Tests pass.", bus:, scope: :clean)
    assert_equal :continue, result[:action]
  end

  # The ladder counts consecutive phantoms, not every phantom the process has
  # ever seen. A clean response between two phantoms must put the next one back
  # at step one; without that the third phantom a process encounters halts it,
  # and so does every phantom after that, for the life of the process.
  #
  # This is not a rare corner. gaslighting_preamble matches any reply opening
  # "I'll", "I can", "I would", "Let me" or "Sure," — so on a live box the
  # budget is spent within minutes and every turn after it returns an error.
  def test_a_clean_response_resets_the_ladder
    bus = FakeBus.new
    phantom = MALFUNCTION

    assert_equal :discard, Master::PhantomRecovery.handle(phantom, bus:, scope: :ladder)[:action]
    assert_equal :escalate, Master::PhantomRecovery.handle(phantom, bus:, scope: :ladder)[:action]
    assert_equal :continue, Master::PhantomRecovery.handle("Done. Tests pass.", bus:, scope: :ladder)[:action]

    assert_equal :discard, Master::PhantomRecovery.handle(phantom, bus:, scope: :ladder)[:action],
                 "a clean response did not reset the ladder — the next phantom escalated instead of discarding, " \
                 "so the graduated recovery in data/rules.yml can only ever run once per process"
  end

  # Resetting one conversation must not clear another's progress toward escalation.
  def test_the_reset_is_scoped
    bus = FakeBus.new
    phantom = MALFUNCTION

    Master::PhantomRecovery.handle(phantom, bus:, scope: :test)
    Master::PhantomRecovery.handle("Done. Tests pass.", bus:, scope: :clean)

    assert_equal :escalate, Master::PhantomRecovery.handle(phantom, bus:, scope: :test)[:action],
                 "a clean response in one scope reset the counter in another"
  end

  # A style complaint must never spend the ladder. gaslighting_preamble matches
  # any reply opening "I can", "I would", "Let me" or "Sure," — ordinary English
  # — so counting it ends the conversation over phrasing.
  def test_a_style_only_finding_never_escalates
    bus = FakeBus.new
    styled = "Let me take a look at that for you."

    5.times do
      result = Master::PhantomRecovery.handle(styled, bus:, scope: :style)
      assert_equal :continue, result[:action],
                   "a style-only finding drove the ladder — five ordinary replies halted the conversation"
    end

    refute bus.events.any? { |event, _| event == "phantom:halt" }
  end

  # Reported, not silently dropped: the dmesg lane and any critique still see it.
  def test_a_style_only_finding_is_still_detected_and_reported
    bus = FakeBus.new
    result = Master::PhantomRecovery.handle("Sure, here is what I found.", bus:, scope: :style)

    assert_includes result[:patterns], "gaslighting_preamble"
    assert bus.events.any? { |event, _| event == "phantom:detected" }
  end

  # A malfunction alongside a style hit is still a malfunction.
  def test_a_mixed_finding_still_escalates
    bus = FakeBus.new
    mixed = "Let me take a look. #{MALFUNCTION}"

    assert_equal :discard, Master::PhantomRecovery.handle(mixed, bus:, scope: :mixed)[:action],
                 "a real malfunction stopped counting because a style pattern appeared beside it"
  end

  # The list is law, so it lives in data/rules.yml rather than in this module.
  def test_the_style_only_list_comes_from_the_rules_file
    assert_includes Master::PhantomRecovery.style_only_detectors, "gaslighting_preamble"
    refute_includes Master::PhantomRecovery.style_only_detectors, "text_repetition_loop"
  end

  # The react loop ends when it can parse no call, so a broken one comes back
  # as the answer. That is the malfunction xml_tool_call_failure names.
  def test_a_malformed_tool_call_is_a_malfunction
    assert_includes Master::PhantomRecovery.detect(%(<tool_call>{"name": "ReadFile", "args": {</tool_call>))[:patterns],
                    "xml_tool_call_failure"
    assert_includes Master::PhantomRecovery.detect(%(Reading it now. <tool_call>{"name": "ReadFile"}))[:patterns],
                    "xml_tool_call_failure"
  end

  def test_a_well_formed_or_fenced_tool_call_is_not
    assert_nil Master::PhantomRecovery.detect(%(<tool_call>{"name": "ReadFile", "args": {}}</tool_call>))
    assert_nil Master::PhantomRecovery.detect("Call a tool with:\n```\n<tool_call>{...}\n```")
  end

  # The prose detectors used to compile into regexes matching only their own
  # sentence, which a reply quoting data/rules.yml would trip.
  def test_a_prose_detector_is_not_compiled_into_a_pattern
    assert_nil Master::PhantomRecovery.detect("tool returned nil twice in a row")
  end

  class ReactHarness
    include Master::Review::LLMDispatcher::ReactLoop

    NilTool = Class.new { def call(**) = nil }

    attr_reader :bus

    def initialize
      @tools = [NilTool.new]
      @tool_registry = {}
      @bus = FakeBus.new
      @sends = 0
    end

    attr_reader :sends

    def send_ruby_llm(*, **)
      @sends += 1
      Master::Result.ok(%(<tool_call>{"name": "NilTool", "args": {}}</tool_call>))
    end

    def tool_available_for_context?(_) = true
  end

  def test_the_react_loop_stops_after_two_empty_tool_rounds
    harness = ReactHarness.new
    result = Master::CLI::SubagentContext.stub(:permits?, true) do
      Master::Ground::Tool::Profile.stub(:allow?, true) do
        harness.send(:react_tool_loop, "m", [{ role: "user", content: "go" }], sys: nil, stream: false)
      end
    end

    assert_predicate result, :err?
    assert_equal 2, harness.sends, "the loop kept asking a model whose tools answered nothing"
    assert harness.bus.events.any? { |event, payload| event == "phantom:detected" && payload[:patterns] == ["empty_tool_response"] }
  end

  def react_call(harness, tool, name, args)
    harness.instance_variable_set(:@tools, [tool])
    Master::CLI::SubagentContext.stub(:permits?, true) do
      Master::Ground::Tool::Profile.stub(:allow?, true) { harness.send(:execute_react_tool, name, args) }
    end
  end

  def search_tool
    Master::Io::SearchFiles.allocate.tap do |tool|
      tool.define_singleton_method(:call) { |**kw| Master::Result.ok(kw.sort.to_h.inspect) }
    end
  end

  # The react loop called the Io tool with the model's keys, and SearchFiles
  # takes glob: and context_lines:, so the path and context its own wrapper
  # advertises raised a missing-keyword error.
  def test_a_react_call_goes_through_the_wrapper_parameters
    out = react_call(ReactHarness.new, search_tool, "SearchFiles", { "pattern" => "def", "path" => "lib", "context" => 1 })

    assert_includes out, "glob: \"lib\""
    assert_includes out, "context_lines: 1"
  end

  def test_a_guessed_parameter_name_is_healed_and_reported
    harness = ReactHarness.new
    out = react_call(harness, search_tool, "SearchFiles", { "regex" => "def", "dir" => "lib" })

    assert_includes out, "pattern: \"def\""
    assert harness.bus.events.any? { |event, payload| event == "tool:healed" && payload[:from] == :regex }
  end

  def test_an_unhealable_call_is_told_the_parameters
    out = react_call(ReactHarness.new, search_tool, "SearchFiles", { "needle" => "def" })

    assert_match(/error: .*missing keyword: pattern.*parameters are \(pattern\*, path, context\)/, out)
  end

  def test_judge_agent_calls_master_phantom_recovery
    source = File.read(File.join(Master::ROOT, "lib", "review", "agent.rb"))
    assert_includes source, "Master::PhantomRecovery.handle"
    refute_match(/(?<!Master::)PhantomRecovery\.handle/, source)
  end
end
