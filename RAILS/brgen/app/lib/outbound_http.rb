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
    ip = ip.native if ip.respond_to?(:ipv4_mapped?) && ip.ipv4_mapped?
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
  # window is not theoretical: both callers fetch a URL a stranger supplied.
  #
  # ipaddr= pins the socket destination while Net::HTTP keeps the original host
  # for the Host header and SNI, so certificate verification still checks the
  # name rather than the address.
  def request(uri, method: :get, headers: {}, body: nil)
    raise URI::InvalidURIError, "HTTPS required" unless uri.is_a?(URI::HTTPS)
    raise URI::InvalidURIError, "non-standard HTTPS port" unless uri.port.nil? || uri.port == 443

    address = Resolv.getaddresses(uri.host).reject { |addr| unsafe_ip?(addr) }.first
    raise SocketError, "unsafe or unresolvable remote host" unless address

    http = Net::HTTP.new(uri.host, uri.port || 443)
    # Refuse rather than fall back: without pinning this is the same
    # validate-then-reresolve pair the method exists to remove.
    raise SocketError, "Net::HTTP cannot pin remote address" unless http.respond_to?(:ipaddr=)

    http.ipaddr = address
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    klass = method.to_sym == :post ? Net::HTTP::Post : Net::HTTP::Get
    request = klass.new(uri.request_uri)
    headers.each { |key, value| request[key] = value }
    request.body = body if body
    http.request(request)
  end
end
