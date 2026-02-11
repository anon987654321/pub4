# frozen_string_literal: true

require "net/http"
require "uri"

module MASTER
  # Web - Browse and fetch web content with LLM-powered automation
  # Security: Uses nokogiri for safe HTML parsing (prevents ReDoS)
  # Features: Dynamic CSS selector discovery via LLM
  module Web
    extend self

    MAX_CONTENT_LENGTH = 5000
    MAX_PREVIEW_LENGTH = 2000
    BROWSER_LOAD_DELAY = 2
    MAX_HTML_FOR_DISCOVERY = 5000

    def browse(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(Net::HTTP::Get.new(uri))

      if response.code.start_with?("2")
        # Use nokogiri for safe HTML parsing
        text = extract_text(response.body)

        Result.ok(content: text[0, MAX_CONTENT_LENGTH], url: url, status: response.code)
      else
        Result.err("HTTP #{response.code} for #{url}")
      end
    rescue StandardError => e
      Result.err("Browse failed: #{e.message}")
    end

    # JavaScript-rendered pages using Ferrum (optional)
    def browse_js(url)
      require "ferrum"
      
      browser = Ferrum::Browser.new(headless: true, timeout: 30)
      browser.go_to(url)
      browser.network.wait_for_idle
      
      text = extract_text(browser.body)
      browser.quit
      
      Result.ok(content: text[0, MAX_CONTENT_LENGTH], url: url)
    rescue LoadError
      Result.err("Ferrum gem not available - install for JS-rendered pages")
    rescue StandardError => e
      Result.err("Browse JS failed: #{e.message}")
    ensure
      browser&.quit rescue nil
    end

    # Dynamic CSS selector discovery using LLM + vision
    # Instead of hardcoding selectors that break, ask LLM to find them
    def discover_selector(url, action)
      require "ferrum"
      
      browser = Ferrum::Browser.new(headless: true)
      page = browser.create_page
      page.go_to(url)
      sleep BROWSER_LOAD_DELAY

      html_snippet = page.body[0..MAX_HTML_FOR_DISCOVERY]
      screenshot_b64 = page.screenshot(format: :png, encoding: :base64)
      
      browser.quit

      prompt = <<~PROMPT
        Analyze this webpage to find the CSS selector for: #{action}
        
        HTML (truncated):
        #{html_snippet}
        
        Return ONLY the CSS selector, nothing else.
        Example: button.submit-btn, input#search, div.login-form
      PROMPT

      # Use vision model if possible for better accuracy
      result = LLM.ask(prompt, tier: :fast)
      return Result.err("LLM request failed") unless result.ok?

      # Clean up response - extract just the selector
      selector = result.value[:content].to_s.strip.split("\n").first.to_s.strip
      selector = selector.gsub(/^['"`]|['"`]$/, "") # Remove quotes

      Result.ok(selector: selector)
    rescue LoadError
      Result.err("Ferrum not available - install gem 'ferrum' for browser automation")
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
      Result.err("Ferrum not available - install gem 'ferrum'")
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
      Result.err("Ferrum not available - install gem 'ferrum'")
    rescue StandardError => e
      Result.err("Fill failed: #{e.message}")
    end

    private

    def extract_text(html)
      require "nokogiri"
      
      doc = Nokogiri::HTML(html)
      doc.css("script, style").remove
      text = doc.text.squeeze(" \n").strip
      text
    rescue LoadError
      # CRITICAL: nokogiri gem is required for HTML parsing
      # Install nokogiri to use web browsing features
      # No fallback is provided due to ReDoS security concerns
      "ERROR: nokogiri gem not installed. Run: gem install nokogiri"
    end
  end
end
