# frozen_string_literal: true

require "securerandom"

module Shared
  # The one email-verification contract used by every host app. Existing and
  # programmatically provisioned users remain verified; public email signup opts
  # in to verification explicitly. Guest identities are never forced to sign up.
  module EmailVerification
    extend ActiveSupport::Concern

    included do
      attr_accessor :require_email_verification
      before_create :grant_email_verification, unless: :require_email_verification
    end

    def email_verified?
      return true unless has_attribute?(:email_verified_at)

      email_verified_at.present?
    end

    def generate_email_verification!
      return unless has_attribute?(:email_verification_token)

      token = SecureRandom.urlsafe_base64(32)
      update_columns(email_verification_token: token, updated_at: Time.current)
      token
    end

    def verify_email_token!(token)
      return false unless has_attribute?(:email_verification_token) && has_attribute?(:email_verified_at)
      return false if token.to_s.empty?

      changed = self.class.where(
        id: id,
        email_verification_token: token,
        email_verified_at: nil,
        deleted_at: nil,
        deletion_scheduled_at: nil
      ).update_all(email_verified_at: Time.current, email_verification_token: nil, updated_at: Time.current)
      changed == 1
    end

    def verify_email!
      verify_email_token!(email_verification_token)
    end

    private

    def grant_email_verification
      self.email_verified_at ||= Time.current if has_attribute?(:email_verified_at)
    end
  end
end
