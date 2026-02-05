# frozen_string_literal: true

module MASTER
  module Web
    MAX_PREVIEW_LENGTH = 2000
    BROWSER_LOAD_DELAY = 2
    CURL_TIMEOUT = 10
    MAX_HTML_FOR_DISCOVERY = 5000

    class << self
      def browse(url)
        return "Error: empty URL" if url.nil? || url.strip.empty?
        
        # Try Ferrum first, fall back to curl
        ferrum_browse(url)
      rescue LoadError
        curl_browse(url)
      rescue => e
        "Error: #{e.message}"
      end

      # Dynamic CSS selector discovery using LLM + vision
      # Instead of hardcoding selectors that break, ask LLM to find them
      def discover_selector(url, action, llm = nil)
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

        # Use vision if available, otherwise just HTML
        if llm&.respond_to?(:chat_with_image)
          result = llm.chat_with_image(prompt, screenshot_b64)
        elsif llm
          result = llm.chat(prompt)
          result = result.value if result.respond_to?(:value)
        else
          result = MASTER::LLM.new.chat(prompt)
          result = result.value if result.respond_to?(:value)
        end

        # Clean up response - extract just the selector
        selector = result.to_s.strip.split("\n").first.to_s.strip
        selector.gsub(/^['"`]|['"`]$/, '') # Remove quotes
      rescue => e
        nil
      end

      # Click an element discovered dynamically
      def click_discovered(url, action, llm = nil)
        require 'ferrum'

        selector = discover_selector(url, action, llm)
        return { success: false, error: "Could not find selector for: #{action}" } unless selector

        browser = Ferrum::Browser.new(headless: true)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        element = page.at_css(selector)
        return { success: false, error: "Element not found: #{selector}" } unless element

        element.click
        sleep 1
        
        result_html = page.body[0..MAX_PREVIEW_LENGTH]
        browser.quit

        { success: true, selector: selector, result: result_html }
      rescue => e
        { success: false, error: e.message }
      end

      # Fill a form field discovered dynamically  
      def fill_discovered(url, action, value, llm = nil)
        require 'ferrum'

        selector = discover_selector(url, action, llm)
        return { success: false, error: "Could not find selector for: #{action}" } unless selector

        browser = Ferrum::Browser.new(headless: true)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        element = page.at_css(selector)
        return { success: false, error: "Element not found: #{selector}" } unless element

        element.focus.type(value)
        sleep 0.5

        browser.quit
        { success: true, selector: selector, filled: value }
      rescue => e
        { success: false, error: e.message }
      end

      private

      def ferrum_browse(url)
        require 'ferrum'

        browser = Ferrum::Browser.new(headless: true)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        text = page.body_text
        screenshot_path = File.join(MASTER::ROOT, 'var', 'screenshots', "#{Time.now.to_i}.png")
        FileUtils.mkdir_p(File.dirname(screenshot_path))
        page.screenshot(path: screenshot_path)

        browser.quit

        "#{url}\n\n#{text[0..MAX_PREVIEW_LENGTH]}"
      end

      def curl_browse(url)
        html = `curl -sL --max-time #{CURL_TIMEOUT} "#{url}" 2>/dev/null`
        return "Failed to fetch: #{url}" if html.empty?

        # Strip HTML tags for plain text
        text = html.gsub(/<script[^>]*>.*?<\/script>/mi, '')
                   .gsub(/<style[^>]*>.*?<\/style>/mi, '')
                   .gsub(/<[^>]+>/, ' ')
                   .gsub(/\s+/, ' ')
                   .strip

        "#{url}\n\n#{text[0..MAX_PREVIEW_LENGTH]}"
      end
    end

    # GitHub search helper
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
          repos
        rescue => e
          ["Error: #{e.message}"]
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
          repos.map { |r| "https://github.com/#{r}" }
        rescue => e
          ["Error: #{e.message}"]
        end
      end
    end
  end
end
