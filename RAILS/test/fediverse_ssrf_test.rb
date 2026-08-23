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
