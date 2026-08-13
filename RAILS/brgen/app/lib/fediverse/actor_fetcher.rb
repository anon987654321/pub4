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

      upsert(uri, document) || existing
    end

    # keyId is usually "<actor-uri>#main-key". The fragment is stripped rather
    # than assumed, because some implementations use a separate key document.
    def for_key_id(key_id)
      find_or_fetch(key_id.to_s.split("#").first)
    end

    def upsert(uri, document)
      inbox = document["inbox"]
      return nil if inbox.blank?

      actor = FediActor.find_or_initialize_by(uri: uri)
      actor.inbox_url = inbox
      actor.shared_inbox_url = document.dig("endpoints", "sharedInbox")
      actor.username = document["preferredUsername"]
      actor.domain = URI(uri).host
      actor.display_name = document["name"]
      actor.public_key_pem = document.dig("publicKey", "publicKeyPem")
      actor.followers_url = document["followers"]
      actor.last_fetched_at = Time.current
      actor.save!
      actor
    rescue URI::InvalidURIError, ActiveRecord::RecordInvalid
      nil
    end
  end
end
