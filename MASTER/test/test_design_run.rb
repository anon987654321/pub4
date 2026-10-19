# frozen_string_literal: true

require_relative "test_helper"
require_relative "../lib/operator/design_run"

class TestDesignRun < Minitest::Test
  RUN = Operator::DesignRun
  Surface = Struct.new(:id, :pixel_snapshot)
  Round = Struct.new(:outcome)

  def said(kept, surfaces)
    lines = []
    RUN.stub(:say, ->(text) { lines << text }) { RUN.baselines_note(kept, surfaces) }
    lines
  end

  # Baseline approval is the operator's, so a run that kept an edit names what to review first.
  def test_a_kept_edit_names_the_measured_surfaces_that_carry_an_approved_png
    surfaces = [Surface.new("amber/home/desktop", true), Surface.new("amber/feed/desktop", false)]
    lines = said([Round.new(:kept)], surfaces)

    assert_match(/differ on: amber\/home\/desktop\z/, lines.first)
    assert_match(/approve_visual_baselines\.rb --manifest/, lines.last)
  end

  def test_nothing_is_said_without_a_kept_edit_or_without_an_approved_png
    assert_empty said([], [Surface.new("amber/home/desktop", true)])
    assert_empty said([Round.new(:kept)], [Surface.new("amber/feed/desktop", false)])
  end
end
