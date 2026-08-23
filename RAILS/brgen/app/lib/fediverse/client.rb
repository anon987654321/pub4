# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "resolv"
require "uri"

require_relative "../outbound_http"

module Fediverse
  # Outgoing HTTP. Net::HTTP from stdlib rather than a gem, because this deploys
  # to OpenBSD and the dependency surface of federation is already large enough.
  module Client
    ACCEPT = "application/activity+json, application/ld+json"

    # Remote servers are untrusted input. A malicious or broken one can answer a
    # gigabyte, so the body is capped rather than read whole into memory.
    MAX_BODY = 1_000_000

    module_function

    def get_json(url)
      response = request(:get, url, headers: { "Accept" => ACCEPT })
      return nil unless response&.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body.to_s[0, MAX_BODY])
    rescue JSON::ParserError
      nil
    end

    def post_signed(url:, body:, key:, key_id:)
      headers = Signature.sign(key: key, key_id: key_id, method: :post, url: url, body: body)
      request(:post, url, headers: headers, body: body)
    end

    def request(method, url, headers: {}, body: nil)
      uri = URI(url)
      # http:// is refused rather than followed: an unencrypted delivery leaks
      # who follows whom to anyone on the path, and a fediverse peer that only
      # speaks http is not one worth talking to.
      return nil unless uri.is_a?(URI::HTTPS)

      # No public_https? pre-check: it resolved the host and Net::HTTP resolved
      # it again below, so a peer controlling its own DNS could answer public
      # for the check and 127.0.0.1 for the connection. Inbox and key fetches
      # run before signature verification, so the host is attacker-chosen here.
      OutboundHttp.request(uri, method: method, headers: headers, body: body)
    rescue *NETWORK_ERRORS => e
      Rails.logger.warn("fediverse: #{method} #{url} failed: #{e.class}") if defined?(Rails)
      nil
    end

    NETWORK_ERRORS = OutboundHttp::NETWORK_ERRORS

    # Inbox/key fetches run before signature verify, so the SSRF rule bites here
    # first. It lives in OutboundHttp because link previews fetch remote URLs
    # too, and a network allowlist written twice ends up disagreeing with
    # itself.
    def public_https?(uri) = OutboundHttp.public_https?(uri)
    def unsafe_ip?(addr) = OutboundHttp.unsafe_ip?(addr)
  end
end
