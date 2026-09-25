# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face"
require_relative "../lib/cli/face/window"

# The terminal face owns the whole viewport; recent jobs, status and input
# overlay its bottom four rows. Motion stays within a readable front-facing turn.
class TestFaceWindowLayout < Minitest::Test
  Quiet = Struct.new(:missing) do
    def available? = missing.nil?
  end
  BRAILLE = /[⠁-⣿]/

  def window
    Master::CLI::Face::Window.new(turn: ->(_) {}, ear: Quiet.new(nil), mouth: Quiet.new(nil),
                                  input: StringIO.new, output: StringIO.new, size: -> { [30, 60] })
  end

  # The painted lines, keyed by their row, with the escapes stripped.
  def rows_of(screen)
    screen.scan(/\e\[(\d+);1H(.*?)\e\[K/).to_h { |row, text| [row.to_i, text.gsub(/\e\[[0-9;?]*[A-Za-z]/, "")] }
  end

  def test_the_face_uses_the_full_viewport
    painted = rows_of(window.screen(30, 60, 2.0))
    head_rows = painted.select { |_, text| text.match?(BRAILLE) }.keys
    refute_empty head_rows, "the head drew nothing"
    assert_operator head_rows.max, :>, 10, "the face is still confined to the top third"
  end

  def test_the_renderer_receives_the_full_terminal_height
    seen_rows = nil
    renderer = ->(**kwargs) do
      seen_rows = kwargs.fetch(:rows)
      Array.new(seen_rows, " ").join("\n")
    end

    Master::CLI::Face.stub(:frame, renderer) do
      window.screen(30, 60, 2.0)
    end

    assert_equal 30, seen_rows
  end

  def test_the_column_under_the_head_keeps_three_jobs
    face = window
    5.times { |i| face.send(:note_job, ["job #{i}"]) }
    text = rows_of(face.screen(30, 60, 2.0)).values.join("\n")
    assert_includes text, "job 4"
    assert_includes text, "job 2"
    refute_includes text, "job 1", "more than three jobs stayed under the head"
  end

  def test_every_row_of_the_window_is_painted
    painted = rows_of(window.screen(30, 60, 2.0))
    assert_equal (1..30).to_a, painted.keys.sort
  end

  def test_a_failed_turn_does_not_start_picture_work
    face = Master::CLI::Face::Window.new(
      turn: ->(_) { Master::Result.err("talk0: empty response", category: :provider_error) },
      ear: Quiet.new(false),
      mouth: Quiet.new(false),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
    )

    face.stub(:picture, ->(_) { flunk("picture work started after a failed turn") }) do
      face.send(:answer, "Bug and ember lay out.")
    end

    text = rows_of(face.screen(24, 80, 1.0)).values.join("\n")
    assert_includes text, "talk0: empty response"
  end

  def test_a_successful_turn_can_start_picture_work
    face = Master::CLI::Face::Window.new(
      turn: ->(_) { Master::Result.ok("Reply") },
      ear: Quiet.new(false),
      mouth: Quiet.new(false),
      input: StringIO.new,
      output: StringIO.new,
      size: -> { [24, 80] },
    )
    pictured = nil

    face.stub(:picture, ->(text) { pictured = text }) do
      face.send(:answer, "Bug and ember lay out.")
    end

    assert_equal "Bug and ember lay out.", pictured
  end

  def test_motion_keeps_the_face_within_a_readable_turn
    motion = Master::CLI::Face::Motion.new(seed: 7)
    yaw = 0.0

    120.times do |i|
      yaw = motion.step(state: :idle, t: (i + 1) / 15.0).yaw
      assert_operator yaw.abs, :<=, 0.5
    end
  end
end
