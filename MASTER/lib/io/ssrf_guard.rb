# frozen_string_literal: true
require "ipaddr"
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
    # Known residual risk: this resolves the hostname once up front, but
    # Net::HTTP resolves it again when it connects a few
    # milliseconds later — a DNS-rebinding attacker controlling the target
    # domain may serve a public IP for this check and a private one for
    # the real connection. Closing that fully means pinning the connection
    # to the resolved IP (custom socket + TLS SNI/hostname override), which
    # is a bigger change than this guard aims to be; this stops the common
    # case (a payload naming an internal URL directly), not a targeted
    # rebinding attack.
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

      def self.safe_uri?(uri)
        return false unless uri.is_a?(URI::HTTP) && uri.host
        return false if uri.host.strip.casecmp("localhost").zero?

        addresses = Resolv.getaddresses(uri.host)
        return false if addresses.empty?

        addresses.all? { |addr| !blocked_ip?(IPAddr.new(addr)) }
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "SsrfGuard.safe_uri?")
        false
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
