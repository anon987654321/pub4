# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../MASTER/gates/support/cdp_network"

class CdpNetworkDiagnosticsTest < Minitest::Test
  def client(events)
    Object.new.extend(Deploy::CdpNetwork).tap do |probe|
      probe.instance_variable_set(:@events, events)
    end
  end

  def test_http_failures_include_the_response_status_url_and_resource_kind
    probe = client([
      { "method" => "Network.responseReceived",
        "params" => { "requestId" => "a", "type" => "Script",
                      "response" => { "status" => 404, "statusText" => "Not Found",
                                      "url" => "http://127.0.0.1/assets/app.js",
                                      "mimeType" => "text/html" } } },
      { "method" => "Network.responseReceived",
        "params" => { "requestId" => "b", "type" => "Document",
                      "response" => { "status" => 200, "url" => "http://127.0.0.1/" } } }
    ])

    assert_equal [
      { status: 404, status_text: "Not Found", url: "http://127.0.0.1/assets/app.js",
        resource_type: "Script", mime_type: "text/html" }
    ], probe.http_failures
  end

  def test_request_failures_are_joined_to_their_url_and_canceled_loads_are_ignored
    probe = client([
      { "method" => "Network.requestWillBeSent",
        "params" => { "requestId" => "a", "type" => "Script",
                      "request" => { "url" => "http://127.0.0.1/assets/app.js" } } },
      { "method" => "Network.loadingFailed",
        "params" => { "requestId" => "a", "errorText" => "net::ERR_CONNECTION_RESET" } },
      { "method" => "Network.requestWillBeSent",
        "params" => { "requestId" => "b", "type" => "Image",
                      "request" => { "url" => "http://127.0.0.1/canceled.png" } } },
      { "method" => "Network.loadingFailed",
        "params" => { "requestId" => "b", "errorText" => "net::ERR_ABORTED", "canceled" => true } }
    ])

    assert_equal [
      { url: "http://127.0.0.1/assets/app.js", resource_type: "Script",
        error: "net::ERR_CONNECTION_RESET", blocked_reason: "", canceled: false }
    ], probe.request_failures
  end

  def test_duplicate_failures_are_collapsed_without_discarding_different_urls
    repeated = {
      "method" => "Network.responseReceived",
      "params" => { "type" => "Image",
                    "response" => { "status" => 404, "url" => "http://127.0.0.1/missing.png" } }
    }

    assert_equal 1, client([repeated, repeated]).http_failures.length
  end
end
