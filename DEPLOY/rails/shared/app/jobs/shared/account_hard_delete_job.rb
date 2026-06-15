# frozen_string_literal: true

module Shared
  class AccountHardDeleteJob < ApplicationJob
    queue_as :bulk

    def perform(user_id)
      user = User.unscoped.find_by(id: user_id)
      return unless user&.deletion_scheduled_at&.past?

      user.destroy!
    end
  end
end