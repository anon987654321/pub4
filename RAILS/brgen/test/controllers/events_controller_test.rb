# frozen_string_literal: true

require "test_helper"

class EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @organiser = User.strict_loading(false).create!(
      email_address: "ec_org@brgen.no", password: "password123", username: "ec_org", guest: false
    )
    @attendee = User.strict_loading(false).create!(
      email_address: "ec_att@brgen.no", password: "password123", username: "ec_att", guest: false
    )
    ActsAsTenant.current_tenant = @city
    @event = Event.create!(user: @organiser, title: "Bybanefest #{SecureRandom.hex(3)}", starts_at: 5.days.from_now)
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def sign_in_as(user)
    host! "brgen.no"
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  test "the listing and an event page render for a guest" do
    host! "brgen.no"

    get events_path
    assert_response :success
    assert_match @event.title, response.body

    get event_path(@event)
    assert_response :success
  end

  test "creating an event puts the organiser on their own guest list" do
    sign_in_as(@organiser)

    assert_difference -> { Event.count }, 1 do
      post events_path, params: { event: { title: "Nyttarsfest", starts_at: 10.days.from_now } }
    end
    created = Event.order(:id).last
    assert_redirected_to event_path(created)
    # Otherwise an event reads "0 going" the moment it is posted.
    assert_equal 1, created.going_count
  end

  test "rsvp sets a status, and pressing it again withdraws it" do
    sign_in_as(@attendee)

    assert_difference -> { EventRsvp.count }, 1 do
      post rsvp_event_path(@event, status: "going")
    end
    assert_equal 1, @event.reload.going_count

    assert_difference -> { EventRsvp.count }, -1 do
      post rsvp_event_path(@event, status: "going")
    end
    assert_equal 0, @event.reload.going_count
  end

  test "rsvp moves between statuses without leaving a second row" do
    sign_in_as(@attendee)

    post rsvp_event_path(@event, status: "going")
    assert_no_difference -> { EventRsvp.count } do
      post rsvp_event_path(@event, status: "interested")
    end

    assert_equal 0, @event.reload.going_count
    assert_equal 1, @event.interested_count
  end

  test "an unknown rsvp status is refused" do
    sign_in_as(@attendee)

    assert_no_difference -> { EventRsvp.count } do
      post rsvp_event_path(@event, status: "maybe-ish")
    end
    assert_response :unprocessable_entity
  end

  # A full event still takes "interested" — the waiting list is the point.
  test "a full event refuses going but still takes interested" do
    @event.update!(capacity: 1)
    EventRsvp.create!(event: @event, user: @organiser, status: "going")
    sign_in_as(@attendee)

    post rsvp_event_path(@event, status: "going")
    assert_equal 1, @event.reload.going_count, "capacity 1 must not admit a second"

    post rsvp_event_path(@event, status: "interested")
    assert_equal 1, @event.reload.interested_count
  end

  test "only the organiser can edit or cancel" do
    sign_in_as(@attendee)

    patch event_path(@event), params: { event: { title: "Kapret" } }
    assert_redirected_to event_path(@event)
    refute_equal "Kapret", @event.reload.title

    patch cancel_event_path(@event)
    refute @event.reload.cancelled?
  end

  test "the organiser cancels rather than deletes" do
    sign_in_as(@organiser)

    assert_no_difference -> { Event.count } do
      patch cancel_event_path(@event)
    end
    assert @event.reload.cancelled?
  end

  test "an event is reachable by slug" do
    sign_in_as(@organiser)
    assert @event.slug.present?, "guard: Sluggable should have made a slug"

    get event_path(@event.slug)
    assert_response :success
  end
end
