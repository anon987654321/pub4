# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../gates/lib/live/flow_journey"

# The journey gate is supposed to be measuring the app under test on
# 127.0.0.1. It was not, whenever a redirect answered with an absolute URL.
#
# brgen's /live answers `301 Location: http://brgen.no/nearby/room`. The client
# took that at face value, so the next hop went to the real brgen.no on port
# 80, where relayd answers with a TLS redirect that Net::HTTP reports as
# "EOFError: end of file reached". That error is how it was found; the quiet
# case is worse, because an absolute redirect that happens to succeed makes the
# gate report production as a local journey.
class FlowClientRedirectTest < Minitest::Test
  def setup
    @client = Deploy::FlowJourneyGate::FlowClient.new(port: 38_182)
  end

  def follow(location, current: "http://127.0.0.1:38182/live", host: "brgen.no")
    @client.send(:follow, location, current, host)
  end

  def test_an_absolute_redirect_stays_on_the_app_under_test
    url, host = follow("http://brgen.no/nearby/room")

    assert_equal "http://127.0.0.1:38182/nearby/room", url,
                 "an absolute Location must not send the next hop off the box"
    assert_equal "brgen.no", host, "the public name belongs in the Host header"
  end

  def test_an_absolute_redirect_to_another_vertical_carries_that_host
    url, host = follow("https://markedsplass.brgen.no/cart")

    assert_equal "http://127.0.0.1:38182/cart", url
    assert_equal "markedsplass.brgen.no", host,
                 "a redirect across subdomains is what the vanity Host header is for"
  end

  def test_a_relative_redirect_keeps_the_host_it_arrived_with
    url, host = follow("/nearby")

    assert_equal "http://127.0.0.1:38182/nearby", url
    assert_equal "brgen.no", host
  end

  def test_a_query_string_survives_the_hop
    url, = follow("/search?q=ski&page=2")

    assert_equal "http://127.0.0.1:38182/search?q=ski&page=2", url
  end

  # The old code special-cased the literal "127.0.0.1" when deciding whether to
  # overwrite the Host header. A local absolute redirect must not clobber the
  # vanity host with an IP, or every step after it is measured against the apex.
  def test_a_local_absolute_redirect_does_not_clobber_the_vanity_host
    url, host = follow("http://127.0.0.1:38182/nearby")

    assert_equal "http://127.0.0.1:38182/nearby", url
    assert_equal "brgen.no", host
  end
end
