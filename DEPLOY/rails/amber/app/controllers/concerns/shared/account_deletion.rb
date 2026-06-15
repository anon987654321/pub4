# frozen_string_literal: true
# AN212: GDPR account deletion flow

module Shared
  module AccountDeletion
    extend ActiveSupport::Concern

    GRACE_PERIOD = 30.days

    private

    def schedule_account_deletion(user)
      user.update!(deleted_at: Time.current, deletion_scheduled_at: GRACE_PERIOD.from_now)
      Shared::AccountExportJob.perform_later(user.id)
      Shared::AccountHardDeleteJob.set(wait: GRACE_PERIOD).perform_later(user.id)
    end

    def cancel_account_deletion(user)
      user.update!(deleted_at: nil, deletion_scheduled_at: nil)
    end
  end
end