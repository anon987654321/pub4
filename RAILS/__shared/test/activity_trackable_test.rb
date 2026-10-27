# frozen_string_literal: true

require "minitest/autorun"
require "active_support/concern"
require_relative "../app/models/concerns/shared/activity_trackable"
require_relative "../app/services/shared/activity_event_recorder"

class ActivityTrackableTest < Minitest::Test
  def test_concern_api
    host = Class.new do
      include Shared::ActivityTrackable
    end
    assert_includes host.instance_methods, :record_activity!
    assert_includes host.singleton_methods, :tracks_activity
  end

  # The case is an app with no ActivityEvent model. Inside brgen's suite, which runs this file too,
  # the app is loaded and the model exists; there brgen's activity_trackable_concern_test covers recording.
  def test_recorder_noops_without_activity_event_model
    skip "an app with ActivityEvent is loaded; its own concern test covers recording" if defined?(::ActivityEvent)

    assert_nil Shared::ActivityEventRecorder.call(
      actor: nil, event_name: "Test", subject: Object.new, source_vertical: "test",
    )
  end
end
