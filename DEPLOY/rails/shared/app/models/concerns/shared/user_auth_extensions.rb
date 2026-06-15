# frozen_string_literal: true

module Shared
  module UserAuthExtensions
    extend ActiveSupport::Concern

    REMEMBER_DURATION = 30.days
    MAGIC_LINK_DURATION = 15.minutes

    included do
      has_many :device_logins, dependent: :destroy
      has_many :authentications, class_name: "Shared::Authentication", dependent: :destroy
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

    def generate_magic_link_token!
      token = SecureRandom.urlsafe_base64(32)
      update!(magic_link_token: token, magic_link_expires_at: MAGIC_LINK_DURATION.from_now)
      token
    end

    def magic_link_valid?
      magic_link_token.present? &&
        magic_link_expires_at.present? &&
        magic_link_expires_at > Time.current
    end

    def clear_magic_link!
      update!(magic_link_token: nil, magic_link_expires_at: nil)
    end

    def schedule_deletion!
      update!(deletion_scheduled_at: 30.days.from_now, deleted_at: Time.current)
    end

    def deletion_pending?
      deletion_scheduled_at.present? && deletion_scheduled_at > Time.current
    end

    def two_factor_required?
      two_factor_enabled? || marketplace_seller? || dating_profile_active?
    end

    def marketplace_seller?
      respond_to?(:marketplace_listings) && marketplace_listings.active.exists?
    rescue StandardError
      false
    end

    def dating_profile_active?
      respond_to?(:dating_profile) && dating_profile&.active?
    rescue StandardError
      false
    end

    def enable_otp!
      secret = ROTP::Base32.random
      update!(otp_secret: secret, two_factor_enabled: true)
      secret
    end

    def disable_otp!
      update!(otp_secret: nil, two_factor_enabled: false)
    end
  end
end