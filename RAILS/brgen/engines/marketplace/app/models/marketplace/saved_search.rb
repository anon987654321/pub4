# frozen_string_literal: true

class Marketplace::SavedSearch < ApplicationRecord
  include Shared::Notifiable

  belongs_to :user
  belongs_to :category, class_name: "Marketplace::Category", optional: true

  validates :name, length: { maximum: 120 }, allow_blank: true
  validates :query, length: { maximum: 200 }, allow_blank: true

  # Rows with alerts switched on that the job has not looked at recently. The
  # `notify` column and its "alerts on" chip predate anything that could act on
  # them: saving a search was a bookmark, and ticking the box changed a label.
  scope :alerting, -> { where(notify: true) }

  # At most one alert per search per this window, however often the job runs.
  # A quarter-hourly job with a chatty seller would otherwise be a notification
  # every fifteen minutes.
  ALERT_INTERVAL = 6.hours

  # Cap per notification. A search for "sykkel" with no category matches half
  # the marketplace on a busy day, and "347 new listings" is not an alert, it is
  # a reason to turn alerts off.
  MAX_LISTINGS_PER_ALERT = 20

  def title
    name.presence || query.presence || category&.name || "Saved search"
  end

  def due_for_alert?(now: Time.current)
    notify? && (last_notified_at.nil? || last_notified_at <= now - ALERT_INTERVAL)
  end

  # Listings that appeared since this search last reported. Anchored to
  # created_at on a search that has never alerted, not to the beginning of time
  # — otherwise switching alerts on mails you the entire back catalogue.
  def new_matches(since: nil)
    cutoff = since || last_notified_at || created_at
    scope = Marketplace::Listing.active.where("marketplace_listings.created_at > ?", cutoff)
    scope = scope.where(category_id: category_id) if category_id.present?
    scope = scope.where(location: location) if location.present?
    # Same columns the listings page searches, so an alert cannot disagree with
    # what the "run search" link on this row would show.
    scope = Shared::LiveSearch.call(scope, query: query, columns: %w[title description location]) if query.present?
    scope.order(created_at: :desc)
  end

  def deliver_alert!(listings, now: Time.current)
    return false if listings.empty?

    deliver_notification(
      user,
      title: I18n.t("marketplace.saved_search_alert.title", search: title, count: listings.size),
      body: listings.first(3).map(&:title).join(" · "),
      source: self
    )
    update!(last_notified_at: now)
    true
  end
end
