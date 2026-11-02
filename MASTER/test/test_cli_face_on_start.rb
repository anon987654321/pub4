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

  def test_face_overlay_uses_the_shared_ascii_renderer
    seen = nil
    rendered = Master::CLI::Face.stub(:frame, lambda { |**options|
      seen = options
      "compact face"
    }) do
      Master::CLI::Session.allocate.face_overlay_text
    end

    assert_equal "compact face", rendered
    assert_equal :idle, seen.fetch(:state)
    assert_equal 12, seen.fetch(:rows)
    assert_equal 32, seen.fetch(:cols)
    assert_equal false, seen.fetch(:color)
    assert_equal false, seen.fetch(:show_laws)
  end
end
