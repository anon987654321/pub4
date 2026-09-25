# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/cli/face"
require_relative "../lib/cli/face/window"

# The terminal face keeps its head in the top third of the window and the
# last three jobs under it (7552cab9c). Window#screen draws the whole window
# as escape sequences, so the layout is checked here without a microphone.
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

  def test_the_head_stays_in_the_top_third
    painted = rows_of(window.screen(30, 60, 2.0))
    head_rows = painted.select { |_, text| text.match?(BRAILLE) }.keys
    refute_empty head_rows, "the head drew nothing"
    assert_operator head_rows.max, :<=, 10, "the head reached below the top third"
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
end
