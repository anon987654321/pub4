# frozen_string_literal: true

require_relative "test_helper"

class TestCliFaceOnStart < Minitest::Test
  def session = Master::CLI::Session.allocate

  def with_tty(value, &)
    $stdin.stub(:tty?, value) { $stdout.stub(:tty?, value, &) }
  end

  def test_it_is_on_by_default_in_the_data
    assert_equal true, Master.patterns_config.fetch("cli").fetch("face_on_start")
  end

  def test_a_bare_interactive_start_opens_the_face
    with_tty(true) { assert session.face_on_start?(nil) }
  end

  def test_a_message_a_pipe_or_the_opt_out_keeps_the_plain_shell
    with_tty(true) { refute session.face_on_start?("read CLAUDE.md") }
    with_tty(false) { refute session.face_on_start?(nil) }
    ENV["MASTER_FACE_ON_START"] = "0"
    with_tty(true) { refute session.face_on_start?(nil) }
  ensure
    ENV.delete("MASTER_FACE_ON_START")
  end
end
