# frozen_string_literal: true

# An instance this one refuses to talk to.
#
# A domain rather than an actor: the reason to block a whole instance is usually
# that moderating it actor by actor is the problem. Enforced on the way in (the
# inbox drops the activity before it becomes anything) and on the way out
# (delivery skips its inboxes), because a block that only works in one direction
# is a block that leaks in the other.
class FediBlock < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true

  validates :domain, presence: true, uniqueness: { case_sensitive: false },
                     format: { with: /\A[a-z0-9.-]+\z/i, message: "must be a hostname" }
  validates :reason, length: { maximum: 500 }

  before_validation { self.domain = domain.to_s.strip.downcase.delete_prefix("www.") }

  # Cached, because every inbox POST and every delivery asks. A blocklist that
  # costs a query per activity is one somebody eventually takes out of the hot
  # path and forgets to put back.
  CACHE_KEY = "fedi_blocks/domains"
  CACHE_TTL = 5.minutes

  after_commit { Rails.cache.delete(CACHE_KEY) }

  def self.domains
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { pluck(:domain).to_set }
  end

  def self.blocked?(host)
    host = host.to_s.strip.downcase.delete_prefix("www.")
    return false if host.blank?

    domains.include?(host) || domains.any? { |domain| host.end_with?(".#{domain}") }
  end

  def self.blocked_uri?(uri)
    blocked?(URI(uri.to_s).host)
  rescue URI::InvalidURIError
    false
  end
end
