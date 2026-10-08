# frozen_string_literal: true

# A remote fediverse account.
#
# Cached rather than fetched per request, because verifying an HTTP signature
# needs the sender's public key on every inbox POST — and re-fetching the actor
# document each time would turn our inbox into a denial-of-service amplifier
# pointed at whoever is being impersonated.
class FediActor < ApplicationRecord
  has_many :fedi_follows, dependent: :destroy
  has_many :followed_users, through: :fedi_follows, source: :user

  validates :uri, presence: true, uniqueness: true
  validates :inbox_url, presence: true

  # How long a cached key is trusted. Keys rotate rarely, and a stale one fails
  # closed (the signature simply does not verify) rather than open.
  KEY_TTL = 1.day

  def handle = username.present? && domain.present? ? "@#{username}@#{domain}" : uri

  def stale? = last_fetched_at.nil? || last_fetched_at < KEY_TTL.ago

  def public_key
    return nil if public_key_pem.blank?

    OpenSSL::PKey::RSA.new(public_key_pem)
  rescue OpenSSL::PKey::RSAError
    nil
  end

  # The inbox to deliver to. A shared inbox is one POST for every follower on
  # that instance instead of one each; ignoring it is how a small server floods
  # a large one.
  def delivery_inbox = shared_inbox_url.presence || inbox_url
end
