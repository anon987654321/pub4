# frozen_string_literal: true

class PasswordResetJob < ApplicationJob
  queue_as :critical

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    PasswordsMailer.reset(user).deliver_now
  end
end
