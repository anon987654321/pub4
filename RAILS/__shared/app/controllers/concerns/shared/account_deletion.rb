# frozen_string_literal: true

module Shared
  module AccountDeletion
    extend ActiveSupport::Concern

    private

    def schedule_account_deletion(user)
      user.schedule_deletion!
    end

    def cancel_account_deletion(user)
      user.update!(deletion_scheduled_at: nil, deleted_at: nil)
    end

    def complete_logout_for(_user)
      terminate_session
    end
  end
end
