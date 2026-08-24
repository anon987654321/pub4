# frozen_string_literal: true

module Shared
  module UserAuthExtensions
    extend ActiveSupport::Concern

    REMEMBER_DURATION = 30.days
    MAGIC_LINK_DURATION = 15.minutes

    included do
      has_many :device_logins, dependent: :destroy if defined?(::DeviceLogin)
      if defined?(Shared::Authentication) && shared_auth_table_available?
        has_many :authentications, class_name: "Shared::Authentication", dependent: :destroy
      end
    end

    def generate_remember_token!
      ensure_auth_column!(:remember_token, :remember_token_expires_at)
      token = SecureRandom.urlsafe_base64(32)
      update!(
        remember_token: token,
        remember_token_expires_at: REMEMBER_DURATION.from_now,
      )
      token
    end

    def remember_token_valid?
      return false unless has_attribute?(:remember_token) && has_attribute?(:remember_token_expires_at)

      remember_token.present? &&
        remember_token_expires_at.present? &&
        remember_token_expires_at > Time.current
    end

    def invalidate_remember_token!
      ensure_auth_column!(:remember_token, :remember_token_expires_at)
      update!(remember_token: nil, remember_token_expires_at: nil)
    end

    def generate_magic_link_token!
      ensure_auth_column!(:magic_link_token, :magic_link_expires_at)
      token = SecureRandom.urlsafe_base64(32)
      update!(magic_link_token: token, magic_link_expires_at: MAGIC_LINK_DURATION.from_now)
      token
    end

    def magic_link_valid?
      return false unless has_attribute?(:magic_link_token) && has_attribute?(:magic_link_expires_at)

      magic_link_token.present? &&
        magic_link_expires_at.present? &&
        magic_link_expires_at > Time.current
    end

    def clear_magic_link!
      ensure_auth_column!(:magic_link_token, :magic_link_expires_at)
      update!(magic_link_token: nil, magic_link_expires_at: nil)
    end

    def schedule_deletion!
      ensure_auth_column!(:deletion_scheduled_at, :deleted_at)
      update!(deletion_scheduled_at: 30.days.from_now, deleted_at: Time.current)
    end

    def deletion_pending?
      return false unless has_attribute?(:deletion_scheduled_at)

      deletion_scheduled_at.present? && deletion_scheduled_at > Time.current
    end

    def two_factor_required?
      two_factor_enabled_for_auth? || marketplace_seller? || dating_profile_active?
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
      ensure_auth_column!(:otp_secret, :two_factor_enabled)
      secret = ROTP::Base32.random
      update!(otp_secret: secret, two_factor_enabled: true)
      secret
    end

    def disable_otp!
      ensure_auth_column!(:otp_secret, :two_factor_enabled)
      update!(otp_secret: nil, two_factor_enabled: false)
    end

    private

    def two_factor_enabled_for_auth?
      has_attribute?(:two_factor_enabled) && self[:two_factor_enabled]
    end

    def ensure_auth_column!(*columns)
      missing = columns.reject { |column| has_attribute?(column) }
      return if missing.empty?

      raise ActiveRecord::StatementInvalid, "missing shared auth user columns: #{missing.join(', ')}"
    end

    module ClassMethods
      def shared_auth_table_available?
        connection.data_source_exists?("authentications")
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
        false
      end
    end
  end
end
