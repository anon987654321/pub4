# frozen_string_literal: true

require "uri"

module Master
  module Io
    # Renders a page in headless Chrome and returns what a visitor would see.
    #
    # web_fetch reads the static response, which for a shop or any app-shell site
    # is a few kilobytes of script and no content (temu.com answers 2.9 KB), so a
    # request to find something on such a site had no tool that could do it and
    # ended in "I can't browse that from here". This is the tool for those pages:
    # read-only, no clicking and no login. Interaction stays with the governed
    # plugins (social_browser, travel_browser).
    #
    # The first URL is pinned through SsrfGuard like web_fetch; every sub-request
    # the page makes is checked against the same guard, so a redirect or an
    # embedded resource cannot reach an internal address.
    class WebBrowse
      TIER = :guarded
      NAME = "web_browse"
      DESCRIPTION = "Render a page in headless Chrome → title, visible text and links. For JavaScript sites web_fetch cannot read."
      TIMEOUT = 30
      SETTLE_SECONDS = 4
      MAX_TEXT = 16_000
      MAX_LINKS = 40

      SCRIPT = <<~JS
        (() => {
          const text = (document.body && document.body.innerText) || "";
          const links = Array.from(document.querySelectorAll("a[href]")).map(a => ({
            text: (a.innerText || a.getAttribute("aria-label") || "").trim().replace(/\\s+/g, " ").slice(0, 120),
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
        return Result.err("web_browse: only http(s)", category: :validation) unless %w[http https].include?(uri.scheme)
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
                                      browser_options: { "no-sandbox" => nil, "disable-gpu" => nil })
        page = browser.create_page
        guard_requests(page)
        page.go_to(uri.to_s)
        sleep wait
        JSON.parse(page.evaluate(SCRIPT))
      ensure
        browser&.quit
      end

      # Chrome follows redirects and loads sub-resources on its own; each host it
      # asks for is resolved and checked, once, and an unsafe one is aborted.
      def guard_requests(page)
        verdicts = {}
        page.network.intercept
        page.on(:request) do |request|
          host = URI(request.url).host.to_s rescue ""
          verdicts[host] = safe_host?(request.url) unless verdicts.key?(host)
          verdicts[host] ? request.continue : request.abort
        end
      end

      def safe_host?(url)
        uri = URI(url)
        return true unless %w[http https].include?(uri.scheme)

        !SsrfGuard.pinned_address(uri).nil?
      rescue StandardError
        false
      end

      # A site that turns a headless browser away says so in the address or the page.
      WALL = /captcha|verif(?:y|ication)|are you (?:a )?(?:human|robot)|access denied|unusual traffic|bot detection|blocked/i

      def deliver(url, snapshot, links:)
        text = snapshot["text"].to_s.delete("​‌‍﻿").gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
        body = +"#{snapshot["title"]}\n#{snapshot["url"]}\n\n#{text[0, MAX_TEXT]}"
        if text.length < 1500 && "#{snapshot["url"]} #{snapshot["title"]} #{text}".match?(WALL)
          body.prepend("NOTE: the site answered with a verification or bot wall instead of the page. " \
                       "Report that, and do not guess its contents.\n\n")
        end
        if links && snapshot["links"].is_a?(Array) && !snapshot["links"].empty?
          list = snapshot["links"].uniq { |l| l["href"] }.first(MAX_LINKS).map { |l| "- #{l["text"]} → #{l["href"]}" }
          body << "\n\nLinks:\n#{list.join("\n")}"
        end
        @bus&.publish("tool:after", tool: NAME, url:)
        @bus&.publish("tool:untrusted_output", tool: NAME, source: url)
        Result.ok(guarded(body, url))
      end

      # Rendered text is outside content becoming prompt, same as web_fetch.
      def guarded(text, url) = injection_guard.screen(text, tool: NAME, source: url, bus: @bus)

      def injection_guard
        @injection_guard ||= Master::Review::Security::InjectionGuard.new(mode: :permissive)
      end
    end
  end
end
