# frozen_string_literal: true

require "minitest/autorun"
require "active_support/concern"
require_relative "../../app/models/concerns/shared/activity_trackable"
require_relative "../../app/services/shared/activity_event_recorder"

class ActivityTrackableTest < Minitest::Test
  def test_concern_api
    host = Class.new do
      include Shared::ActivityTrackable
    end
    assert_includes host.instance_methods, :record_activity!
    assert_includes host.singleton_methods, :tracks_activity
  end

  def test_recorder_noops_without_activity_event_model
    assert_nil Shared::ActivityEventRecorder.call(
      actor: nil, event_name: "Test", object: Object.new, source_vertical: "test",
    )
  end
end
