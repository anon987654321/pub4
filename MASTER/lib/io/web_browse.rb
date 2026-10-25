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
        "host-resolver-rules" => "MAP * ~NOTFOUND",
      }.freeze
      ResourceLimit = Class.new(StandardError)
      UnsupportedContentEncoding = Class.new(StandardError)

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
          const candidates = ["main", "[role='main']", "article", ".content", "#content", ".post", ".article"];
          let textRoot = null;
          for (const selector of candidates) {
            const node = document.querySelector(selector);
            if (node && (node.innerText || "").trim().length > 200) {
              textRoot = node;
              break;
            }
          }
          textRoot ||= document.body;
          const text = (textRoot && textRoot.innerText) || "";
          const headings = Array.from(document.querySelectorAll("h1, h2, h3, h4, h5, h6"))
            .slice(0, 40)
            .map(node => ({
              level: node.tagName,
              text: (node.innerText || "").trim().replace(/\s+/g, " ").slice(0, 120)
            }))
            .filter(item => item.text.length > 0);
          const links = Array.from(document.querySelectorAll("a[href]")).map(a => ({
            text: (a.innerText || a.getAttribute("aria-label") || "").trim().replace(/\s+/g, " ").slice(0, 120),
            href: a.href
          })).filter(link => link.text && /^https?:/.test(link.href));
          const forms = Array.from(document.querySelectorAll("form")).slice(0, 20).map(form => ({
            action: form.action,
            method: (form.method || "get").toUpperCase(),
            inputs: Array.from(form.querySelectorAll("input, textarea, select")).slice(0, 20).map(input => ({
              name: input.name || "",
              type: input.type || input.tagName.toLowerCase(),
              placeholder: input.placeholder || ""
            }))
          }));
          const counts = {
            images: document.querySelectorAll("img").length,
            links: document.querySelectorAll("a[href]").length,
            interactive: document.querySelectorAll("button, input, select, textarea").length,
            sections: document.querySelectorAll("article, section, .content, .post").length
          };
          return JSON.stringify({
            title: document.title,
            url: location.href,
            text,
            text_source: textRoot ? textRoot.tagName.toLowerCase() : "none",
            headings,
            links,
            forms,
            counts
          });
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

      # Public, shared security setup: Browser uses the same fenced
      # request path rather than letting a second Ferrum instance access the net.
      def secure_page(page, allowed_host: nil)
        page.command("Page.addScriptToEvaluateOnNewDocument", source: NETWORK_SANDBOX_SCRIPT)
        page.command("Network.setCacheDisabled", cacheDisabled: true)
        page.command("Network.setBypassServiceWorker", bypass: true)
        budget = new_budget
        page.instance_variable_set(:@master_web_browse_budget, budget)
        guard_requests(page, budget:, allowed_host:)
        page
      end

      # Reuse the same request handler while giving each explicit page
      # navigation its own bounded resource budget. The callback closes over
      # the mutable budget object, so resetting its counters does not weaken
      # the host or SSRF checks.
      def reset_page_budget(page)
        budget = page.instance_variable_get(:@master_web_browse_budget)
        return false unless budget

        budget[:mutex].synchronize do
          budget[:requests] = 0
          budget[:bytes] = 0
        end
        true
      end

      def deliver_snapshot(url, snapshot, links: true) = deliver(url, snapshot, links:)

      private

      def render(uri, wait)
        require "ferrum"
        require "json"
        browser = Ferrum::Browser.new(headless: true, timeout: TIMEOUT, process_timeout: TIMEOUT,
                                      browser_options: BROWSER_OPTIONS)
        page = browser.create_page
        secure_page(page)
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
      def guard_requests(page, budget:, allowed_host: nil)
        page.network.intercept
        page.on(:request) do |request|
          handle_request(request, budget:, allowed_host:)
        rescue StandardError => e
          Master::Ground::Swallow.log(e, context: "WebBrowse.request") rescue nil
          request.abort rescue nil
        end
      end

      def handle_request(request, budget:, allowed_host: nil)
        return request.abort unless reserve_request!(budget)

        uri = URI(request.url.to_s)
        return request.abort unless web_uri?(uri)
        return request.abort unless request_allowed_for_host?(uri, allowed_host)

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
      rescue ResourceLimit, UnsupportedContentEncoding
        request.abort
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WebBrowse.pinned_get", url: request.url) rescue nil
        request.abort
      end

      def web_uri?(uri)
        %w[http https].include?(uri.scheme.to_s.downcase) && !uri.host.to_s.empty? && uri.userinfo.nil?
      end

      def request_allowed_for_host?(uri, allowed_host)
        return true if allowed_host.nil?

        canonical_host(uri.host) == canonical_host(allowed_host)
      end

      def canonical_host(host)
        host.to_s.downcase.sub(/\.\z/, "").sub(/\Awww\./, "")
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

            encoding = incoming["content-encoding"].to_s.strip.downcase
            unless encoding.empty? || encoding == "identity"
              raise UnsupportedContentEncoding, "refused encoded response: #{encoding}"
            end

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
        if (headings = snapshot["headings"]).is_a?(Array) && !headings.empty?
          list = headings.first(40).map { |heading| "#{heading["level"]}: #{heading["text"]}" }
          body << "\n\nHeadings:\n#{list.join("\n")}"
        end
        if (counts = snapshot["counts"]).is_a?(Hash) && !counts.empty?
          summary = counts.map { |name, count| "#{name}=#{count}" }.join(", ")
          body << "\n\nPage elements: #{summary}"
        end
        if links && snapshot["links"].is_a?(Array) && !snapshot["links"].empty?
          list = snapshot["links"].uniq { |link| link["href"] }.first(MAX_LINKS).map { |link| "- #{link["text"]} → #{link["href"]}" }
          body << "\n\nLinks:\n#{list.join("\n")}"
        end
        if (forms = snapshot["forms"]).is_a?(Array) && !forms.empty?
          lines = forms.first(10).map do |form|
            fields = Array(form["inputs"]).first(20).map do |input|
              [input["name"], input["type"], input["placeholder"]].map { |part| part.to_s[0, 80] }.reject(&:empty?).join(" / ")
            end.reject(&:empty?)
            " - #{form["method"].to_s.upcase[0, 8]} #{form["action"].to_s[0, 200]}#{fields.empty? ? "" : " (#{fields.join("; ")})"}"
          end
          body << "\n\nForms:\n#{lines.join("\n")}"
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
