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
  end
end
