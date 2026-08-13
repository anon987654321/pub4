# frozen_string_literal: true

# Runs everyone's saved searches and tells them what turned up.
#
# marketplace_saved_searches shipped with a `notify` boolean, the form permitted
# it, and the saved-searches page rendered an "alerts on" chip from it — while
# nothing in the tree ever ran a saved search on a user's behalf. The chip was
# the only thing the column did. This is the reader.
class SavedSearchAlertJob < ApplicationJob
  queue_as :bulk

  def perform
    now = Time.current
    alerted = 0

    Marketplace::SavedSearch.alerting.includes(:user, :category).find_each do |saved_search|
      next unless saved_search.due_for_alert?(now: now)

      listings = saved_search.new_matches.limit(Marketplace::SavedSearch::MAX_LISTINGS_PER_ALERT).to_a
      # No matches is not "nothing happened": last_notified_at stays put so the
      # next run still measures from the last thing the user was actually told
      # about, rather than silently swallowing listings posted in between.
      next if listings.empty?

      alerted += 1 if saved_search.deliver_alert!(listings, now: now)
    rescue StandardError => e
      # One malformed query must not stop everyone else's alerts. A saved search
      # can hold any string a user typed, and FTS is happy to raise on some.
      Ground::Swallow.log(e, context: "SavedSearchAlertJob##{saved_search.id}") if defined?(Ground::Swallow)
    end

    alerted
  end
end
