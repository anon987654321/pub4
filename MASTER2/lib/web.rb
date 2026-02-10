# frozen_string_literal: true

require "net/http"
require "uri"

module MASTER
  # Web - Browse and fetch web content with LLM-powered automation
  # Restored from MASTER v1 with dynamic CSS selector discovery
  module Web
    extend self

    MAX_CONTENT_LENGTH = 5000
    MAX_PREVIEW_LENGTH = 2000
    BROWSER_LOAD_DELAY = 2
    CURL_TIMEOUT = 10
    MAX_HTML_FOR_DISCOVERY = 5000

    # Simple browse using Net::HTTP (fallback, no JS execution)
    def browse(url)
      uri = URI(url)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 10
      http.read_timeout = 30

      response = http.request(Net::HTTP::Get.new(uri))

      if response.code.start_with?("2")
        # Simple text extraction - remove scripts, styles, and HTML tags
        # Using conservative patterns to avoid ReDoS vulnerabilities
        text = response.body.dup
        
        # Remove script blocks (limit backtracking)
        while (match = text.match(/<script(?:\s[^>]{0,200})?>|<script>/i))
          start_pos = match.begin(0)
          end_pos = text.index(/<\/script>/i, start_pos)
          if end_pos
            text[start_pos..(end_pos + 8)] = " "
          else
            text[start_pos..-1] = " "
            break
          end
        end
        
        # Remove style blocks (limit backtracking)
        while (match = text.match(/<style(?:\s[^>]{0,200})?>|<style>/i))
          start_pos = match.begin(0)
          end_pos = text.index(/<\/style>/i, start_pos)
          if end_pos
            text[start_pos..(end_pos + 7)] = " "
          else
            text[start_pos..-1] = " "
            break
          end
        end
        
        # Remove all remaining HTML tags with limited backtracking
        text.gsub!(/<[^<>]*>/, " ")
        
        # Normalize whitespace
        text.gsub!(/\s+/, " ")
        text.strip!

        Result.ok(content: text[0, MAX_CONTENT_LENGTH], url: url, status: response.code)
      else
        Result.err("HTTP #{response.code} for #{url}")
      end
    rescue StandardError => e
      Result.err("Browse failed: #{e.message}")
    end

    # Browse with JavaScript support using Ferrum (optional dependency)
    def browse_js(url)
      require 'ferrum'

      browser = Ferrum::Browser.new(headless: true)
      page = browser.create_page
      page.go_to(url)
      sleep BROWSER_LOAD_DELAY

      text = page.body_text
      browser.quit

      Result.ok(content: text[0, MAX_PREVIEW_LENGTH], url: url)
    rescue LoadError
      Result.err("Ferrum not available - install gem 'ferrum' for JS support")
    rescue StandardError => e
      Result.err("Browse JS failed: #{e.message}")
    end

    # Dynamic CSS selector discovery using LLM + vision
    # Instead of hardcoding selectors that break, ask LLM to find them
    def discover_selector(url, action)
      require 'ferrum'
      
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
      selector = selector.gsub(/^['"`]|['"`]$/, '') # Remove quotes

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

      require 'ferrum'
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

      require 'ferrum'
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

    # GitHub helpers
    module GitHub
      SEARCH_URL = 'https://github.com/search'

      class << self
        def search_repos(query, sort: 'stars', limit: 10)
          require 'ferrum'
          require 'uri'

          url = "#{SEARCH_URL}?q=#{URI.encode_www_form_component(query)}&type=repositories&s=#{sort}&o=desc"
          
          browser = Ferrum::Browser.new(headless: true)
          page = browser.create_page
          page.go_to(url)
          sleep 3  # GitHub is slow

          # Extract repo links
          repos = page.css('a[href*="/"][data-testid="results-list"] a, .repo-list-item a, div[data-testid] a').map do |link|
            href = link.attribute('href')
            next unless href&.match?(%r{^/[^/]+/[^/]+$})
            "https://github.com#{href}"
          end.compact.uniq.first(limit)

          # If CSS selectors don't work, try text extraction
          if repos.empty?
            text = page.body_text
            repos = text.scan(%r{github\.com/([a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+)}).flatten.uniq.first(limit).map { |r| "https://github.com/#{r}" }
          end

          browser.quit
          Result.ok(repos: repos)
        rescue LoadError
          Result.err("Ferrum not available - install gem 'ferrum'")
        rescue StandardError => e
          Result.err("Search failed: #{e.message}")
        end

        def trending(language: nil, since: 'daily')
          require 'ferrum'

          url = "https://github.com/trending"
          url += "/#{language}" if language
          url += "?since=#{since}"

          browser = Ferrum::Browser.new(headless: true)
          page = browser.create_page
          page.go_to(url)
          sleep 2

          text = page.body_text
          repos = text.scan(%r{([a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+)\s+\d+}).flatten.uniq.first(20)
          
          browser.quit
          Result.ok(repos: repos.map { |r| "https://github.com/#{r}" })
        rescue LoadError
          Result.err("Ferrum not available - install gem 'ferrum'")
        rescue StandardError => e
          Result.err("Trending fetch failed: #{e.message}")
        end
      end
    end
  end
end
