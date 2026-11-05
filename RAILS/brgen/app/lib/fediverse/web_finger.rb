# frozen_string_literal: true

module Fediverse
  # Turns a handle people actually know, @kari@mastodon.example, into the actor
  # URI ActivityPub needs (RFC 7033). Following used to accept only the actor
  # URL, which nobody has to hand; the handle is what a profile shows.
  module WebFinger
    HANDLE = /\A@?(?<user>[^@\s\/]+)@(?<host>[a-z0-9.-]+\.[a-z]{2,}(?::\d+)?)\z/i
    LD_ACTOR = 'application/ld+json; profile="https://www.w3.org/ns/activitystreams"'
    ACTOR_TYPES = [ "application/activity+json", LD_ACTOR ].freeze

    module_function

    def handle?(text) = HANDLE.match?(text.to_s.strip)

    # https://host/ for a handle, nil for anything else.
    def host_uri(text)
      match = HANDLE.match(text.to_s.strip)
      match && "https://#{match[:host]}/"
    end

    # The actor URI for a handle, or nil. Anything that is not a handle comes
    # back unchanged, so a pasted actor URL still works as before.
    def resolve(text)
      text = text.to_s.strip
      match = HANDLE.match(text)
      return text unless match

      user, host = match.values_at(:user, :host)
      query = URI.encode_www_form(resource: "acct:#{user}@#{host}")
      document = Client.get_json("https://#{host}/.well-known/webfinger?#{query}")
      self_link(document)
    end

    # The rel=self link of an ActivityPub type. Mastodon also lists a profile
    # page; that one is HTML and is no actor.
    def self_link(document)
      links = document.is_a?(Hash) ? Array(document["links"]) : []
      link = links.find { |entry| entry.is_a?(Hash) && entry["rel"] == "self" && ACTOR_TYPES.include?(entry["type"]) }
      href = link&.dig("href").to_s
      href.start_with?("https://") ? href : nil
    end
  end
end
