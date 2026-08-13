# frozen_string_literal: true

# The local side of an ActivityPub actor.
#
# A user's identity is scoped to their city's domain, because that is already
# how brgen is partitioned: oshlo.no and brgen.no are separate origins with
# separate populations, which is the same shape as two Mastodon instances. So
# @kari@brgen.no and @kari@oshlo.no are different accounts, and federating the
# cities to each other falls out of federating at all.
module Federatable
  extend ActiveSupport::Concern

  KEY_BITS = 2048

  included do
    has_many :fedi_follows, dependent: :destroy
    has_many :fedi_followers, through: :fedi_follows, source: :fedi_actor
  end

  # city_id rather than city: this is called on users a controller loaded with
  # nothing preloaded, and ApplicationRecord is strict_loading by default —
  # reading the association here raised on every webfinger and actor fetch.
  def federated? = username.present? && !guest? && city_id.present?

  def actor_domain = strict_safe(:city)&.domain

  def actor_uri
    return nil unless federated?

    "https://#{actor_domain}/users/#{username}"
  end

  def key_id = actor_uri.present? ? "#{actor_uri}#main-key" : nil

  # Generated on first use rather than at signup. brgen mints a real User row
  # for every cookieless visitor, and RSA-2048 keygen for each of those would be
  # both slow and pointless — almost none of them ever federate anything.
  def signing_key
    ensure_keypair!
    OpenSSL::PKey::RSA.new(private_key)
  end

  def public_key_pem
    ensure_keypair!
    public_key
  end

  def ensure_keypair!
    return if private_key.present? && public_key.present?

    key = OpenSSL::PKey::RSA.new(KEY_BITS)
    # update_columns: this can run inside a request that is only reading, and a
    # keypair is not a change anyone wants a callback, a broadcast or an
    # activity emission about.
    update_columns(
      private_key: key.to_pem,
      public_key: key.public_key.to_pem,
      updated_at: Time.current
    )
  end

  def followers_inboxes
    fedi_follows.accepted.includes(:fedi_actor).map { |follow| follow.fedi_actor.delivery_inbox }.uniq
  end
end
