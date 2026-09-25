# frozen_string_literal: true

# Shared Ferrum + vision-LLM scraper for fictive data generation (Reddit, X, Amazon, fashion etc.).
# Used by brgen and amber rake tasks for seed augmentation.
# Requires OPENROUTER_API_KEY (or configure MODEL/ENDPOINT).

begin
  require "ferrum"
rescue LoadError
  nil
end
require "json"
require "stringio"

module Shared
  # Namespaced rather than bare: this sits at an engine autoload root, and a
  # host app defining its own top-level Scrape would shadow the engine copy
  # silently — which is how three apps ran without the engine ApplicationHelper
  # for months.
  class Scrape
    MODEL = ENV.fetch("SCRAPE_MODEL", "google/gemini-2.0-flash-001")
    ENDPOINT = URI("https://openrouter.ai/api/v1/chat/completions")
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
      require "ruby_llm"

      prompt = <<~TXT
        Source: #{url}
        Extract every listed item on the page as JSON. Use the screenshot to read visual layout (cards, sponsored banners, hidden overlays); use the HTML for exact text and links.
        #{hint}
        Reply with one JSON object: {"items":[{#{schema.join(', ')}}, ...]}.
        HTML (truncated to #{HTML_MAX} bytes):
        #{html.byteslice(0, HTML_MAX)}
      TXT
      attachment = RubyLLM::Attachment.new(StringIO.new(png), filename: "page.png")
      response = RubyLLM.context { |config| config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY") }
                         .chat(model: MODEL, provider: :openrouter, assume_model_exists: true)
                         .with_params(response_format: { type: "json_object" })
                         .ask(prompt, with: attachment)
      JSON.parse(response.content).fetch("items", [])
    end

