# frozen_string_literal: true

require "json"

begin
  require "ferrum"
rescue LoadError
  nil
end

module Shared
  class Scrape
    MODEL = ENV.fetch("SCRAPE_MODEL", Shared::Llm::DEFAULT_MODEL)
    HTML_MAX = 60_000

    def self.call(url, schema:, hint: nil)
      raise LoadError, "gem install ferrum — required for Scrape.call" unless defined?(Ferrum::Browser)

      browser = Ferrum::Browser.new(headless: true, timeout: 30,
                                    browser_options: { "no-sandbox": nil })
      begin
        browser.go_to(url)
        browser.network.wait_for_idle(timeout: 10)
        html = browser.body
        png = browser.screenshot(encoding: :binary, full: true)
        reason(url:, html:, png:, schema:, hint:)
      ensure
        browser.quit
      end
    end

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
