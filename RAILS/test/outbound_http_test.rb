# frozen_string_literal: true

require "minitest/autorun"
require_relative "../__shared/app/services/shared/outbound_http"
require_relative "../brgen/app/lib/fediverse/client"

class FediverseSsrfTest < Minitest::Test
  def test_loopback_https_is_refused
    refute Fediverse::Client.public_https?(URI("https://127.0.0.1/actor"))
  end

  def test_link_local_metadata_is_refused
    refute Fediverse::Client.public_https?(URI("https://169.254.169.254/latest/meta-data"))
  end

  def test_non_443_is_refused
    refute Fediverse::Client.public_https?(URI("https://example.com:8443/actor"))
  end

  def test_plain_http_is_refused_by_the_predicate
    refute Shared::OutboundHttp.public_https?(URI("http://example.com/actor"))
  end

  def test_https_on_port_80_is_refused_by_the_predicate
    refute Shared::OutboundHttp.public_https?(URI("https://example.com:80/actor"))
  end

  # The predicate tests above pass whether or not the request path consults it,
  # so they cannot tell a guard from a decoration. These drive the real method.
  def test_request_refuses_a_loopback_host
    error = assert_raises(SocketError) { Shared::OutboundHttp.request(URI("https://127.0.0.1/actor")) }
    assert_match(/unsafe or unresolvable/, error.message)
  end

  def test_ipv4_mapped_loopback_is_refused
    assert Shared::OutboundHttp.unsafe_ip?("::ffff:127.0.0.1")
    assert Shared::OutboundHttp.unsafe_ip?("::ffff:10.0.0.1")
    assert Shared::OutboundHttp.unsafe_ip?("::ffff:169.254.169.254")
  end

  def test_ipv6_targets_must_be_global_unicast_and_not_documentation_space
    %w[4000::1 5f00::1 2d00::1 2e00::1 3000::1 3800::1 3c00::1 3e00::1 3f00::1 3ffe::1 3fff::1 2001:db8::1 fd00::1 fe80::1 ff02::1].each do |address|
      assert Shared::OutboundHttp.unsafe_ip?(address), "#{address} must not be an outbound target"
    end
    refute Shared::OutboundHttp.unsafe_ip?("2606:4700:4700::1111")
  end

  def test_special_ipv4_ranges_are_refused
    %w[0.1.2.3 100.64.0.1 169.254.1.1 192.168.1.1 198.18.0.1 203.0.113.1 224.0.0.1 240.0.0.1 255.255.255.255].each do |address|
      assert Shared::OutboundHttp.unsafe_ip?(address), "#{address} must not be an outbound target"
    end
    refute Shared::OutboundHttp.unsafe_ip?("93.184.216.34")
  end

  def test_dns_name_limits_reject_overlong_labels_and_wire_names
    assert Shared::OutboundHttp.valid_resolver_host?("example.com")
    assert Shared::OutboundHttp.valid_resolver_host?("127.0.0.1")
    refute Shared::OutboundHttp.valid_resolver_host?("#{"a" * 64}.example")
    refute Shared::OutboundHttp.valid_resolver_host?(Array.new(4, "a" * 63).join("."))
  end

  def test_pinned_connection_ignores_environment_proxy
    old_proxy = ENV["https_proxy"]
    ENV["https_proxy"] = "http://127.0.0.1:9"
    http = Shared::OutboundHttp.pinned_connection(URI("https://rebind.test/actor"), "93.184.216.34")

    assert_equal "93.184.216.34", http.ipaddr
    assert_nil http.proxy_address, "an environment proxy must not bypass the pinned destination"
  ensure
    old_proxy.nil? ? ENV.delete("https_proxy") : ENV["https_proxy"] = old_proxy
  end

  def test_request_refuses_a_non_443_port
    assert_raises(URI::InvalidURIError) { Shared::OutboundHttp.request(URI("https://example.com:8443/actor")) }
  end

  def test_request_refuses_reserved_ipv6_before_connecting
    %w[4000::1 3fff::1].each do |address|
      error = with_stubbed_dns(address) do
        assert_raises(SocketError) do
          Shared::OutboundHttp.request(URI("https://reserved-ipv6.test/actor"))
        end
      end
      assert_match(/unsafe or unresolvable/, error.message)
    end
  end

  def test_client_returns_nil_rather_than_raising_at_a_loopback_host
    assert_nil Fediverse::Client.request(:get, "https://127.0.0.1/actor")
  end

  # The point of the whole exercise: the address that was checked is the address
  # the socket connects to. Without ipaddr= the host would be resolved a second
  # time inside Net::HTTP and a rebinding answer would land on the private net.
  def test_the_checked_address_is_the_one_connected_to
    pinned = with_stubbed_dns("93.184.216.34") do
      with_stubbed_request(->(http, _request, _block) { http.ipaddr }) do
        Shared::OutboundHttp.request(URI("https://rebind.test/actor"))
      end
    end

    assert_equal "93.184.216.34", pinned
  end

  def test_a_host_answering_one_public_and_one_private_address_pins_the_public_one
    pinned = with_stubbed_dns("127.0.0.1", "93.184.216.34") do
      with_stubbed_request(->(http, _request, _block) { http.ipaddr }) do
        Shared::OutboundHttp.request(URI("https://rebind.test/actor"))
      end
    end

    assert_equal "93.184.216.34", pinned
  end

  # The cap is enforced while reading, so a hostile server cannot make this
  # process hold its whole answer before anything checks the size.
  def test_a_body_past_the_cap_stops_the_read
    response = ChunkedResponse.new(%w[aaaa bbbb cccc])

    with_stubbed_exchange(response) do
      assert_raises(Shared::OutboundHttp::BodyTooLarge) do
        Shared::OutboundHttp.request(URI("https://rebind.test/actor"), max_body: 6)
      end
    end
    assert_equal 2, response.chunks_read
  end

  def test_a_body_inside_the_cap_is_kept_whole
    response = ChunkedResponse.new(%w[aaaa bbbb])

    with_stubbed_exchange(response) do
      Shared::OutboundHttp.request(URI("https://rebind.test/actor"), max_body: 8)
    end
    assert_equal "aaaabbbb", response.body
  end

  def test_media_body_budget_is_bounded_and_larger_than_json
    assert_operator Shared::OutboundHttp::MAX_MEDIA_BODY, :>, Shared::OutboundHttp::MAX_BODY
    assert_operator Shared::OutboundHttp::MAX_MEDIA_BODY, :<=, 8_000_000
  end

  def test_an_oversized_body_is_a_network_error_callers_already_rescue
    assert_includes Shared::OutboundHttp::NETWORK_ERRORS, Shared::OutboundHttp::BodyTooLarge
  end

  private

  ChunkedResponse = Struct.new(:chunks, :body, :chunks_read) do
    def read_body
      self.chunks_read = 0
      chunks.each do |chunk|
        self.chunks_read += 1
        yield chunk
      end
    end
  end

  # Hands the request block a response that streams its chunks, instead of
  # opening a socket.
  def with_stubbed_exchange(response)
    with_stubbed_dns("93.184.216.34") do
      with_stubbed_request(->(_http, _request, block) { block.call(response) }) { yield }
    end
  end

  def with_stubbed_request(handler)
    Net::HTTP.alias_method(:saved_outbound_test_request, :request)
    Net::HTTP.define_method(:request) do |request, &block|
      handler.call(self, request, block)
    end
    yield
  ensure
    Net::HTTP.alias_method(:request, :saved_outbound_test_request)
    Net::HTTP.remove_method(:saved_outbound_test_request)
  end

  # Answers the lookup with fixed addresses and reports the ipaddr Net::HTTP was
  # left holding, instead of opening a socket.
  def with_stubbed_dns(*addresses)
    resolver = Shared::OutboundHttp.singleton_class
    resolver.alias_method(:saved_outbound_test_resolver, :resolve_addresses)
    Shared::OutboundHttp.define_singleton_method(:resolve_addresses) { |_host| addresses }
    yield
  ensure
    resolver.alias_method(:resolve_addresses, :saved_outbound_test_resolver)
    resolver.remove_method(:saved_outbound_test_resolver)
  end
end

# Every outbound HTTP call in app code carries a timeout.
#
# Net::HTTP's defaults are sixty seconds to open and sixty to read, and the
# convenience calls — Net::HTTP.get, get_response, post, post_form — accept no
# timeout at all. On a one-vCPU box a feed read that hangs inside a render holds
# a Falcon fiber and the page for two minutes. A call that opens a connection
# (start, new, URI.open) must name read_timeout in the same file; a convenience
# call is refused outright, because it cannot be given one.
class OutboundHttpTimeoutTest < Minitest::Test
  RAILS = File.expand_path("..", __dir__)
  SOURCES = "{__shared,amber,brgen,bsdports,brgen_marketplace,brgen_dating,brgen_radio,brgen_takeaway,brgen_messenger,brgen_maps}/{app,lib,engines}/**/*.rb"

  UNBOUNDABLE = /Net::HTTP\.(get|get_response|post|post_form)\s*\(/
  OPENS = /Net::HTTP\.(start|new)\s*\(|URI\.open\s*\(/

  def self.findings(source, label)
    code = source.lines.reject { |line| line.lstrip.start_with?("#") }.join
    found = code.scan(UNBOUNDABLE).map { |(call)| "#{label}: Net::HTTP.#{call} cannot take a timeout — use Net::HTTP.start with open_timeout/read_timeout" }
    found << "#{label}: opens a connection and never names read_timeout" if code.match?(OPENS) && !code.include?("read_timeout")
    found
  end

  def test_no_app_file_makes_an_unbounded_call
    files = Dir.glob(File.join(RAILS, SOURCES)).reject { |path| path.include?("/test/") }
    assert_operator files.size, :>, 0, "the outbound HTTP inventory matched no Ruby files"

    found = files.flat_map { |path| self.class.findings(File.read(path).scrub, path.delete_prefix("#{RAILS}/")) }
    assert_empty found, found.join("\n")
  end

  def test_a_convenience_call_is_named
    found = self.class.findings("res = Net::HTTP.get_response(uri)\n", "planted.rb")
    assert_equal 1, found.size
    assert_match(/Net::HTTP.get_response cannot take a timeout/, found.first)
  end

  def test_a_connection_without_read_timeout_is_named
    found = self.class.findings("Net::HTTP.start(host, 443, use_ssl: true) { |h| h.get(path) }\n", "planted.rb")
    assert_match(/never names read_timeout/, found.first.to_s)
  end

  def test_a_bounded_connection_and_a_comment_pass
    source = "# Net::HTTP.get takes no timeout, so this does not use it\n"              "Net::HTTP.start(host, 443, open_timeout: 5, read_timeout: 10) { |h| h.get(path) }\n"
    assert_empty self.class.findings(source, "planted.rb")
  end
end
