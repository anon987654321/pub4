# frozen_string_literal: true

module MASTER
  # Web - Browser automation with Ferrum, fallback to curl
  # Features: Dynamic CSS selector discovery via LLM
  module Web
    MAX_PREVIEW_LENGTH = 2000
    BROWSER_LOAD_DELAY = 2
    CURL_TIMEOUT = 10
    MAX_HTML_FOR_DISCOVERY = 5000

    class << self
      def browse(url)
        return Result.err("Empty URL") if url.nil? || url.strip.empty?

        ferrum_browse(url)
      rescue LoadError
        curl_browse(url)
      rescue StandardError => e
        Result.err("Browse failed: #{e.message}")
      end

      def discover_selector(url, action)
        require "ferrum"

        browser = Ferrum::Browser.new(headless: true, timeout: 30)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        html_snippet = page.body[0..MAX_HTML_FOR_DISCOVERY]
        screenshot_b64 = page.screenshot(format: :png, encoding: :base64) rescue nil

        browser.quit

        prompt = <<~PROMPT
          Analyze this webpage to find the CSS selector for: #{action}
          
          HTML (truncated):
          #{html_snippet}
          
          Return ONLY the CSS selector, nothing else.
          Example: button.submit-btn, input#search, div.login-form
        PROMPT

        result = LLM.ask(prompt, tier: :fast)
        return nil unless result.ok?

        selector = result.value[:content].to_s.strip.split("\n").first
        return nil if selector.nil? || selector.empty?
        selector.strip.gsub(/^['"`]|['"`]$/, "")
      rescue Ferrum::TimeoutError
        nil
      rescue StandardError
        nil
      end

      def click(url, action)
        require "ferrum"

        selector = discover_selector(url, action)
        return Result.err("Could not find selector for: #{action}") unless selector

        browser = Ferrum::Browser.new(headless: true, timeout: 30)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        element = page.at_css(selector)
        return Result.err("Element not found: #{selector}") unless element

        element.click
        sleep 1

        result_html = page.body[0..MAX_PREVIEW_LENGTH]
        browser.quit

        Result.ok(selector: selector, result: result_html)
      rescue LoadError
        Result.err("Ferrum not available - install with: gem install ferrum")
      rescue Ferrum::TimeoutError
        Result.err("Browser timeout")
      rescue StandardError => e
        Result.err("Click failed: #{e.message}")
      end

      def fill(url, action, value)
        require "ferrum"

        selector = discover_selector(url, action)
        return Result.err("Could not find selector for: #{action}") unless selector

        browser = Ferrum::Browser.new(headless: true, timeout: 30)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        element = page.at_css(selector)
        return Result.err("Element not found: #{selector}") unless element

        element.focus.type(value)
        sleep 0.5

        browser.quit
        Result.ok(selector: selector, filled: value)
      rescue LoadError
        Result.err("Ferrum not available")
      rescue Ferrum::TimeoutError
        Result.err("Browser timeout")
      rescue StandardError => e
        Result.err("Fill failed: #{e.message}")
      end

      def screenshot(url, path: nil)
        require "ferrum"

        browser = Ferrum::Browser.new(headless: true, timeout: 30)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        path ||= File.join(MASTER.root, "var", "screenshots", "#{Time.now.to_i}.png")
        FileUtils.mkdir_p(File.dirname(path))
        page.screenshot(path: path)

        browser.quit
        Result.ok(path: path)
      rescue LoadError
        Result.err("Ferrum not available")
      rescue Ferrum::TimeoutError
        Result.err("Browser timeout")
      rescue StandardError => e
        Result.err("Screenshot failed: #{e.message}")
      end

      private

      def ferrum_browse(url)
        require "ferrum"

        browser = Ferrum::Browser.new(headless: true, timeout: 30)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        text = page.body_text
        browser.quit

        Result.ok(url: url, content: text[0..MAX_PREVIEW_LENGTH])
      rescue Ferrum::TimeoutError
        curl_browse(url)
      end

      def curl_browse(url)
        html = if RUBY_PLATFORM.include?("openbsd")
                 `ftp -o - "#{url}" 2>/dev/null`
               else
                 `curl -sL --max-time #{CURL_TIMEOUT} "#{url}" 2>/dev/null`
               end

        html = `curl -sLk --max-time #{CURL_TIMEOUT} "#{url}" 2>/dev/null` if html.empty?

        return Result.err("Failed to fetch: #{url}") if html.empty?

        text = html.gsub(/<script[^>]*>.*?<\/script>/mi, "")
                   .gsub(/<style[^>]*>.*?<\/style>/mi, "")
                   .gsub(/<[^>]+>/, " ")
                   .gsub(/\s+/, " ")
                   .strip

        Result.ok(url: url, content: text[0..MAX_PREVIEW_LENGTH])
      end
    end

    module GitHub
      SEARCH_URL = "https://github.com/search"

      class << self
        def search_repos(query, sort: "stars", limit: 10)
          require "ferrum"
          require "uri"

          url = "#{SEARCH_URL}?q=#{URI.encode_www_form_component(query)}&type=repositories&s=#{sort}&o=desc"

          browser = Ferrum::Browser.new(headless: true)
          page = browser.create_page
          page.go_to(url)
          sleep 3

          text = page.body_text
          repos = text.scan(%r{github\.com/([a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+)}).flatten.uniq.first(limit)
          repos = repos.map { |r| "https://github.com/#{r}" }

          browser.quit
          Result.ok(repos: repos)
        rescue LoadError
          Result.err("Ferrum not available")
        rescue StandardError => e
          Result.err("Search failed: #{e.message}")
        end

        def trending(language: nil, since: "daily")
          require "ferrum"

          url = "https://github.com/trending"
          url += "/#{language}" if language
          url += "?since=#{since}"

          browser = Ferrum::Browser.new(headless: true)
          page = browser.create_page
          page.go_to(url)
          sleep 2

          text = page.body_text
          repos = text.scan(%r{([a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+)\s+\d+}).flatten.uniq.first(20)
          repos = repos.map { |r| "https://github.com/#{r}" }

          browser.quit
          Result.ok(repos: repos)
        rescue LoadError
          Result.err("Ferrum not available")
        rescue StandardError => e
          Result.err("Trending failed: #{e.message}")
        end
      end
    end
  end
end
