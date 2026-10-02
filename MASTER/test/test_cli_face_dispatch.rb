# frozen_string_literal: true

require_relative "test_helper"

class TestCliFaceDispatch < Minitest::Test
  def test_face_pauses_the_repl_background_scanner
    session = Master::CLI::Session.allocate
    session.instance_variable_set(:@running, true)
    session.instance_variable_set(:@bg_thread, Object.new.tap { |o| def o.alive? = true })
    events = []

    session.define_singleton_method(:stop_background_loop) { events << :stop }
    session.define_singleton_method(:start_background_loop) { events << :start }

    Master::CLI::CommandRegistry.stub(:dispatch_face, -> { events << :face; "face0: closed" }) do
      assert_nil session.send(:run_face)
    end

    assert_equal %i[stop face start], events
  end

  def test_face_is_dispatched_synchronously_from_repl
    session = Master::CLI::Session.allocate
    called = false

    Master::CLI::CommandRegistry.stub(:dispatch_face, -> { called = true; "face0: closed" }) do
      assert_nil session.send(:dispatch_core_slash_command, "/face")
    end

    assert called
  end
end
