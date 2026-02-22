# frozen_string_literal: true

require "uri"
require "async"
require "async/http/internet"

module MASTER
  # Web - Browse and fetch web content with LLM-powered automation
  # HTTP client: async-http (Falcon ecosystem) — consistent with server stack
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

      status  = nil
      content = nil

      Async do |task|
        task.with_timeout(WEB_TIMEOUT) do
          internet = Async::HTTP::Internet.new
          begin
            response = internet.get(url)
            status = response.status.to_s
            body   = response.read
            content = extract_text(body) if status.start_with?("2")
          ensure
            internet.close
          end
        end
      end

      if content
        Result.ok(content: content[0, MAX_CONTENT_LENGTH], url: url, status: status)
      else
        Result.err("HTTP #{status} for #{url}")
      end
    rescue Async::TimeoutError => e
      Result.err("Browse timeout after #{WEB_TIMEOUT}s: #{e.message}")
    rescue StandardError => e
      Result.err("Browse failed: #{e.message}")
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
    rescue StandardError => e
      Result.err("Browse JS failed: #{e.message}")
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
    rescue StandardError => e
      Result.err("Selector discovery failed: #{e.message}")
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
    rescue StandardError => e
      Result.err("Click failed: #{e.message}")
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
    rescue StandardError => e
      Result.err("Fill failed: #{e.message}")
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
