# frozen_string_literal: true

# Tells sellers a week before their listing lapses, so renewing is a choice
# rather than a surprise.
#
# Nothing here deletes or hides anything: `live` already excludes an expired
# listing from every public surface, so the listing lapsing is a scope, not a
# state change. That keeps a seller's own expired listings visible to them,
# which is what makes renewal possible at all.
class ListingExpiryJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: "listing-expiry", duration: 1.hour, on_conflict: :discard

  def perform
    Marketplace::Listing.expiring_soon.includes(:user).find_each do |listing|
      next unless claim(listing)

      notify(listing)
    end
  end

  private

  # The stamp is written only where it is still empty, in one statement, so two
  # workers holding the same listing cannot both pass the check: the second
  # update matches no row.
  def claim(listing)
    now = Time.current
    Marketplace::Listing.where(id: listing.id, renewal_notice_sent_at: nil)
      .update_all(renewal_notice_sent_at: now, updated_at: now) == 1
  end

  # A notice that fails gives its claim back, so the next run tries again rather
  # than the seller never being told.
  def notify(listing)
    listing.deliver_notification(
      listing.user,
      title: I18n.t("marketplace.expiry_notice.title", title: listing.title),
      body: I18n.t("marketplace.expiry_notice.body", days: listing.expires_in_days.to_i),
      source: listing,
      kind: "alert"
    )
  rescue StandardError
    Marketplace::Listing.where(id: listing.id).update_all(renewal_notice_sent_at: nil)
    raise
  end
end
