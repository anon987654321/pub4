# frozen_string_literal: true

require "test_helper"
require_relative "stimulus_node"

# track_controller's own source under node, against the stand-ins in
# track_stage.mjs.
class TrackControllerTest < ActiveSupport::TestCase
  include StimulusNode

  test "a finished order is not polled and a hidden tab waits until it is shown" do
    seen = run_stimulus("track", "track_stage.mjs", "track_finished_and_hidden.mjs")

    assert_equal 0, seen["finished"], "delivered and cancelled orders start no poll"
    assert_equal 0, seen["hidden"], "a hidden tab starts no poll"
    assert_equal 1, seen["shown"], "showing the tab starts it"
  end

  test "a new state refreshes the page in place from the status url it was given" do
    seen = run_stimulus("track", "track_stage.mjs", "track_state_change.mjs")

    assert_equal [ "/mat/track/abc/status" ], seen["fetched"]
    assert_equal [ [ "https://mrdamascy.test/track/abc", "replace" ] ], seen["visits"]
    assert_equal 0, seen["reloads"]
  end
end
