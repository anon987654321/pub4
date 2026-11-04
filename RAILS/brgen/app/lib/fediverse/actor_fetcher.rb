# frozen_string_literal: true

module Fediverse
  # Fetch and cache a remote actor document.
  module ActorFetcher
    module_function

    # Returns a FediActor or nil. Refreshes a stale record rather than trusting
    # a cached key forever, but keeps serving the old one if the refresh fails —
    # a remote outage must not stop us verifying signatures we can already
    # verify.
    def find_or_fetch(uri)
      return nil if uri.blank?

      existing = FediActor.find_by(uri: uri)
      return existing if existing && !existing.stale?

      document = Client.get_json(uri)
      return existing if document.blank?

      upsert(uri, document) || canonical(uri, document) || existing
    end

    # A profile URL can answer with the actor under its canonical id. Followed
    # once, on the same host, and stored under that id rather than the URL asked.
    def canonical(uri, document)
      id = document["id"].to_s
      return if id == uri || !same_host?(uri, id)

      fetched = Client.get_json(id)
      fetched.present? ? upsert(id, fetched) : nil
    end

    # keyId is usually "<actor-uri>#main-key". The fragment is stripped rather
    # than assumed, because some implementations use a separate key document.
    def for_key_id(key_id)
      find_or_fetch(key_id.to_s.split("#").first)
    end

    # A remote that rotated its key signs with one the cached copy does not
    # hold. One forced refetch, at most once a minute per actor, so a stream of
    # badly signed POSTs cannot make brgen fetch on each of them.
    REFETCH_INTERVAL = 1.minute

    def refetch(actor)
      return if actor.last_fetched_at&.after?(REFETCH_INTERVAL.ago)

      document = Client.get_json(actor.uri)
      document.present? ? upsert(actor.uri, document) : nil
    end

    # The document must be the actor that was asked for, and its key must say it
    # belongs to that actor: otherwise a host could serve another account's
    # document, or a key it does not own, under this URI.
    def upsert(uri, document)
      return unless document["id"] == uri

      inbox = document["inbox"]
      return if inbox.blank? || !same_host?(uri, inbox)

      actor = FediActor.find_or_initialize_by(uri:)
      actor.update!(document_attributes(uri, document))
      actor
    rescue URI::InvalidURIError, ActiveRecord::RecordInvalid
      nil
    end

    def document_attributes(uri, document)
      shared = document.dig("endpoints", "sharedInbox")

      {
        inbox_url: document["inbox"],
        shared_inbox_url: (shared if shared.present? && same_host?(uri, shared)),
        username: document["preferredUsername"],
        domain: URI(uri).host,
        display_name: document["name"],
        public_key_pem: owned_key_pem(uri, document["publicKey"]),
        followers_url: document["followers"],
        last_fetched_at: Time.current,
      }
    end

    def owned_key_pem(uri, key)
      key["publicKeyPem"] if key.is_a?(Hash) && key["owner"] == uri
    end

    def same_host?(left, right)
      URI(left).host.to_s.downcase == URI(right).host.to_s.downcase
    rescue URI::InvalidURIError
      false
    end
  end
end
