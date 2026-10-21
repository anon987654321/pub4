# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "openssl"
require "socket"
require "uri"

module Shared
  # Where an app is allowed to point an HTTP request, and how it reads the
  # answer. One rule for every app that fetches a URL someone else chose —
  # brgen's federation and link previews, and the post link embeds brgen and
  # amber share: an SSRF rule defined twice is one that will disagree with
  # itself, and the half that is wrong is the half nobody remembers to update.
  module OutboundHttp
    TIMEOUT = 10

    # Remote servers are untrusted input. A malicious or broken one can answer a
    # gigabyte, so the body is read in chunks and the read stops at the cap
    # rather than holding the whole answer in memory first.
    MAX_BODY = 1_000_000
    MAX_MEDIA_BODY = 8_000_000

    class BodyTooLarge < StandardError; end

    NETWORK_ERRORS = [
      Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Errno::ECONNRESET,
      Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, SocketError, URI::InvalidURIError,
      BodyTooLarge,
    ].freeze

    # HTTPS alone is not enough: a URL of https://127.0.0.1/ or a name that
    # resolves to RFC1918 is SSRF against our own box.
    UNSAFE_NETS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8
      169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24
      192.88.99.0/24 192.168.0.0/16 198.18.0.0/15 198.51.100.0/24
      203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 64:ff9b::/96 64:ff9b:1::/48 100::/64
      2001::/23 2001:db8::/32 2002::/16 2d00::/8 2e00::/7 3000::/5 3800::/6
      3c00::/7 3e00::/8 3f00::/8 fec0::/10 fc00::/7 fe80::/10 ff00::/8
    ].map { |cidr| IPAddr.new(cidr) }.freeze

    # IANA defines 2000::/3 as assignable global unicast, but reserves
    # unassigned subranges inside it. UNSAFE_NETS rejects those reservations
    # too; do not treat address space awaiting allocation as a public target.
    GLOBAL_IPV6 = IPAddr.new("2000::/3").freeze

    DNS_LABEL_MAX_BYTES = 63
    DNS_MAX_WIRE_BYTES = 255

    module_function

    # Bound DNS names before resolution: 63 octets per label and 255 octets
    # for the encoded name. IP literals are allowed through to the IP-range gate.
    def valid_resolver_host?(host)
      candidate = host.to_s
      candidate = candidate[1...-1] if candidate.start_with?("[") && candidate.end_with?("]")
      candidate = candidate.delete_suffix(".")
      return false if candidate.empty?

      begin
        IPAddr.new(candidate)
        return true
      rescue IPAddr::InvalidAddressError
        # Continue with DNS-name limits.
      end

      labels = candidate.split(".", -1)
      return false if labels.any? { |label| label.empty? || label.bytesize > DNS_LABEL_MAX_BYTES }

      labels.sum { |label| label.bytesize + 1 } + 1 <= DNS_MAX_WIRE_BYTES
    end

    # Use the operating-system resolver rather than the vulnerable Resolv parser.
    def resolve_addresses(host)
      return [] unless valid_resolver_host?(host)

      Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    rescue SocketError, SystemCallError
      []
    end

    def public_https?(uri)
      return false unless uri.is_a?(URI::HTTPS)
      return false unless uri.port.nil? || uri.port == 443
      return false unless valid_resolver_host?(uri.hostname)

      addrs = resolve_addresses(uri.hostname)
      return false if addrs.empty?

      addrs.none? { |addr| unsafe_ip?(addr) }
    end

    def unsafe_ip?(addr)
      ip = IPAddr.new(addr)
      ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
      return true if ip.ipv6? && !GLOBAL_IPV6.include?(ip)

      UNSAFE_NETS.any? { |net| net.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end

    # Resolve once, check that address, then connect to *that* address.
    #
    # public_https? above resolves the host to validate it, and every caller then
    # handed the hostname to Net::HTTP, which resolved it again at connect time.
    # Between those two lookups an attacker controlling the DNS answer can return
    # a public address for the check and 127.0.0.1 for the connection — classic
    # rebinding, and the reason a validate-then-connect pair is not a guard. The
    # window is not theoretical: every caller fetches a URL a stranger supplied.
    #
    # ipaddr= pins the socket destination while Net::HTTP keeps the original host
    # for the Host header and SNI, so certificate verification still checks the
    # name rather than the address.
    def request(uri, method: :get, headers: {}, body: nil, max_body: MAX_BODY)
      raise URI::InvalidURIError, "HTTPS required" unless uri.is_a?(URI::HTTPS)
      raise URI::InvalidURIError, "non-standard HTTPS port" unless uri.port.nil? || uri.port == 443

      address = resolve_addresses(uri.hostname).reject { |addr| unsafe_ip?(addr) }.first
      raise SocketError, "unsafe or unresolvable remote host" unless address

      http = pinned_connection(uri, address)
      klass = method.to_sym == :post ? Net::HTTP::Post : Net::HTTP::Get
      request = klass.new(uri.request_uri)
      headers.each { |key, value| request[key] = value }
      request.body = body if body
      http.request(request) { |response| response.body = capped_body(response, max_body) }
    end

    def pinned_connection(uri, address)
      # Passing nil disables Net::HTTP's implicit :ENV proxy lookup; a proxy
      # would otherwise route around the IP address this guard approved.
      http = Net::HTTP.new(uri.hostname, uri.port || 443, nil)
      # Refuse rather than fall back: without pinning this is the same
      # validate-then-reresolve pair the method exists to remove.
      raise SocketError, "Net::HTTP cannot pin remote address" unless http.respond_to?(:ipaddr=)

      http.ipaddr = address
      http.use_ssl = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http
    end

    def capped_body(response, limit)
      body = +""
      response.read_body do |chunk|
        raise BodyTooLarge, "response body exceeds #{limit} bytes" if body.bytesize + chunk.bytesize > limit

        body << chunk
      end
      body
    end
  end
end
