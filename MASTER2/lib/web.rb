# frozen_string_literal: true

require "uri"
require "net/http"

module MASTER
  # Web - Browse and fetch web content with LLM-powered automation
  # HTTP client: net/http — avoids async-http getifaddrs permission issues in containers
  # Security: Uses nokogiri for safe HTML parsing (prevents ReDoS)
  # Features: Dynamic CSS selector discovery via LLM
  module Web
    extend self

    MAX_CONTENT_LENGTH = 5000
    MAX_PREVIEW_LENGTH = 2000
    BROWSER_LOAD_DELAY = 2
    MAX_HTML_FOR_DISCOVERY = 5000

    WEB_TIMEOUT        = (ENV["MASTER_WEB_TIMEOUT"]       || 30).to_i
    HTTP_OPEN_TIMEOUT  = (ENV["MASTER_HTTP_OPEN_TIMEOUT"] || 10).to_i

    def browse(url)
      uri = URI(url)
      return Result.err("Invalid URL scheme: #{uri.scheme}") unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.is_a?(URI::HTTPS)
      http.open_timeout = HTTP_OPEN_TIMEOUT
      http.read_timeout = WEB_TIMEOUT

      response = http.get(uri.request_uri)
      status = response.code
      content = extract_text(response.body) if status.start_with?("2")

      if content
        Result.ok(content: content[0, MAX_CONTENT_LENGTH], url: url, status: status)
      else
        Result.err("HTTP #{status} for #{url}")
      end
    rescue Net::OpenTimeout, Net::ReadTimeout => err
      Result.err("Browse timeout after #{WEB_TIMEOUT}s: #{err.message}")
    rescue StandardError => err
      Result.err("Browse failed: #{err.message}")
    end

    # JavaScript-rendered pages using Ferrum (optional)
    def browse_js(url)
      require "ferrum"

      browser = Ferrum::Browser.new(headless: true, timeout: WEB_TIMEOUT)
      browser.go_to(url)
      browser.network.wait_for_idle

      text = extract_text(browser.body)
      browser.quit

      Result.ok(content: text[0, MAX_CONTENT_LENGTH], url: url)
    rescue LoadError
      Result.err("Ferrum gem not available - install for JS-rendered pages.")
    rescue StandardError => err
      Result.err("Browse JS failed: #{err.message}")
    ensure
      begin
        browser&.quit
      rescue StandardError
        StandardError
      end
    end

    # Dynamic CSS selector discovery using LLM + vision
    def discover_selector(url, action)
      require "ferrum"

      browser = Ferrum::Browser.new(headless: true)
      page = browser.create_page
      page.go_to(url)
      sleep BROWSER_LOAD_DELAY

      html_snippet = page.body[0..MAX_HTML_FOR_DISCOVERY]
      page.screenshot(format: :png, encoding: :base64)

      browser.quit

      prompt = <<~PROMPT
        Analyze this webpage to find the CSS selector for: #{action}

        HTML (truncated):
        #{html_snippet}

        Return ONLY the CSS selector, nothing else.
        Example: button.submit-btn, input#search, div.login-form
      PROMPT

      result = LLM.ask(prompt, tier: :fast)
      return Result.err("LLM request failed.") unless result.ok?

      selector = result.value[:content].to_s.strip.split("\n").first.to_s.strip
      selector = selector.gsub(/^['"`]|['"`]$/, "")

      Result.ok(selector: selector)
    rescue LoadError
      Result.err("Ferrum not available - install gem 'ferrum' for browser automation.")
    rescue StandardError => err
      Result.err("Selector discovery failed: #{err.message}")
    end

    # Click an element discovered dynamically
    def click_discovered(url, action)
      selector_result = discover_selector(url, action)
      return selector_result unless selector_result.ok?

      selector = selector_result.value[:selector]

      require "ferrum"
      browser = Ferrum::Browser.new(headless: true)
      page = browser.create_page
      page.go_to(url)
      sleep BROWSER_LOAD_DELAY

      element = page.at_css(selector)
      unless element
        browser.quit
        return Result.err("Element not found: #{selector}")
      end

      element.click
      sleep 1

      result_html = page.body[0..MAX_PREVIEW_LENGTH]
      browser.quit

      Result.ok(selector: selector, result: result_html)
    rescue LoadError
      Result.err("Ferrum not available - install gem 'ferrum'.")
    rescue StandardError => err
      Result.err("Click failed: #{err.message}")
    end

    # Fill a form field discovered dynamically
    def fill_discovered(url, action, value)
      selector_result = discover_selector(url, action)
      return selector_result unless selector_result.ok?

      selector = selector_result.value[:selector]

      require "ferrum"
      browser = Ferrum::Browser.new(headless: true)
      page = browser.create_page
      page.go_to(url)
      sleep BROWSER_LOAD_DELAY

      element = page.at_css(selector)
      unless element
        browser.quit
        return Result.err("Element not found: #{selector}")
      end

      element.focus.type(value)
      sleep 0.5

      browser.quit
      Result.ok(selector: selector, filled: value)
    rescue LoadError
      Result.err("Ferrum not available - install gem 'ferrum'.")
    rescue StandardError => err
      Result.err("Fill failed: #{err.message}")
    end

    private

    def extract_text(html)
      require "nokogiri"

      doc = Nokogiri::HTML(html)
      doc.css("script, style").remove
      doc.text.squeeze(" \n").strip
    rescue LoadError
      raise "nokogiri gem required for HTML parsing"
    end
  end
end
