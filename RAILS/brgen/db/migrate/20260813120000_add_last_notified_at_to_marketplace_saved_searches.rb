# frozen_string_literal: true

# marketplace_saved_searches has carried a `notify` boolean since the table was
# created, the form permits it, and the index page renders an "alerts on" chip
# from it — while nothing ever ran a saved search on anyone's behalf. This is
# the column the alert job needs to know where it left off, so a subscriber is
# told about new listings once rather than every quarter of an hour.
class AddLastNotifiedAtToMarketplaceSavedSearches < ActiveRecord::Migration[8.1]
  def change
    add_column :marketplace_saved_searches, :last_notified_at, :datetime

    # The job's driving scope. Without it, every run scans the whole table to
    # find the handful of rows with alerts switched on.
    add_index :marketplace_saved_searches, %i[notify last_notified_at],
              name: "idx_marketplace_saved_searches_alerting"
  end
end
