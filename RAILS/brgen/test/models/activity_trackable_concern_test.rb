# frozen_string_literal: true

require "test_helper"

# Shared::ActivityTrackable resolved the `tracks_activity actor:` by calling
# public_send inside an after_commit. That is a lazy association read, and
# strict_loading_by_default is true in every environment (shared
# ApplicationRecord) with production raising rather than logging. So emitting an
# activity event for any record loaded from the database — every controller
# update action — raised *after* the write had already committed.
#
# record_activity! swallows its own failures ("activity skipped"), but the actor
# lookup happened outside that rescue, so it propagated and turned a successful
# save into a 500. 38 models pass `actor:`; every one with an `updated:` event
# was affected.
class ActivityTrackableTest < ActiveSupport::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @owner = User.strict_loading(false).create!(
      email_address: "at_owner@brgen.no", password: "password123", city: @city
    )
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  # actor: :user — a straightforward belongs_to.
  test "updating a freshly-found record resolves an association actor" do
    ActsAsTenant.with_tenant(@city) do
      created = Tv::Channel.create!(user: @owner, name: "Fjordkanalen", slug: "fjordkanalen-#{SecureRandom.hex(4)}")
      ActivityEvent.delete_all

      bare = Tv::Channel.find_by(id: created.id)
      refute bare.association(:user).loaded?, "guard: user must NOT be preloaded or this proves nothing"

      bare.update!(description: "Nyheter fra Vestland")

      assert_equal "Nyheter fra Vestland", created.reload.description
      event = ActivityEvent.where(subject_type: "Tv::Channel", subject_id: created.id).last
      assert_not_nil event, "an activity event should have been recorded"
      assert_equal @owner.id, event.actor_id, "the actor must resolve to the channel owner, not nil"
    end
  end

  # actor: :restaurant_owner — a plain method, not an association, and it walks
  # a second association of its own.
  test "updating a freshly-found record resolves a method actor" do
    ActsAsTenant.with_tenant(@city) do
      restaurant = Takeaway::Restaurant.create!(
        user: @owner, name: "Marken Mat", address: "Marken 8",
        cuisine_type: "Norwegian", city: @city, active: true
      )
      created = Takeaway::MenuItem.create!(restaurant: restaurant, name: "Fiskesuppe", price_cents: 18_900)
      ActivityEvent.delete_all

      bare = Takeaway::MenuItem.find_by(id: created.id)
      refute bare.association(:restaurant).loaded?, "guard: restaurant must NOT be preloaded"

      bare.update!(price_cents: 19_900)

      assert_equal 19_900, created.reload.price_cents
      event = ActivityEvent.where(subject_type: "Takeaway::MenuItem", subject_id: created.id).last
      assert_not_nil event
      assert_equal @owner.id, event.actor_id, "restaurant_owner must resolve through the restaurant"
    end
  end

  # The contract: analytics is never the reason a write fails. record_activity!
  # already honoured this; actor resolution now does too.
  test "a write still succeeds when actor resolution raises" do
    ActsAsTenant.with_tenant(@city) do
      created = Tv::Channel.create!(user: @owner, name: "Nattkanalen", slug: "nattkanalen-#{SecureRandom.hex(4)}")

      bare = Tv::Channel.find_by(id: created.id)
      bare.define_singleton_method(:strict_safe) { |_name| raise "actor lookup exploded" }

      bare.update!(description: "Sent på kvelden")

      assert_equal "Sent på kvelden", created.reload.description
    end
  end
end
