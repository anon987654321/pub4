# frozen_string_literal: true

require "net/http"
require "uri"

module Master
  module Io
    # Renders a page in headless Chrome and returns visible text and links.
    # Chrome never receives an unrestricted HTTP request: each GET/HEAD is fetched
    # by Net::HTTP at SsrfGuard's pinned address, then fulfilled into the page.
    class WebBrowse
      TIER = :guarded
      NAME = "web_browse"
      DESCRIPTION = "Render a page in headless Chrome → title, visible text and links. For JavaScript sites web_fetch cannot read."
      TIMEOUT = 30
      REQUEST_TIMEOUT = 10
      SETTLE_SECONDS = 4
      MAX_TEXT = 16_000
      MAX_LINKS = 40
      MAX_REQUESTS = 120
      MAX_RESOURCE_BYTES = 4 * 1024 * 1024
      MAX_TOTAL_BYTES = 16 * 1024 * 1024
      REQUEST_METHODS = %w[GET HEAD].freeze
      REQUEST_HEADER_ALLOWLIST = %w[
        accept accept-language cookie origin referer user-agent
        sec-fetch-dest sec-fetch-mode sec-fetch-site sec-ch-ua
        sec-ch-ua-mobile sec-ch-ua-platform
      ].freeze
      HOP_BY_HOP_HEADERS = %w[
        connection keep-alive proxy-authenticate proxy-authorization
        te trailer transfer-encoding upgrade content-length
      ].freeze
      BROWSER_OPTIONS = {
        "disable-gpu" => nil,
        "disable-background-networking" => nil,
        "disable-quic" => nil,
        "host-resolver-rules" => "MAP * ~NOTFOUND"
      }.freeze
      ResourceLimit = Class.new(StandardError)

      # Fetch does not intercept every non-HTTP networking primitive (for example,
      # WebSockets). Disable those APIs before untrusted page scripts execute.
      NETWORK_SANDBOX_SCRIPT = <<~JS.freeze
        (() => {
          const deny = () => { throw new DOMException("Network sockets are disabled in read-only browsing", "SecurityError"); };
          for (const name of ["WebSocket", "WebTransport", "RTCPeerConnection", "webkitRTCPeerConnection"]) {
            try { Object.defineProperty(window, name, { value: deny, configurable: false, writable: false }); } catch (_) {}
          }
        })();
      JS

      SCRIPT = <<~JS
        (() => {
          const text = (document.body && document.body.innerText) || "";
          const links = Array.from(document.querySelectorAll("a[href]")).map(a => ({
            text: (a.innerText || a.getAttribute("aria-label") || "").trim().replace(/\s+/g, " ").slice(0, 120),
            href: a.href
          })).filter(l => l.text && /^https?:/.test(l.href));
          return JSON.stringify({ title: document.title, url: location.href, text, links });
        })()
      JS

      def initialize(governor:, event_bus: nil)
        @governor = governor
        @bus = event_bus
      end

      # wait: seconds to let the page's scripts settle before reading it.
      def call(url:, wait: SETTLE_SECONDS, links: true)
        uri = URI(url.to_s)
        return Result.err("web_browse: only http(s)", category: :validation) unless web_uri?(uri)
        return Result.err("web_browse: refused internal/reserved address", category: :validation) unless SsrfGuard.pinned_address(uri)

        perm = @governor.permit?(NAME, TIER, url)
        return perm if perm.err?

        snapshot = render(uri, wait.to_f.clamp(0.0, 12.0))
        deliver(url, snapshot, links:)
      rescue StandardError => e
        Result.err("web_browse: #{e.class}: #{e.message.lines.first.to_s.strip[0, 200]}", category: :infrastructure)
      end

      private

      def render(uri, wait)
        require "ferrum"
        require "json"
        browser = Ferrum::Browser.new(headless: true, timeout: TIMEOUT, process_timeout: TIMEOUT,
                                      browser_options: BROWSER_OPTIONS)
        page = browser.create_page
        page.command("Page.addScriptToEvaluateOnNewDocument", source: NETWORK_SANDBOX_SCRIPT)
        page.command("Network.setCacheDisabled", cacheDisabled: true)
        page.command("Network.setBypassServiceWorker", bypass: true)
        guard_requests(page, budget: new_budget)
        page.go_to(uri.to_s)
        sleep wait
        JSON.parse(page.evaluate(SCRIPT))
      ensure
        browser&.quit
      end

      def new_budget
        { requests: 0, bytes: 0, mutex: Mutex.new }
      end

      # Nothing is continued to Chromium's own network stack. A request is either
      # fetched directly to the address approved by SsrfGuard or aborted.
      def guard_requests(page, budget:)
        page.network.intercept
        page.on(:request) do |request|
          handle_request(request, budget:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "WebBrowse.request") rescue nil
          request.abort rescue nil
        end
      end

      def handle_request(request, budget:)
        return request.abort unless reserve_request!(budget)

        uri = URI(request.url.to_s)
        return request.abort unless web_uri?(uri)

        method = request.method.to_s.upcase
        return request.abort unless REQUEST_METHODS.include?(method)

        address = SsrfGuard.pinned_address(uri)
        return request.abort unless address

        response, body = pinned_get(uri, address, request, method, budget)
        if unsafe_redirect?(uri, response)
          return request.respond(
            responseCode: 403,
            responseHeaders: { "content-type" => "text/plain; charset=utf-8" },
            body: "Blocked unsafe redirect.",
          )
        end

        options = { responseCode: response.code.to_i, responseHeaders: response_headers(response) }
        options[:body] = body unless method == "HEAD"
        request.respond(**options)
      rescue ResourceLimit
        request.abort
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WebBrowse.pinned_get", url: request.url) rescue nil
        request.abort
      end

      def web_uri?(uri)
        %w[http https].include?(uri.scheme.to_s.downcase) && !uri.host.to_s.empty? && uri.userinfo.nil?
      end

      def reserve_request!(budget)
        budget[:mutex].synchronize do
          return false if budget[:requests] >= MAX_REQUESTS

          budget[:requests] += 1
          true
        end
      end

      def reserve_bytes!(budget, bytes)
        budget[:mutex].synchronize do
          raise ResourceLimit if budget[:bytes] + bytes > MAX_TOTAL_BYTES

          budget[:bytes] += bytes
        end
      end

      def pinned_get(uri, address, request, method, budget)
        headers = request_headers(request.headers)
        headers["Accept-Encoding"] = "identity"
        client = SsrfGuard.http_for(uri, address, timeout: REQUEST_TIMEOUT)
        outbound = method == "HEAD" ? Net::HTTP::Head.new(uri.request_uri, headers) : Net::HTTP::Get.new(uri.request_uri, headers)
        response = nil
        body = +"".b

        client.start do |connection|
          connection.request(outbound) do |incoming|
            response = incoming
            next if method == "HEAD"

            incoming.read_body do |chunk|
              raise ResourceLimit if body.bytesize + chunk.bytesize > MAX_RESOURCE_BYTES

              reserve_bytes!(budget, chunk.bytesize)
              body << chunk
            end
          end
        end
        [response, body]
      ensure
        client.finish if client&.started? rescue nil
      end

      def request_headers(headers)
        source = headers || {}
        REQUEST_HEADER_ALLOWLIST.each_with_object({}) do |name, result|
          pair = source.find { |key, _value| key.to_s.downcase == name }
          result[name] = pair.last.to_s if pair && !pair.last.to_s.empty?
        end
      end

      def response_headers(response)
        result = {}
        response.each_header do |name, value|
          key = name.to_s.downcase
          next if HOP_BY_HOP_HEADERS.include?(key) || key == "set-cookie"

          result[key] = value.to_s
        end
        cookies = response.get_fields("set-cookie")
        result["set-cookie"] = cookies.first if cookies && !cookies.empty?
        result
      end

      def unsafe_redirect?(uri, response)
        return false unless response.code.to_i.between?(300, 399)

        location = response["location"].to_s
        return false if location.empty?

        !web_uri?(URI.join(uri.to_s, location))
      rescue StandardError
        true
      end

      WALL = /captcha|verif(?:y|ication)|are you (?:a )?(?:human|robot)|access denied|unusual traffic|bot detection|blocked/i

      def deliver(url, snapshot, links:)
        text = snapshot["text"].to_s.delete("​‌‍﻿").gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
        body = +"#{snapshot["title"]}\n#{snapshot["url"]}\n\n#{text[0, MAX_TEXT]}"
        if text.length < 1500 && "#{snapshot["url"]} #{snapshot["title"]} #{text}".match?(WALL)
          body.prepend("NOTE: the site answered with a verification or bot wall instead of the page. " \
                       "Report that, and do not guess its contents.\n\n")
        end
        if links && snapshot["links"].is_a?(Array) && !snapshot["links"].empty?
          list = snapshot["links"].uniq { |link| link["href"] }.first(MAX_LINKS).map { |link| "- #{link["text"]} → #{link["href"]}" }
          body << "\n\nLinks:\n#{list.join("\n")}"
        end
        @bus&.publish("tool:after", tool: NAME, url:)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: url)
        Result.ok(guarded(body, url))
      end

      def guarded(text, url) = injection_guard.screen(text, tool: NAME, source: url, bus: @bus)

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end
    end
  end
end
