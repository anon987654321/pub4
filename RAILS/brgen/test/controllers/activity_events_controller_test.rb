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
    ActivityEvent.create!(
      actor: leaving, source_vertical: "marketplace", event_name: "ListingCreated",
      subject_type: "Post", subject_id: 1, visibility: "public", moderation_state: "clean"
    )
    leaving.update_columns(deleted_at: Time.current, deletion_scheduled_at: 7.days.from_now)

    get activity_events_path

    assert_response :success
    assert_select ".activity-event-list", count: 0
  end

  test "removed posts and private-community posts leave the public activity feed" do
    author = User.create!(email_address: "activity-#{SecureRandom.hex(4)}@brgen.no", password: "password123",
                          username: "activity_#{SecureRandom.hex(3)}", city: @city)
    club = Community.create!(slug: "klubb-#{SecureRandom.hex(3)}", name: "Klubb", user: author, city: @city,
                             privacy: "private")
    open_title = "Åpen #{SecureRandom.hex(3)}"
    removed_title = "Fjernet #{SecureRandom.hex(3)}"
    private_title = "Lukket #{SecureRandom.hex(3)}"
    Post.create!(user: author, city: @city, title: open_title, content: "hei")
    removed = Post.create!(user: author, city: @city, title: removed_title, content: "hei")
    removed.update_columns(removed_at: Time.current)
    Post.create!(user: author, city: @city, community: club, title: private_title, content: "hei")

    get activity_events_path

    assert_response :success
    assert_includes response.body, open_title
    refute_includes response.body, removed_title
    refute_includes response.body, private_title
  end
end
