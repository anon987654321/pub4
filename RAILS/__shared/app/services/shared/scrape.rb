# frozen_string_literal: true

require "json"
require "ipaddr"
require "resolv"
require "socket"
require "uri"

begin
  require "ferrum"
rescue LoadError
  nil
end

module Shared
  class Scrape
    MODEL = ENV.fetch("SCRAPE_MODEL", Shared::Llm::DEFAULT_MODEL)
    HTML_MAX = 60_000
    BLOCKED_HOST_SUFFIXES = %w[.localhost .local .internal .home.arpa .onion].freeze
    BLOCKED_NETWORKS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16
      198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 ::ffff:0:0/96 64:ff9b:1::/48 100::/64 2001:db8::/32
      fc00::/7 fe80::/10 ff00::/8
    ].map { |range| IPAddr.new(range) }.freeze

    def self.call(url, schema:, hint: nil)
      raise ArgumentError, "scrape requires a public HTTP(S) URL" unless public_http_url?(url)
      raise LoadError, "gem install ferrum — required for Scrape.call" unless defined?(Ferrum::Browser)

      browser = Ferrum::Browser.new(headless: true, timeout: 30,
                                    browser_options: { "no-sandbox": nil })
      begin
        # A public page may redirect, load scripts, or embed images from another
        # origin. Check each browser request, not just the first URL, so a redirect
        # cannot turn a public seed URL into a request to localhost or cloud metadata.
        browser.network.intercept
        browser.on(:request) do |request|
          if safe_request_url?(request.url)
            request.continue
          else
            request.abort
          end
        end
        browser.go_to(url)
        browser.network.wait_for_idle(timeout: 10)
        html = browser.body
        png = browser.screenshot(encoding: :binary, full: true)
        reason(url:, html:, png:, schema:, hint:)
      ensure
        browser.quit
      end
    end

    # Only public HTTP(S) targets are scrape entrypoints. Resolve names here and
    # at every intercepted request; any private/reserved answer fails closed.
    # This application-level guard complements, but does not replace, host firewalling.
    def self.public_http_url?(value, resolver: ->(host) { Resolv.getaddresses(host) })
      uri = URI.parse(value.to_s)
      return false unless %w[http https].include?(uri.scheme&.downcase)
      return false if uri.userinfo || uri.hostname.to_s.empty?

      host = uri.hostname.downcase.delete_suffix(".")
      return false if host == "localhost" || BLOCKED_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }

      addresses = begin
        [IPAddr.new(host)]
      rescue IPAddr::InvalidAddressError
        Array(resolver.call(host)).map { |address| IPAddr.new(address) }
      end
      addresses.any? && addresses.all? { |address| public_address?(address) }
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError, Resolv::ResolvError, SocketError, ArgumentError
      false
    end

    def self.safe_request_url?(value, resolver: ->(host) { Resolv.getaddresses(host) })
      uri = URI.parse(value.to_s)
      return true if %w[data blob about].include?(uri.scheme&.downcase)

      public_http_url?(value, resolver:)
    rescue URI::InvalidURIError, ArgumentError
      false
    end

    def self.public_address?(address)
      BLOCKED_NETWORKS.none? do |network|
        network.ipv4? == address.ipv4? && network.include?(address)
      end
    rescue IPAddr::InvalidAddressError
      false
    end
    private_class_method :public_address?

    def self.reason(url:, html:, png:, schema:, hint:)
      prompt = <<~TXT
        Source: #{url}
        Extract every listed item on the page as JSON. Use the screenshot to read visual layout (cards, sponsored banners, hidden overlays); use the HTML for exact text and links.
        #{hint}
        Reply with one JSON object: {"items":[{#{schema.join(', ')}}, ...]}.
        HTML (truncated to #{HTML_MAX} bytes):
        #{html.byteslice(0, HTML_MAX)}
      TXT
      llm = Shared::Llm.new(model: MODEL)
      content = llm.ask(prompt, with: llm.attachment(png, filename: "page.png"))
      JSON.parse(content).fetch("items", [])
    end
  end
end
