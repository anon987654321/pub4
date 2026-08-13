# frozen_string_literal: true

require "test_helper"

# marketplace_saved_searches shipped with a `notify` boolean, the form permitted
# it, and the saved-searches page rendered an "alerts on" chip from it — while
# nothing in the tree ever ran a saved search on anyone's behalf. Ticking the box
# changed a label. These pin the reader.
class SavedSearchAlertJobTest < ActiveJob::TestCase
  setup do
    Brgen::CitySeed.sync! if City.table_exists?
    @city = City.find_by!(domain: "brgen.no")
    @seller = User.strict_loading(false).create!(
      email_address: "ss_seller@brgen.no", password: "password123", city: @city
    )
    @watcher = User.strict_loading(false).create!(
      email_address: "ss_watcher@brgen.no", password: "password123", city: @city
    )
    ActsAsTenant.current_tenant = @city
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  def default_category
    @default_category ||= Marketplace::Category.create!(name: "Diverse-#{SecureRandom.hex(3)}")
  end

  def listing(title:, created_at: Time.current, description: "Pent brukt", category: nil)
    Marketplace::Listing.create!(
      user: @seller, title: title, description: description, category: category || default_category,
      price_cents: 50_000, status: "active", created_at: created_at
    )
  end

  def saved_search(query:, notify: true, **attrs)
    @watcher.marketplace_saved_searches.create!(query: query, notify: notify, **attrs)
  end

  test "a listing posted after the search was saved produces one notification" do
    search = saved_search(query: "sykkel")
    listing(title: "Terrengsykkel til salgs")

    assert_difference -> { @watcher.notifications.count }, 1 do
      SavedSearchAlertJob.perform_now
    end
    assert_not_nil search.reload.last_notified_at
  end

  # Switching alerts on must not mail you the entire back catalogue.
  test "listings that predate the saved search are not alerted" do
    listing(title: "Gammel sykkel", created_at: 3.days.ago)
    saved_search(query: "sykkel")

    assert_no_difference -> { @watcher.notifications.count } do
      SavedSearchAlertJob.perform_now
    end
  end

  test "a search with alerts off is never run" do
    saved_search(query: "sykkel", notify: false)
    listing(title: "Ny sykkel")

    assert_no_difference -> { @watcher.notifications.count } do
      SavedSearchAlertJob.perform_now
    end
  end

  # The schedule is every 30 minutes; the interval is what stops that becoming a
  # notification every 30 minutes.
  test "a second run inside the alert interval stays quiet" do
    saved_search(query: "sykkel")
    listing(title: "Sykkel en")

    assert_difference -> { @watcher.notifications.count }, 1 do
      SavedSearchAlertJob.perform_now
    end

    listing(title: "Sykkel to")
    assert_no_difference -> { @watcher.notifications.count } do
      SavedSearchAlertJob.perform_now
    end
  end

  test "the interval elapsing lets the next listing through" do
    search = saved_search(query: "sykkel")
    listing(title: "Sykkel en")
    SavedSearchAlertJob.perform_now

    search.update!(last_notified_at: (Marketplace::SavedSearch::ALERT_INTERVAL + 1.hour).ago)
    listing(title: "Sykkel to")

    assert_difference -> { @watcher.notifications.count }, 1 do
      SavedSearchAlertJob.perform_now
    end
  end

  test "a category-scoped search ignores matches from other categories" do
    bikes = Marketplace::Category.create!(name: "Sykler-#{SecureRandom.hex(3)}")
    boats = Marketplace::Category.create!(name: "Bater-#{SecureRandom.hex(3)}")
    saved_search(query: nil, category: bikes)

    listing(title: "Robat", category: boats)

    assert_no_difference -> { @watcher.notifications.count } do
      SavedSearchAlertJob.perform_now
    end

    listing(title: "Landeveissykkel", category: bikes)

    assert_difference -> { @watcher.notifications.count }, 1 do
      SavedSearchAlertJob.perform_now
    end
  end

  test "nothing matching leaves the watermark alone" do
    search = saved_search(query: "kajakk")
    listing(title: "Terrengsykkel til salgs", description: "Pent brukt")

    assert_no_difference -> { @watcher.notifications.count } do
      SavedSearchAlertJob.perform_now
    end
    # Otherwise a quiet run would move the cutoff forward over listings the user
    # was never told about.
    assert_nil search.reload.last_notified_at
  end

  # A saved search holds any string a user typed, and FTS will raise on some of
  # them. The job loads its own instances, so the only honest way to make one
  # blow up is to patch the method it calls and put it back afterwards.
  test "one broken saved search does not stop everyone else's alerts" do
    saved_search(query: "sykkel-broken")
    other_watcher = User.strict_loading(false).create!(
      email_address: "ss_other@brgen.no", password: "password123", city: @city
    )
    other_watcher.marketplace_saved_searches.create!(query: "sykkel", notify: true)
    listing(title: "Sykkel til alle")

    Marketplace::SavedSearch.class_eval do
      alias_method :new_matches_without_fault, :new_matches
      def new_matches(**kwargs)
        raise "FTS blew up" if query == "sykkel-broken"

        new_matches_without_fault(**kwargs)
      end
    end

    begin
      assert_difference -> { other_watcher.notifications.count }, 1 do
        SavedSearchAlertJob.perform_now
      end
    ensure
      Marketplace::SavedSearch.class_eval do
        remove_method :new_matches
        alias_method :new_matches, :new_matches_without_fault
        remove_method :new_matches_without_fault
      end
    end
  end
end
