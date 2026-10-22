# frozen_string_literal: true

require_relative "test_helper"
require "json"
require "review/llm_dispatcher/claude_stream"

class TestClaudeStream < Minitest::Test
  Stream = Master::Review::LLMDispatcher::ClaudeStream

  def delta(text)
    event = { type: "content_block_delta", delta: { type: "text_delta", text: } }
    "#{JSON.generate(type: "stream_event", event:)}\n"
  end

  def run_stream(pieces)
    seen = +""
    stream = Stream.new { |text| seen << text }
    pieces.join.chars.each_slice(7).map(&:join).each { |chunk| stream.feed(chunk) }
    stream.finish
    seen
  end

  # Events arrive split anywhere across pipe reads; the text comes out whole and in order.
  def test_text_deltas_pass_through_across_split_chunks
    events = [JSON.generate(type: "system") + "\n", delta("Hei, "), delta("Johann. "), delta("Dette går fint."),
              JSON.generate(type: "result", result: "ignored here") + "\n"]

    assert_equal "Hei, Johann. Dette går fint.", run_stream(events)
  end

  # A ReAct tool call is for MASTER, not the operator: nothing from it reaches the screen.
  def test_a_tool_call_is_never_shown
    shown = run_stream([delta("Let me look. "), delta("<tool_"), delta("call>{\"name\": \"WebSearch\"}"),
                        delta("</tool_call> and more")])

    assert_equal "Let me look. ", shown
  end

  # Angle brackets that cannot begin a tool call are ordinary text, released as soon as that is clear.
  def test_other_angle_brackets_are_text
    assert_equal "a <b> c and x < y", run_stream([delta("a <b"), delta("> c"), delta(" and x <"), delta(" y")])
  end

  def test_exec_hands_stdout_to_a_listener_while_returning_it_whole
    seen = []
    out, _err, status = Master::Io::Exec.capture3(
      RbConfig.ruby, "-e", "print 'one'; $stdout.flush; sleep 0.2; print 'two'", on_stdout: ->(chunk) { seen << chunk }
    )

    assert status.success?
    assert_equal "onetwo", out
    assert_equal "onetwo", seen.join
    assert_operator seen.size, :>=, 2, "the first chunk arrived before the child finished"
  end
end
