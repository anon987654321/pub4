# frozen_string_literal: true

require_relative "test_helper"

class TestOpenCrabsGuards < Minitest::Test
  class EchoTool
    NAME = "echo_tool"
    def call(**) = Master::Result.ok("same")
  end

  class ReadTool
    NAME = "read_file"
    def call(**) = Master::Result.ok("same")
  end

  class Wrapper
    include Master::Io::LLM::ToolForwarding
    def run(**args) = forward(**args)
  end

  def setup
    Fiber[:master_tool_streak] = nil
    Fiber[:master_tree_seen] = nil
  end

  def teardown
    Fiber[:master_tool_streak] = nil
    Fiber[:master_tree_seen] = nil
  end

  def replaced(content, old_string, new_string)
    Master::Io::StrReplace.allocate.resolve_updated_content(content, old_string, new_string, "f.txt")
  end

  def test_a_tab_the_model_typed_as_spaces_still_matches_its_line
    assert_equal "\tx = 2\n", replaced("\tx = 1\n", "  x = 1", "\tx = 2")
  end

  def test_a_tolerant_match_in_two_places_refuses
    result = replaced("\tx = 1\n\tx = 1\n", "   x = 1", "y")
    assert result.err?
    assert_match(/matches 2 places/, result.message)
  end

  def test_curly_quotes_match_straight_ones
    assert_equal "puts \"bye\"\n", replaced("puts \u201Chi\u201D\n", "puts \"hi\"", "puts \"bye\"")
  end

  def test_a_replacement_keeps_its_backslashes
    assert_equal "\\0\\0\n", replaced("a\n", "a", "\\0\\0")
  end

  def test_a_last_line_without_a_newline_does_not_gain_one
    assert_equal "a\nB", replaced("a\n  b", "  b\n", "B")
  end

  def test_nothing_close_is_still_not_found
    assert_match(/pattern not found/, replaced("a\n", "zzz", "b").message)
  end

  def test_a_third_identical_call_is_answered_not_run
    wrapper = Wrapper.new(EchoTool.new)
    assert_equal "same", wrapper.run(command: "ls 1")
    assert_equal "same", wrapper.run(command: "ls  2")
    assert_match(/\AError: the same echo_tool call/, wrapper.run(command: "ls 3"))
    assert_equal "same", wrapper.run(command: "pwd")
  end

  # Source work waits for a Tree or ListDir call in the turn; once the model
  # has oriented, rereading is the method and never trips the repeat guard.
  def test_rereading_a_file_is_not_a_loop
    wrapper = Wrapper.new(ReadTool.new)
    assert_match(/\AError: tree required before source work: a\.rb/, wrapper.run(path: "a.rb"))
    Fiber[:master_tree_seen] = true
    4.times { assert_equal "same", wrapper.run(path: "a.rb") }
  end

  class ReadFile
    NAME = "read_file"
  end

  class Shell
    NAME = "zsh"
  end

  # The tools and the registry LLMDispatcher#initialize gives the loop;
  # tool_registry_name reads the registry for every tool name.
  class ReactHost
    include Master::Review::LLMDispatcher::ReactLoop

    def initialize(tools)
      @tools = tools
      @tool_registry = {}
    end
  end

  def react_host
    ReactHost.new([ReadFile.new, Shell.new])
  end

  def test_a_tool_name_that_differs_only_in_spelling_reaches_its_tool
    assert_instance_of ReadFile, react_host.send(:find_react_tool, "read_file")
    assert_instance_of ReadFile, react_host.send(:find_react_tool, "readFile")
    assert_instance_of Shell, react_host.send(:find_react_tool, "ZSH")
    assert_nil react_host.send(:find_react_tool, "write_file")
  end

  def test_an_unknown_tool_name_hears_the_nearest_names
    assert_match(/nearest: ReadFile/, react_host.send(:unknown_tool_result, "ReedFile"))
  end

  def test_a_second_ctrl_c_inside_the_window_closes
    cli = Master::CLI::Session.allocate
    refute cli.send(:close_requested?)
    assert cli.send(:close_requested?)
  end

  class RecordingBus
    attr_reader :events
    def initialize = @events = []
    def publish(name, _payload = {}) = @events << name
  end

  class PayloadBus
    attr_reader :events
    def initialize = @events = []
    def publish(name, payload = {}) = @events << [name, payload]
  end

  def test_public_tool_events_hash_private_subjects_and_errors
    secret = "/private/home/member.txt"
    bus = PayloadBus.new
    tool = Object.new
    tool.define_singleton_method(:call) { |**| Master::Result.err("cannot read #{secret}", category: :infrastructure) }
    wrapper = Wrapper.new(tool, bus:)

    wrapper.run(path: secret)

    call = bus.events.find { |name, _| name == "tool:call" }.last
    returned = bus.events.find { |name, _| name == "tool:return" }.last
    refute call.key?(:subject)
    assert_equal "path", call[:subject_kind]
    assert_equal Digest::SHA256.hexdigest(secret), call[:subject_digest]
    refute_includes call.inspect, secret
    refute returned.key?(:error)
    assert_equal Digest::SHA256.hexdigest("cannot read #{secret}"), returned[:error_digest]
    refute_includes returned.inspect, secret
  end

  def test_a_refused_repeat_is_bracketed_so_dmesg_prints_it
    bus = RecordingBus.new
    wrapper = Wrapper.new(EchoTool.new, bus:)
    3.times { wrapper.run(command: "ls") }
    assert_equal %w[tool:call tool:failed tool:return], bus.events.last(3)
  end

  def stream(chunks, width: 20)
    cli = Master::CLI::Session.allocate
    state = { width: }
    chunks.map { |chunk| cli.send(:wrap_stream, chunk, state) }.join
  end

  def test_a_streamed_reply_preserves_authored_paragraph_lines
    source = "the quick brown fox jumps over the lazy dog\nand the next line stays next\n"
    assert_equal source, stream([source], width: 20)
  end

  def test_stream_chunks_add_no_hard_breaks
    assert_equal "hello world", stream(["hello wor", "ld"])
    assert_equal "a" * 30, stream(["a" * 15, "a" * 15])
  end

  def test_fenced_code_and_table_rows_stream_untouched
    code = "```\nx = a line of code longer than the measure\n```\n"
    row = "| a | b | c | d | e | f | g |\n"
    assert_equal code + row, stream([code, row])
  end

  def test_the_prompt_path_gets_what_the_screen_leaves
    renderer = Master::Voice::Renderer.new(config: {})
    TTY::Screen.stub(:width, 200) { assert_equal 44, renderer.send(:prompt_path_budget) }
    TTY::Screen.stub(:width, 50) { assert_equal 44, renderer.send(:prompt_path_budget) }
    TTY::Screen.stub(:width, 30) { assert_equal 29, renderer.send(:prompt_path_budget) }
  end
end
