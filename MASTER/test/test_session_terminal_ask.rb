# frozen_string_literal: true

require "test_helper"
require "stringio"

# The interactive session is the one surface that answers a fold's Request.
# These pin the three ways it declines: no terminal, a thread the turn does not
# own, and anything short of a yes.
class SessionTerminalAskTest < Minitest::Test
  Renderer = Struct.new(:lines) do
    def render(text, mode:) = "#{mode}: #{text}"
  end

  # A session with only the refs the asker reads, and the asker opened up.
  class AskSession < Master::CLI::Session
    def initialize(refs)
      @refs = refs
    end

    public :terminal_ask
  end

  # The session approves on its own unless config says auto_approve: false
  # (8c61ec8b4); these pin the reader the operator gets when it does.
  def session(auto_approve: false)
    AskSession.new(Struct.new(:renderer, :config).new(Renderer.new, { "auto_approve" => auto_approve }))
  end

  def with_terminal(input)
    stdin, stdout = $stdin, $stdout
    $stdin = StringIO.new(input).tap { |io| def io.tty? = true }
    $stdout = StringIO.new.tap { |io| def io.tty? = true }
    yield $stdout
  ensure
    $stdin, $stdout = stdin, stdout
  end

  def test_a_pipe_builds_no_asker
    assert_nil session.terminal_ask(Thread.current)
  end

  def test_the_turn_thread_reads_the_answer_from_the_terminal
    with_terminal("y\n") do |out|
      asker = session.terminal_ask(Thread.current)
      assert_equal "y", asker.call(prompt: "run `git push`?")
      assert_match(/run `git push`\? \[y\/N\]/, out.string)
    end
  end

  def test_the_turn_thread_can_choose_a_multi_option_approval
    with_terminal("1\n") do |out|
      asker = session.terminal_ask(Thread.current)
      answer = asker.call(
        prompt: "web_fetch: https://example.com",
        options: [
          { name: "approve once", value: "approve" },
          { name: "deny this request", value: "deny" },
        ],
      )
      assert_equal "approve", answer
      assert_match(/1\) approve once/, out.string)
      assert_match(/2\) deny this request/, out.string)
    end
  end

  def test_hash_approval_choices_do_not_raise_symbol_to_integer_type_error
    with_terminal("2\n") do |out|
      asker = session.terminal_ask(Thread.current)
      answer = asker.call(
        prompt: "Choose the browser action",
        options: { approve: "approve", deny: "deny" },
      )

      assert_equal "deny", answer
      assert_match(/1\) approve/, out.string)
      assert_match(/2\) deny/, out.string)
    end
  end

  def test_single_hash_choice_is_normalized
    with_terminal("1\n") do |out|
      asker = session.terminal_ask(Thread.current)
      answer = asker.call(
        prompt: "Choose an action",
        options: { name: "approve once", value: "approve" },
      )

      assert_equal "approve", answer
      assert_match(/1\) approve once/, out.string)
    end
  end

  def test_auto_approve_takes_the_approve_choice_and_logs_it
    with_terminal("") do |out|
      asker = session(auto_approve: true).terminal_ask(Thread.current)
      answer = asker.call(prompt: "push?", options: [{ name: "deny", value: "deny" }, { name: "ok", value: "approve" }])

      assert_equal "approve", answer
      assert_match(/ask0 at fold0: approved, push\?/, out.string)
    end
  end

  def test_a_thread_the_turn_spawned_is_not_answered
    with_terminal("y\n") do
      asker = session.terminal_ask(Thread.current)
      refute_equal "y", Thread.new { asker.call(prompt: "push?") }.value
    end
  end
end
