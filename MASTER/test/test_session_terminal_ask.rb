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

  def session
    Master::CLI::Session.allocate.tap do |s|
      s.instance_variable_set(:@refs, Struct.new(:renderer).new(Renderer.new))
    end
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
    assert_nil session.send(:terminal_ask, Thread.current)
  end

  def test_the_turn_thread_reads_the_answer_from_the_terminal
    with_terminal("y\n") do |out|
      asker = session.send(:terminal_ask, Thread.current)
      assert_equal "y", asker.call(prompt: "run `git push`?")
      assert_match(/run `git push`\? \[y\/N\]/, out.string)
    end
  end

  def test_a_thread_the_turn_spawned_is_not_answered
    with_terminal("y\n") do
      asker = session.send(:terminal_ask, Thread.current)
      refute_equal "y", Thread.new { asker.call(prompt: "push?") }.value
    end
  end
end
