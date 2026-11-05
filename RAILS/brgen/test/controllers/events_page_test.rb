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
    assert_select "input#event_price_kroner[inputmode='decimal'][aria-describedby='event_price_hint']"
    assert_select "small#event_price_hint.form-help"
  end

  test "the event shows its newest comments oldest first, with older ones behind the pager" do
    talker = person("ep_talk")
    rows = (1..22).map do |n|
      { user_id: talker.id, commentable_type: "Event", commentable_id: @event.id, content: "Kommentar-#{n}-slutt",
        created_at: n.minutes.ago, updated_at: n.minutes.ago }
    end
    Comment.insert_all!(rows)

    get event_path(@event)

    assert_equal 20, css_select("#comments article.comment").size
    body = response.body
    assert_operator body.index("Kommentar-2-slutt"), :<, body.index("Kommentar-1-slutt"), "the newest comes last"
    refute_includes body, "Kommentar-22-slutt"
    assert_select "nav.pager a[rel=next][href*=?]", "comments_page=2"
  end

  test "the event page links an .ics file that carries the time, place and status" do
    @event.update!(ends_at: @event.starts_at + 2.hours, address: "Bryggen 1, Bergen", description: "Ta med; stol")

    get event_path(@event)
    assert_select "a[href=?][download]", event_path(@event, format: :ics),
                  text: I18n.t("events.add_to_calendar", locale: :nb)

    get event_path(@event, format: :ics)
    assert_response :success
    assert_equal "text/calendar", response.media_type
    body = response.body
    assert_includes body, "DTSTART:#{@event.starts_at.utc.strftime('%Y%m%dT%H%M%SZ')}\r\n"
    assert_includes body, "DTEND:#{@event.ends_at.utc.strftime('%Y%m%dT%H%M%SZ')}\r\n"
    assert_includes body, "LOCATION:Bryggen\\, Bryggen 1\\, Bergen\r\n"
    assert_includes body, "DESCRIPTION:Ta med\\; stol\r\n"
    assert_includes body, "STATUS:CONFIRMED\r\n"

    @event.cancel!
    get event_path(@event, format: :ics)
    assert_includes response.body, "STATUS:CANCELLED\r\n"
  end

  test "the form sets a neighbourhood and the index filters by one" do
    nordnes = Neighborhood.create!(city: @city, name: "Nordnes", slug: "nordnes-#{SecureRandom.hex(2)}")
    sandviken = Neighborhood.create!(city: @city, name: "Sandviken", slug: "sandviken-#{SecureRandom.hex(2)}")
    sign_in_as(@organiser)

    get new_event_path
    assert_select "select#event_neighborhood_id[aria-describedby='event_neighborhood_hint'] option[value=?]",
                  nordnes.id.to_s

    post events_path, params: { event: { title: "Nabofest", starts_at: 3.days.from_now, venue_name: "Hagen",
                                         neighborhood_id: nordnes.id } }
    assert_equal nordnes.id, Event.find_by!(title: "Nabofest").neighborhood_id
    Event.create!(user: @organiser, title: "Sandvikfest", starts_at: 4.days.from_now, venue_name: "Kaien",
                  neighborhood: sandviken)

    get events_path(neighborhood_id: nordnes.id)
    assert_select "form.neighborhood-filter select#events-neighborhood option[selected][value=?]", nordnes.id.to_s
    assert_includes response.body, "Nabofest"
    refute_includes response.body, "Sandvikfest"
  end
end
