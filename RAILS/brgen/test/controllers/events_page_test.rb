# frozen_string_literal: true

require "test_helper"

# What the event pages say about attendance: a full event's markup, the
# count after an RSVP, a list that stops before everyone, and the form's hints.
class EventsPageTest < ActionDispatch::IntegrationTest
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    ActsAsTenant.current_tenant = @city
    host! "brgen.no"
    @organiser = person("ep_org")
    @event = Event.create!(user: @organiser, title: "Bryggekonsert #{SecureRandom.hex(3)}",
                           starts_at: 5.days.from_now, venue_name: "Bryggen", capacity: 1)
  end

  teardown { ActsAsTenant.current_tenant = nil }

  def person(prefix)
    User.strict_loading(false).create!(
      email_address: "#{prefix}_#{SecureRandom.hex(3)}@brgen.no", password: "password123",
      username: "#{prefix}_#{SecureRandom.hex(3)}", guest: false
    )
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
  end

  def event_json_ld
    scripts = css_select("script[type='application/ld+json']").map { |node| JSON.parse(node.text) }
    scripts.flatten.find { |data| data["@type"] == "Event" }
  end

  test "a full event's JSON-LD says sold out and gives its capacity" do
    @event.rsvps.create!(user: person("ep_going"), status: "going")

    get event_path(@event)

    json_ld = event_json_ld
    assert_equal "https://schema.org/SoldOut", json_ld.dig("offers", "availability")
    assert_equal 1, json_ld["maximumAttendeeCapacity"]
    assert_equal 0, json_ld["remainingAttendeeCapacity"]
  end

  test "the past strip renders a finished event with its neighbourhood" do
    hood = Neighborhood.create!(city: @city, name: "Nordnes", slug: "nordnes-#{SecureRandom.hex(2)}")
    Event.create!(user: @organiser, title: "Ferdig #{SecureRandom.hex(3)}", starts_at: 3.days.ago,
                  venue_name: "Nordnes", neighborhood: hood)

    get events_path

    assert_response :success
  end

  test "an RSVP refreshes the count and names, and says the answer" do
    sign_in_as(person("ep_answer"))

    post rsvp_event_path(@event, status: "going"), as: :turbo_stream

    target = ActionView::RecordIdentifier.dom_id(@event, :attendees)
    assert_select "turbo-stream[action='replace'][target=?]", target
    assert_includes response.body, I18n.t("events.going_count", count: 1, locale: :nb)
    assert_select "p.visually-hidden[role='status']", text: I18n.t("events.your_answer.going", locale: :nb)
  end

  test "the attendee list says how many more are going than it names" do
    @event.update_columns(capacity: nil)
    @event.rsvps.create!(user: person("ep_named"), status: "going")
    @event.update_columns(going_count: 30)

    get event_path(@event)

    assert_includes response.body, "og 29 til"
  end

  test "the capacity and price hints are tied to their fields" do
    sign_in_as(@organiser)

    get new_event_path

    assert_select "input#event_capacity[aria-describedby='event_capacity_hint']"
    assert_select "small#event_capacity_hint.form-help"
    assert_select "input#event_price_cents[aria-describedby='event_price_hint']"
    assert_select "small#event_price_hint.form-help"
  end
end
