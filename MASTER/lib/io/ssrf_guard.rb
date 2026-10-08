# frozen_string_literal: true
require "ipaddr"
require "net/http"
require "resolv"
# Without this, safe_uri?'s `uri.is_a?(URI::HTTP)` raised NameError into its own
# blanket rescue and the guard answered false for every URL — web_fetch silently off.
require "uri"

module Master
  module Io
    # Blocks tool-driven HTTP fetches from reaching loopback, link-local
    # (including the 169.254.169.254 cloud metadata endpoint), private, and
    # other non-routable ranges. web_fetch/dynamic_http results flow back
    # into agent context as untrusted output, so a prompt-injection payload
    # that directs a fetch at the runtime's own internal network must not
    # succeed silently.
    #
    # The connection is pinned to the address this check approved. Net::HTTP
    # resolves a hostname again when it connects, so a DNS-rebinding domain
    # could answer public for the check and private for the socket; `http_for`
    # sets Net::HTTP#ipaddr to the checked address instead, while the hostname
    # still carries SNI, certificate verification and the Host header. Every
    # caller connects through `http_for`, never `Net::HTTP.start(uri.host, ...)`.
    module SsrfGuard
      RESERVED_RANGES = %w[
        0.0.0.0/8
        100.64.0.0/10
        192.0.0.0/24
        192.0.2.0/24
        198.18.0.0/15
        198.51.100.0/24
        203.0.113.0/24
        ::/128
        100::/64
        2001:db8::/32
      ].map { |cidr| IPAddr.new(cidr) }.freeze

      def self.safe_uri?(uri) = !pinned_address(uri).nil?

      # The address to connect to, or nil when the host is unsafe. Every answer
      # must be public: a name with one public and one private address is the
      # shape of a rebinding setup, not a choice.
      def self.pinned_address(uri)
        return unless uri.is_a?(URI::HTTP) && uri.host
        return if uri.host.strip.casecmp("localhost").zero?

        addresses = Resolv.getaddresses(uri.host)
        return if addresses.empty?
        return if addresses.any? { |addr| blocked_ip?(IPAddr.new(addr)) }

        addresses.first
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SsrfGuard.pinned_address")
        nil
      end

      # Bounded by default, so a caller that forgets a timeout still cannot hang
      # a turn on a host that accepts and never answers; callers may tighten it.
      DEFAULT_TIMEOUT_S = 15

      def self.http_for(uri, address, timeout: DEFAULT_TIMEOUT_S)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.ipaddr = address
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = timeout
          http.read_timeout = timeout
          http.write_timeout = timeout
        end
      end

      def self.blocked_ip?(ip)
        ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
        ip.loopback? || ip.link_local? || ip.private? ||
          (ip.respond_to?(:multicast?) && ip.multicast?) ||
          RESERVED_RANGES.any? { |range| range.include?(ip) }
      rescue StandardError
        true
      end
    end
  end
end
