# frozen_string_literal: true

require "minitest/autorun"
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

  # The predicate tests above pass whether or not the request path consults it,
  # so they cannot tell a guard from a decoration. These drive the real method.
  def test_request_refuses_a_loopback_host
    error = assert_raises(SocketError) { OutboundHttp.request(URI("https://127.0.0.1/actor")) }
    assert_match(/unsafe or unresolvable/, error.message)
  end

  def test_ipv4_mapped_loopback_is_refused
    assert OutboundHttp.unsafe_ip?("::ffff:127.0.0.1")
    assert OutboundHttp.unsafe_ip?("::ffff:10.0.0.1")
    assert OutboundHttp.unsafe_ip?("::ffff:169.254.169.254")
  end

  def test_request_refuses_a_non_443_port
    assert_raises(URI::InvalidURIError) { OutboundHttp.request(URI("https://example.com:8443/actor")) }
  end

  def test_client_returns_nil_rather_than_raising_at_a_loopback_host
    assert_nil Fediverse::Client.request(:get, "https://127.0.0.1/actor")
  end

  # The point of the whole exercise: the address that was checked is the address
  # the socket connects to. Without ipaddr= the host would be resolved a second
  # time inside Net::HTTP and a rebinding answer would land on the private net.
  def test_the_checked_address_is_the_one_connected_to
    pinned = with_stubbed_dns("93.184.216.34") do
      OutboundHttp.request(URI("https://rebind.test/actor"))
    end

    assert_equal "93.184.216.34", pinned
  end

  def test_a_host_answering_one_public_and_one_private_address_pins_the_public_one
    pinned = with_stubbed_dns("127.0.0.1", "93.184.216.34") do
      OutboundHttp.request(URI("https://rebind.test/actor"))
    end

    assert_equal "93.184.216.34", pinned
  end

  private

  # Answers the lookup with fixed addresses and reports the ipaddr Net::HTTP was
  # left holding, instead of opening a socket.
  def with_stubbed_dns(*addresses)
    seen = nil
    Resolv.singleton_class.alias_method(:real_getaddresses, :getaddresses)
    Net::HTTP.alias_method(:real_request, :request)
    Resolv.define_singleton_method(:getaddresses) { |_host| addresses }
    Net::HTTP.define_method(:request) { |_req| seen = ipaddr }

    yield
    seen
  ensure
    Resolv.singleton_class.alias_method(:getaddresses, :real_getaddresses)
    Net::HTTP.alias_method(:request, :real_request)
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
  SOURCES = "{amber,brgen,bsdports,shared}/{app,lib,engines}/**/*.rb"

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
    assert_operator files.size, :>, 500, "the glob read #{files.size} files — the instrument is pointed at the wrong place"

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
    source = "# Net::HTTP.get takes no timeout, so this does not use it\n" \
             "Net::HTTP.start(host, 443, open_timeout: 5, read_timeout: 10) { |h| h.get(path) }\n"
    assert_empty self.class.findings(source, "planted.rb")
  end
end
