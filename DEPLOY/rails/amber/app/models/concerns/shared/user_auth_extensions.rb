# frozen_string_literal: true

module Shared
  module UserAuthExtensions
    extend ActiveSupport::Concern

    REMEMBER_DURATION = 30.days

    included do
      has_many :device_logins, dependent: :destroy
      has_many :authentications, dependent: :destroy
    end

    def generate_remember_token!
      token = SecureRandom.urlsafe_base64(32)
      update!(
        remember_token: token,
        remember_token_expires_at: REMEMBER_DURATION.from_now
      )
      token
    end

    def remember_token_valid?
      remember_token.present? &&
        remember_token_expires_at.present? &&
        remember_token_expires_at > Time.current
    end

    def invalidate_remember_token!
      update!(remember_token: nil, remember_token_expires_at: nil)
    end

    def schedule_deletion!
      update!(deletion_scheduled_at: 30.days.from_now, deleted_at: Time.current)
    end

    def deletion_pending?
      deletion_scheduled_at.present? && deletion_scheduled_at > Time.current
    end
  end
end