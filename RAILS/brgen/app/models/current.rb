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

  # The city this request is for, resolved from the domain by
  # Brgen::DomainRegistry (oshlo.no -> Oslo, lndon.uk -> London).
  #
  # Lives here rather than only in ApplicationHelper because copy that names a
  # city is not only rendered from views: Dating::Prompt#question_text
  # interpolates it from a model, where no helper is in scope, and had no way to
  # reach this — which is why its city prompt was the literal string "Bergen"
  # for every city domain.
  def self.city_name
    city.presence ||
      Brgen::DomainRegistry::ENTRIES_BY_DOMAIN[domain.to_s]&.city ||
      "Brgen"
  end
end
