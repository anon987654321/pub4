# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  attribute :city
  attribute :city_record
  attribute :country
  attribute :currency
  attribute :domain
  attribute :locale
  attribute :neighborhood
  attribute :session
  attribute :subapp
  attribute :user
  # Per-request memo of the viewer's reposts. The feed renders 25 cards and each
  # asks "did I repost this?" — as an exists? per card that is the N+1
  # QueryBudgetTest exists to catch. See Repost.reposted_post_ids_for.
  attribute :reposted_post_ids
  # Quote text is user-specific output inside the cached card (the dropdown
  # form prefills it). Same memo shape as the id set, so the feed does not
  # add a second query per card for it.
  attribute :repost_quote_comments
end
