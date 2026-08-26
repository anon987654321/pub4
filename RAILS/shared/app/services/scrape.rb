# frozen_string_literal: true

# Shared Ferrum + vision-LLM scraper for fictive data generation (Reddit, X, Amazon, fashion etc.).
# Used by brgen and amber rake tasks for seed augmentation.
# Requires OPENROUTER_API_KEY (or configure MODEL/ENDPOINT).

begin
  require "ferrum"
rescue LoadError
  nil
end
require "net/http"
require "json"
require "base64"

class Scrape
  MODEL = ENV.fetch("SCRAPE_MODEL", "google/gemini-2.0-flash-001")
  ENDPOINT = URI("https://openrouter.ai/api/v1/chat/completions")
  HTML_MAX = 60_000

  def self.call(url, schema:, hint: nil)
    raise LoadError, "gem install ferrum — required for Scrape.call" unless defined?(Ferrum::Browser)

    browser = Ferrum::Browser.new(headless: true, timeout: 30,
                                  browser_options: { "no-sandbox": nil })
    browser.go_to(url)
    browser.network.wait_for_idle(timeout: 10)
    html = browser.body
    png = Base64.strict_encode64(browser.screenshot(encoding: :binary, full: true))
    browser.quit
    reason(url:, html:, png:, schema:, hint:)
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
    payload = {
      model: MODEL,
      messages: [ {
        role: "user",
        content: [
          { type: "text",      text: prompt },
          { type: "image_url", image_url: { url: "data:image/png;base64,#{png}" } },
        ],
      } ],
      response_format: { type: "json_object" },
    }
    req = Net::HTTP::Post.new(ENDPOINT,
                              "Content-Type" => "application/json",
                              "Authorization" => "Bearer #{ENV.fetch('OPENROUTER_API_KEY')}")
    req.body = payload.to_json
    res = Net::HTTP.start(ENDPOINT.hostname, ENDPOINT.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
    JSON.parse(JSON.parse(res.body).dig("choices", 0, "message", "content")).fetch("items", [])
  end
end
