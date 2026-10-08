# frozen_string_literal: true

# Title, site and summary for a link someone pasted. Deliberately no image.
#
# An image would mean either hotlinking the remote file — which tells that
# server the IP of every reader of the thread — or proxying and storing it,
# which is remote media hosting with the moderation and disk problems that
# come with it. TODO.md 2.1 defers the same problem for federation; a
# chat preview is not the place to take it on.
class LinkPreview < ApplicationRecord
  STATUSES = %w[pending ok failed].freeze
  # A preview goes stale: titles change, articles get taken down.
  MAX_AGE = 30.days

  has_many :messages, dependent: :nullify

  validates :url, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :usable, -> { where(status: "ok") }

  def ok? = status == "ok"
  def stale? = fetched_at.nil? || fetched_at < MAX_AGE.ago

  def host
    URI(url).host.to_s.delete_prefix("www.")
  rescue URI::InvalidURIError
    ""
  end

  # The first https URL in a body, or nil. http:// is skipped rather than
  # upgraded: fetching it would be an unencrypted request made on the reader's
  # behalf, and guessing at https for a server that did not offer it is a guess.
  URL_PATTERN = %r{https://[^\s<>"']+}

  def self.first_url_in(text)
    match = text.to_s[URL_PATTERN]
    return nil if match.blank?

    match.sub(/[.,;:)\]]+\z/, "")
  end
end
