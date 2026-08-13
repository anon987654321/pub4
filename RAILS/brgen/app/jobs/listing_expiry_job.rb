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

  def perform
    Marketplace::Listing.expiring_soon.includes(:user).find_each do |listing|
      listing.deliver_notification(
        listing.user,
        title: I18n.t("marketplace.expiry_notice.title", title: listing.title),
        body: I18n.t("marketplace.expiry_notice.body", days: listing.expires_in_days.to_i),
        source: listing,
        kind: "alert"
      )
      # Marked after sending, so a failure mid-run means a repeat rather than a
      # seller who is never told.
      listing.update_columns(renewal_notice_sent_at: Time.current, updated_at: Time.current)
    end
  end
end
