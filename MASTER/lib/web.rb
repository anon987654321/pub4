# frozen_string_literal: true

module MASTER
  module Web
    MAX_PREVIEW_LENGTH = 2000
    BROWSER_LOAD_DELAY = 2
    CURL_TIMEOUT = 10

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
