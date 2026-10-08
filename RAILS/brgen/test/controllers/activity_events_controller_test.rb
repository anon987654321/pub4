# frozen_string_literal: true

require "test_helper"

class ActivityEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
  end

  teardown { ActsAsTenant.current_tenant = nil }

  test "departing actors are omitted from the public activity feed" do
    leaving = User.create!(
      email_address: "activity-leaving-#{SecureRandom.hex(4)}@brgen.no",
      password: "password123", username: "activity_leaving_#{SecureRandom.hex(3)}",
      city: @city
    )
    visible_event = ActivityEvent.create!(
      actor: leaving, source_vertical: "marketplace", event_name: "ListingCreated",
      subject_type: "Post", subject_id: 1, visibility: "public", moderation_state: "clean"
    )
    leaving.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get activity_events_path

    assert_response :success
    refute_includes response.body, visible_event.id.to_s
  end
end
