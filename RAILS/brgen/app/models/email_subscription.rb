# frozen_string_literal: true

class EmailSubscription < ApplicationRecord
  MARKETING_CONSENT_VERSION = "newsletter-affiliate-disclosure-v1".freeze
  MARKETING_CONSENT_SOURCES = %w[signup_form preference_center].freeze

  before_create :generate_token

  # normalizes (not a bare before_validation) so finder args normalize too:
  # "Foo@X.com " and "foo@x.com" resolve to one row instead of inserting a
  # case/whitespace duplicate past the uniqueness check.
  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :confirmed, -> { where(confirmed: true) }
  scope :marketing_opted_in, -> { confirmed.where(agreed_to_marketing: true) }
  scope :delivery_eligible, -> {
    marketing_opted_in.where.not(
      email: User.where("deleted_at IS NOT NULL OR deletion_scheduled_at IS NOT NULL").select(:email_address),
    )
  }

  # Consent and mailbox confirmation are separate decisions. Public re-consent
  # rotates the token and requires a fresh inbox confirmation so a third party
  # cannot reactivate another person's opted-out address by typing the email.
  # Shared::Audit is append-only; its occurred_at, source and version retain the
  # consent trail across later opt-outs and re-consents without duplicating state.
  def record_marketing_consent!(source:, reconfirm: false)
    source = source.to_s
    raise ArgumentError, "unknown marketing consent source" unless MARKETING_CONSENT_SOURCES.include?(source)

    self.agreed_to_marketing = true
    if reconfirm
      self.confirmed = false
      self.confirmed_at = nil
      self.token = SecureRandom.urlsafe_base64(32)
    end

    saved = save
    audit_marketing_consent!("granted", source:) if saved
    saved
  end

  def confirm!
    update!(confirmed: true, confirmed_at: Time.current)
  end

  def update_marketing_preferences!(marketing:)
    if marketing
      return true if agreed_to_marketing?

      return record_marketing_consent!(source: "preference_center")
    end

    revoke_marketing_consent!(source: "preference_center")
  end

  # One-click comes from the mail client (RFC 8058), not the preference page;
  # the audit says which.
  def revoke_marketing_consent!(source:)
    return true unless agreed_to_marketing?

    update!(agreed_to_marketing: false)
    audit_marketing_consent!("revoked", source:)
    true
  end

  def marketing = agreed_to_marketing?

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(32)
  end

  def audit_marketing_consent!(decision, source:)
    return unless defined?(Shared::Audit)

    Shared::Audit.record!(
      action: "newsletter.marketing_consent.#{decision}",
      target: self,
      metadata: {
        decision:,
        source:,
        consent_version: MARKETING_CONSENT_VERSION
      }
    )
  end
end
