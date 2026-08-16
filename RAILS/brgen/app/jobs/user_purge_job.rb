# frozen_string_literal: true

# GDPR Art. 17 erasure, on a delay. schedule_deletion! sets deleted_at now and
# deletion_scheduled_at +30 days (a grace window). This job runs after the window
# and erases the account's personal data: PII columns are overwritten, secrets and
# sessions are cleared. Content is anonymised to a "deleted" author rather than
# cascade-deleted, so replies and threads don't collapse and no foreign key breaks.
class UserPurgeJob < ApplicationJob
  queue_as :default

  def perform
    return unless User.column_names.include?("deletion_scheduled_at")

    User.where.not(deletion_scheduled_at: nil)
        .where("deletion_scheduled_at <= ?", Time.current)
        .find_each { |user| erase!(user) }
  end

  private

  def erase!(user)
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
    user.sessions.delete_all if user.respond_to?(:sessions)
  end
end
