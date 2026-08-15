# frozen_string_literal: true

require "ipaddr"
require "json"
require "net/http"
require "openssl"
require "resolv"
require "uri"

module Fediverse
  # Outgoing HTTP. Net::HTTP from stdlib rather than a gem, because this deploys
  # to OpenBSD and the dependency surface of federation is already large enough.
  module Client
    TIMEOUT = 10
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
      return nil unless public_https?(uri)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT

      klass = method == :post ? Net::HTTP::Post : Net::HTTP::Get
      req = klass.new(uri.request_uri)
      headers.each { |name, value| req[name] = value }
      req.body = body if body

      http.request(req)
    rescue *NETWORK_ERRORS => e
      Rails.logger.warn("fediverse: #{method} #{url} failed: #{e.class}") if defined?(Rails)
      nil
    end

    NETWORK_ERRORS = [
      Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Errno::ECONNRESET,
      Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, SocketError, URI::InvalidURIError,
      Resolv::ResolvError
    ].freeze

    # Inbox/key fetches run before signature verify. HTTPS alone is not enough:
    # a keyId of https://127.0.0.1/ or a name that resolves to RFC1918 is SSRF.
    UNSAFE_NETS = %w[
      0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16
      ::1/128 fc00::/7 fe80::/10
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    def public_https?(uri)
      return false unless uri.port.nil? || uri.port == 443

      addrs = Resolv.getaddresses(uri.host)
      return false if addrs.empty?

      addrs.none? { |addr| unsafe_ip?(addr) }
    end

    def unsafe_ip?(addr)
      ip = IPAddr.new(addr)
      UNSAFE_NETS.any? { |net| net.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end
  end
end
