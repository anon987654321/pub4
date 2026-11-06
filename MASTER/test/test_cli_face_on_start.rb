# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face"
require_relative "../lib/cli/face/window"

class TestCliFaceOnStart < Minitest::Test
  def test_the_face_is_never_a_separate_bin_master_entry_mode
    refute Master::CLI::Face::Window.asked?([])
    refute Master::CLI::Face::Window.asked?(["/face"])
    refute Master::CLI::Face::Window.asked?(["face"])
    refute Master::CLI::Face::Window.asked?(["-m", "/face"])
  end

  def test_face_overlay_uses_live_ready_motion_and_the_shared_law_setting
    seen = []
    session = Master::CLI::Session.allocate
    renderer = lambda do |**options|
      seen << options
      "compact face"
    end

    rendered = Master::CLI::Face.stub(:frame, renderer) do
      first = session.face_overlay_text
      sleep 0.001
      second = session.face_overlay_text
      [first, second]
    end

    assert_equal ["compact face", "compact face"], rendered
    assert_equal :ready, seen.first.fetch(:state)
    assert_equal 12, seen.first.fetch(:rows)
    assert_equal 32, seen.first.fetch(:cols)
    assert_equal false, seen.first.fetch(:color)
    assert_nil seen.first.fetch(:show_laws)
    assert_operator seen.last.fetch(:t), :>, seen.first.fetch(:t)
    assert_same seen.first.fetch(:motion), seen.last.fetch(:motion)
  end

  def test_terminal_face_intro_animates_at_a_portrait_termux_width
    session = Master::CLI::Session.allocate
    rendered = 0
    session.define_singleton_method(:face_overlay_text) do |cols:, swarm_budget: nil|
      rendered += 1
      Array.new(12, "x" * cols).join("\n")
    end
    session.define_singleton_method(:sleep) { |_seconds| }
    terminal = StringIO.new

    Master::Trace::Dmesg.stub(:terminal_write, ->(&block) { block.call(terminal) }) do
      TTY::Screen.stub(:height, 40) do
        session.send(:animate_face_intro, cols: 20, terminal_cols: 40, face_rows: 12)
      end
    end

    assert_equal Master::CLI::Session::FACE_INTRO_FRAMES, rendered
    assert_operator Master::CLI::Session::FACE_OVERLAY_MARKER.length, :<=, 40
  end

end
