# frozen_string_literal: true

require_relative "test_helper"

class TestCliTerminalFace < Minitest::Test
  def test_normal_prompt_draws_the_face_above_the_existing_shell_prompt
    session = Master::CLI::Session.allocate
    refs = Struct.new(:agent, :session, :renderer, :bus).new(
      Struct.new(:model).new("test-model"),
      Struct.new(:phase, :token_est, :cost).new(:idle, 0, 0),
      nil,
      nil
    )
    session.instance_variable_set(:@refs, refs)
    session.instance_variable_set(:@last_ok, true)
    session.instance_variable_set(:@violations, 0)
    session.instance_variable_set(:@violations_mutex, Mutex.new)
    session.define_singleton_method(:terminal_face) { "⠁⠂⠄\n⠈⠐⠠" }

    renderer = Object.new
    renderer.define_singleton_method(:prompt_line) { |*| ["state0", "% "] }
    refs.renderer = renderer

    $stdout.stub(:tty?, true) do
      output = capture_io { session.send(:normal_prompt) }.first
      assert_includes output, "⠁⠂⠄"
      assert_includes output, "state0"
    end
  end
end
