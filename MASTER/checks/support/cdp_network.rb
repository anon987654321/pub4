# frozen_string_literal: true

module Deploy
  # Network response evidence from the same CDP event stream as console errors.
  # Request ids join the URL/resource type to loadingFailed; canceled navigations
  # are excluded because Chrome routinely aborts a request when a frame changes.
  module CdpNetwork
    def http_failures
      @events.filter_map do |event|
        next unless event["method"] == "Network.responseReceived"

        params = event["params"] || {}
        response = params["response"] || {}
        status = response["status"].to_i
        next if status < 400

        {
          status:,
          status_text: response["statusText"].to_s,
          url: response["url"].to_s,
          resource_type: params["type"].to_s,
          mime_type: response["mimeType"].to_s,
        }
      end.uniq { |row| [row[:status], row[:url], row[:resource_type]] }
    end

    def request_failures
      requests = {}
      @events.each do |event|
        next unless event["method"] == "Network.requestWillBeSent"

        params = event["params"] || {}
        request = params["request"] || {}
        requests[params["requestId"]] = {
          url: request["url"].to_s,
          resource_type: params["type"].to_s,
        }
      end

      @events.filter_map do |event|
        next unless event["method"] == "Network.loadingFailed"

        params = event["params"] || {}
        error = params["errorText"].to_s
        next if params["canceled"] || error == "net::ERR_ABORTED"

        request = requests[params["requestId"]] || {}

        {
          url: request[:url].to_s,
          resource_type: request[:resource_type].to_s,
          error:,
          blocked_reason: params["blockedReason"].to_s,
          canceled: false,
        }
      end.uniq { |row| [row[:url], row[:resource_type], row[:error], row[:blocked_reason]] }
    end
  end
end
