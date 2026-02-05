# frozen_string_literal: true

module MASTER
  module Web
    class << self
      def browse(url)
        require 'ferrum'

        browser = Ferrum::Browser.new(headless: true)
        page = browser.create_page
        page.go_to(url)
        
        # Wait for content
        sleep 2

        # Get text and screenshot
        text = page.body_text
        screenshot_path = File.join(MASTER::ROOT, 'var', 'screenshots', "#{Time.now.to_i}.png")
        FileUtils.mkdir_p(File.dirname(screenshot_path))
        page.screenshot(path: screenshot_path)

        browser.quit

        "Visited: #{url}\nScreenshot: #{screenshot_path}\n\n#{text[0..2000]}"
      rescue LoadError
        'Ferrum not installed. Run: gem install ferrum'
      rescue => e
        "Error: #{e.message}"
      end
    end
  end
end
