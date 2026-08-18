# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "openssl"
require "resolv"
require "uri"

# Where this app is allowed to point an HTTP request, and how it reads the
# answer. Hoisted out of Fediverse::Client when link previews became a second
# caller: an SSRF rule defined twice is one that will disagree with itself, and
# the half that is wrong is the half nobody remembers to update.
module OutboundHttp
  TIMEOUT = 10

  # Remote servers are untrusted input. A malicious or broken one can answer a
  # gigabyte, so the body is capped rather than read whole into memory.
  MAX_BODY = 1_000_000

  NETWORK_ERRORS = [
    Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Errno::ECONNRESET,
    Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, SocketError, URI::InvalidURIError,
    Resolv::ResolvError
  ].freeze

  # HTTPS alone is not enough: a URL of https://127.0.0.1/ or a name that
  # resolves to RFC1918 is SSRF against our own box.
  UNSAFE_NETS = %w[
    0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16
    ::1/128 fc00::/7 fe80::/10
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  module_function

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
