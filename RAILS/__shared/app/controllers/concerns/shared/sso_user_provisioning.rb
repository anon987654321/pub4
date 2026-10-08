# frozen_string_literal: true

module Shared
  # The host side of Shared::SsoConsume: turn an email handed over by MASTER
  # into a local user and open a session for them.
  #
  # All three apps carried a byte-identical copy of find_or_create_sso_user.
  # Only start_sso_session! ever differed, so that is the one method left
  # overridable.
  module SsoUserProvisioning
    extend ActiveSupport::Concern

    private

    def find_or_create_sso_user(email:, display_name:)
      normalized = email.to_s.downcase.strip
      user = User.find_by(email_address: normalized)
      return user if user

      User.create!(sso_user_attributes(normalized, display_name))
    rescue StandardError => e
      Rails.logger.warn("SSO create user failed: #{e.message}")
      nil
    end

    # display_name and name are both probed because the three apps do not agree
    # on which column their User has, and an SSO handover must not fail over a
    # cosmetic field.
    def sso_user_attributes(email, display_name)
      password = SecureRandom.hex(24)
      attrs = { email_address: email, password:, password_confirmation: password }
      return attrs if display_name.blank?

      %w[display_name name].each do |column|
        attrs[column.to_sym] = display_name if User.column_names.include?(column)
      end
      attrs
    end

    def start_sso_session!(user)
      start_new_session_for(user)
    end
  end
end
