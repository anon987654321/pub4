# frozen_string_literal: true

# GDPR Art. 17 erasure, on a delay. schedule_deletion! sets deleted_at now and
# deletion_scheduled_at +30 days (a grace window). This job runs after the
# window and erases the account's personal data.
#
# The users row is anonymised in place rather than destroyed, so that replies
# and threads keep their shape and no foreign key breaks. That decision has a
# consequence worth stating plainly, because it was not stated and the erasure
# was wrong for it: **no `dependent: :destroy` in the graph ever fires on this
# path**. Nothing is destroyed, so nothing cascades. Every table holding
# personal data has to be named here or it is simply kept.
#
# It was only the users row and its sessions. A purged account still had its
# dating profile — bio, coordinates, profile photographs and the
# identity-verification selfie — plus its delivery addresses, its postal
# addresses with recipient and phone, its federated email and phone number, its
# newsletter subscription, and the coordinates attached to every post and story
# it had written. Some of those are the most sensitive rows in the tree.
#
# Three dispositions, and which one a table gets is a legal question rather
# than a technical one:
#
#   destroy  — the row exists only to describe the person. A dating profile is
#              not shared content; removing it collapses no thread. Attachments
#              go with it, which is how the photographs and the selfie leave.
#   nullify  — the row must be retained but some columns are personal. A
#              takeaway order is a financial record the restaurant may be
#              required to keep (Art. 17(3)(b)); the address it was delivered
#              to is not part of that obligation.
#   keep     — nothing personal, or retention is required outright. Named in
#              the contract test with a reason, so the next person adding a
#              table has to make the same decision rather than inherit silence.
class UserPurgeJob < ApplicationJob
  queue_as :default

  # Rows that exist only to describe the person, with the association to reach
  # them by. Destroyed one at a time rather than delete_all'd: ActiveStorage
  # attachments are purged by the destroy callback, and a photograph left in
  # storage is the failure this whole job exists to prevent.
  DESTROY = [
    { model: "Dating::Profile",       key: :user_id },
    { model: "ExternalIdentity",      key: :user_id },
    { model: "Marketplace::Address",  key: :user_id },
    # What someone searched for, saved under their name. Nobody else reads it.
    { model: "Marketplace::SavedSearch", key: :user_id },
  ].freeze

  # Retained rows with personal columns to clear.
  #
  # delivery_address has a presence validation, so an order that has been
  # through here can no longer be saved by the ordinary path. That is the
  # honest trade and it is stated rather than dodged with a placeholder: an
  # order belonging to an erased account is not one anybody should be
  # transitioning, and a constant like "[slettet]" would be personal data's
  # shape without its content.
  NULLIFY = [
    { model: "Takeaway::Order", key: :user_id, columns: %i[delivery_address special_instructions] },
    { model: "Post",            key: :user_id, columns: %i[latitude longitude] },
    { model: "Story",           key: :user_id, columns: %i[latitude longitude] },
    # Where the goods are is usually where the seller lives. The listing itself
    # stays, because a sold item is half of somebody else's order.
    { model: "Marketplace::Listing",  key: :user_id, columns: %i[latitude longitude location] },
    # Points at a marketplace_addresses row this job destroys. Left set, it is
    # an id with nothing behind it.
    { model: "Marketplace::Checkout", key: :user_id, columns: %i[marketplace_address_id] },
    # An event has a venue rather than a home, but the coordinates on one
    # somebody hosted themselves are theirs.
    { model: "Event",                 key: :user_id, columns: %i[latitude longitude] },
  ].freeze

  def perform
    return unless User.column_names.include?("deletion_scheduled_at")

    User.where.not(deletion_scheduled_at: nil)
        .where("deletion_scheduled_at <= ?", Time.current)
        .find_each { |user| erase!(user) }
  end

  private

  def erase!(user)
    # Read before the overwrite. email_subscriptions is keyed by address rather
    # than by user_id, so the only handle on it is the address that the next
    # few lines are about to replace with purged-<id>@deleted.invalid.
    former_email = user.try(:email_address)

    DESTROY.each { |row| resolve(row[:model])&.where(row[:key] => user.id)&.find_each(&:destroy) }
    NULLIFY.each { |row| nullify(row, user) }
    erase_email_subscription(former_email)
    anonymise(user)
    user.sessions.delete_all if user.respond_to?(:sessions)
  end

  def anonymise(user)
    attrs = {
      deleted_at: Time.current,
      deletion_scheduled_at: nil,
      updated_at: Time.current
    }
    attrs[:email_address] = "purged-#{user.id}@deleted.invalid" if user.has_attribute?(:email_address)
    attrs[:username]      = "deleted_#{user.id}"                if user.has_attribute?(:username)
    attrs[:display_name]  = nil                                 if user.has_attribute?(:display_name)
    attrs[:password_digest] = BCrypt::Password.create(SecureRandom.hex(24)) if user.has_attribute?(:password_digest)
    %i[otp_secret magic_link_token remember_token latitude longitude location].each do |col|
      attrs[col] = nil if user.has_attribute?(col)
    end
    user.update_columns(attrs)
  end

  def nullify(row, user)
    model = resolve(row[:model]) or return
    columns = row[:columns].select { |c| model.column_names.include?(c.to_s) }
    return if columns.empty?

    model.where(row[:key] => user.id).update_all(columns.to_h { |c| [ c, nil ] })
  end

  def erase_email_subscription(email)
    return if email.blank?
    return unless defined?(::EmailSubscription)

    ::EmailSubscription.where(email: email).find_each(&:destroy)
  end

  # An engine may not be mounted, and a table may predate a migration on a box
  # mid-deploy. Erasure that raises leaves the account half-purged, which is
  # worse than the one that is skipped and retried on the next run.
  def resolve(name)
    model = name.safe_constantize
    model if model.respond_to?(:table_exists?) && model.table_exists?
  end
end
