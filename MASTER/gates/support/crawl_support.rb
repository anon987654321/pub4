# frozen_string_literal: true

require "net/http"
require "socket"
require "uri"
require_relative "utf8"

module CrawlSupport
  module_function

  # One HTTP client for live gates and the optional repository crawler. The
  # Host header distinguishes Brgen's vertical subdomains on a shared loopback
  # port; Accept can narrow a probe to an expected response type.
  def fetch(url, timeout: 15, open_timeout: 8, host: nil, accept: nil)
    uri = URI(url)
    Net::HTTP.start(uri.host, uri.port,
                    use_ssl: uri.scheme == "https",
                    open_timeout:,
                    read_timeout: timeout) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req["Host"] = host if host
      req["Accept"] = accept if accept
      http.request(req)
    end
  end

  def port_open?(host, port, timeout: 0.4)
    Socket.tcp(host, port, connect_timeout: timeout).close
    true
  rescue StandardError
    false
  end
end
