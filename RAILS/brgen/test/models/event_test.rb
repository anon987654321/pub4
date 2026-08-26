# frozen_string_literal: true

require "test_helper"

class EventTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @organiser = User.strict_loading(false).create!(
      email_address: "ev_org@brgen.no", password: "password123", username: "ev_org", city: @city
    )
    @guest = User.strict_loading(false).create!(
      email_address: "ev_guest@brgen.no", password: "password123", username: "ev_guest", city: @city
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def event(title: "Konsert #{SecureRandom.hex(3)}", **attrs)
    Event.create!({ user: @organiser, title: title, starts_at: 3.days.from_now }.merge(attrs))
  end

  test "an event needs a title and a start" do
    refute Event.new(user: @organiser, starts_at: 1.day.from_now).valid?
    refute Event.new(user: @organiser, title: "Uten tid").valid?
  end

  test "an event cannot end before it starts" do
    bad = Event.new(user: @organiser, title: "Bakvendt", starts_at: 2.days.from_now, ends_at: 1.day.from_now)
    refute bad.valid?
    assert bad.errors.of_kind?(:ends_at, :before_start)
  end

  # A three-day festival is still upcoming on day two. Dropping an event from
  # the listing at its opening minute is how a what's-on page lies.
  test "upcoming keeps a running multi-day event and drops a finished one" do
    running = event(title: "Festival", starts_at: 1.day.ago, ends_at: 2.days.from_now)
    finished = event(title: "I gar", starts_at: 3.days.ago, ends_at: 2.days.ago)
    later = event(title: "Neste uke", starts_at: 7.days.from_now)

    ids = Event.upcoming.map(&:id)
    assert_includes ids, running.id, "a festival on day two is still on"
    assert_includes ids, later.id
    refute_includes ids, finished.id
    assert_includes Event.past.map(&:id), finished.id
  end

  test "upcoming is ordered by when things start" do
    late = event(title: "Sent", starts_at: 9.days.from_now)
    early = event(title: "Tidlig", starts_at: 2.days.from_now)

    assert_equal [ early.id, late.id ], Event.upcoming.map(&:id) & [ early.id, late.id ]
    assert_operator Event.upcoming.map(&:id).index(early.id), :<, Event.upcoming.map(&:id).index(late.id)
  end

  # Requiring a Place would mean nobody can post a party in their own flat;
  # requiring coordinates would mean nobody can post before the venue is fixed.
  test "a place fills in location, and a bare venue name is also allowed" do
    place = Place.create!(
      city: @city, name: "Landmark", kind: "venue", latitude: 60.3925, longitude: 5.3242
    )
    linked = event(title: "Pa Landmark", place: place)

    assert_equal "Landmark", linked.location_name
    assert_equal place.latitude, linked.latitude
    assert_equal place.longitude, linked.longitude

    freeform = event(title: "Hjemme", venue_name: "Hos Kari")
    assert_equal "Hos Kari", freeform.location_name
    assert_nil freeform.place_id
  end

  test "an rsvp moves the counts, including when it changes its mind" do
    party = event(title: "Fest")

    rsvp = EventRsvp.create!(event: party, user: @guest, status: "going")
    assert_equal 1, party.reload.going_count
    assert_equal 0, party.interested_count

    # A counter_cache per status would drift here: Rails increments on create
    # and decrements on destroy, and this is neither.
    rsvp.update!(status: "interested")
    assert_equal 0, party.reload.going_count
    assert_equal 1, party.interested_count

    rsvp.destroy
    assert_equal 0, party.reload.interested_count
  end

  test "the counter refresh also bumps updated_at so the cached card changes" do
    party = event(title: "Cache")
    before = party.updated_at

    travel 1.second do
      EventRsvp.create!(event: party, user: @guest, status: "going")
    end

    assert_operator party.reload.updated_at, :>, before,
                    "update_columns skips updated_at, and the card is cached on [event]"
  end

  test "one answer per person per event" do
    party = event(title: "Enkelt")
    EventRsvp.create!(event: party, user: @guest, status: "going")

    refute EventRsvp.new(event: party, user: @guest, status: "interested").valid?
  end

  # nil capacity means unlimited, and must not render as "0 places left".
  test "places_left is nil without a capacity and floors at zero with one" do
    assert_nil event(title: "Apent").places_left

    small = event(title: "Lite", capacity: 1)
    EventRsvp.create!(event: small, user: @guest, status: "going")
    assert_equal 0, small.reload.places_left
    assert small.full?

    EventRsvp.create!(event: small, user: @organiser, status: "going")
    assert_equal 0, small.reload.places_left, "places_left must not go negative"
  end

  test "cancelling tells everyone who said they were coming" do
    party = event(title: "Avlyses")
    EventRsvp.create!(event: party, user: @guest, status: "going")

    assert_difference -> { @guest.notifications.count }, 1 do
      party.cancel!
    end
    assert party.reload.cancelled?
    assert_not_nil party.cancelled_at
  end

  test "a cancelled event leaves the upcoming listing" do
    party = event(title: "Borte")
    party.cancel!

    refute_includes Event.upcoming.map(&:id), party.id
  end

  test "an event emits to the city activity strip" do
    assert_difference -> { ActivityEvent.where(event_name: "EventCreated").count }, 1 do
      event(title: "Til stripen")
    end
  end
end
