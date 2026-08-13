# frozen_string_literal: true

module Shared
  class PasswordResetJob < ApplicationJob
    queue_as :critical
    run_inline!

    def perform(user_id)
      user = User.find_by(id: user_id)
      return unless user

      PasswordsMailer.reset(user).deliver_now
    end
  end
end
