# frozen_string_literal: true
require "base64"
require "fileutils"

module Master
  module Web
    SCREENSHOT_DIR = File.join(Master::ROOT, "var", "screenshots")
    
    class Browser
      def initialize
        @browser = nil
        @available = false
        check_availability
      end
      
      def check_availability
        require "ferrum"
        @available = true
      rescue LoadError
        @available = false
      end
      
      def available?
        @available
      end
      
      def start
        return unless @available
        require "ferrum"
        @browser ||= Ferrum::Browser.new(
          headless: true,
          timeout: 30,
          window_size: [1280, 800]
        )
      end
      
      def stop
        @browser&.quit
        @browser = nil
      end
      
      def fetch(url)
        return Result.err("Ferrum not installed (bundle install)") unless @available
        
        start
        @browser.goto(url)
        
        # Wait for page load
        sleep 1
        
        # Get page content
        title = @browser.title rescue "Unknown"
        text = extract_text
        html = @browser.body rescue ""
        
        # Take screenshot
        screenshot_path = take_screenshot(url)
        screenshot_base64 = nil
        if screenshot_path && File.exist?(screenshot_path)
          screenshot_base64 = Base64.strict_encode64(File.read(screenshot_path, mode: "rb"))
        end
        
        Result.ok({
          url: url,
          title: title,
          text: text,
          html: html,
          screenshot_path: screenshot_path,
          screenshot_base64: screenshot_base64
        })
      rescue => e
        Result.err("Browser error: #{e.message}")
      end
      
      def extract_text
        # Get visible text, strip scripts/styles
        @browser.evaluate(<<~JS)
          (function() {
            var clone = document.body.cloneNode(true);
            var scripts = clone.querySelectorAll('script, style, noscript');
            scripts.forEach(function(s) { s.remove(); });
            return clone.innerText || clone.textContent || '';
          })()
        JS
      rescue
        ""
      end
      
      def take_screenshot(url)
        FileUtils.mkdir_p(SCREENSHOT_DIR)
        filename = "#{Time.now.to_i}_#{url.gsub(/[^a-z0-9]/i, '_')[0..30]}.png"
        path = File.join(SCREENSHOT_DIR, filename)
        @browser.screenshot(path: path)
        path
      rescue
        nil
      end
      
      def click(selector)
        return Result.err("Ferrum not installed") unless @available
        start
        element = @browser.at_css(selector)
        return Result.err("Element not found: #{selector}") unless element
        element.click
        sleep 1
        Result.ok("Clicked #{selector}")
      rescue => e
        Result.err("Click error: #{e.message}")
      end
      
      def type(selector, text)
        return Result.err("Ferrum not installed") unless @available
        start
        element = @browser.at_css(selector)
        return Result.err("Element not found: #{selector}") unless element
        element.focus.type(text)
        Result.ok("Typed into #{selector}")
      rescue => e
        Result.err("Type error: #{e.message}")
      end
      
      def scroll(direction = :down)
        return Result.err("Ferrum not installed") unless @available
        start
        amount = direction == :down ? 500 : -500
        @browser.execute("window.scrollBy(0, #{amount})")
        sleep 0.5
        Result.ok("Scrolled #{direction}")
      rescue => e
        Result.err("Scroll error: #{e.message}")
      end
    end
    
    class << self
      def browser
        @browser ||= Browser.new
      end
      
      def fetch(url)
        browser.fetch(url)
      end
      
      def analyze(url, llm, question = nil)
        result = fetch(url)
        return result unless result.ok?
        
        data = result.value
        
        # Build prompt with page content
        prompt = <<~PROMPT
          Analyze this webpage:
          
          URL: #{data[:url]}
          Title: #{data[:title]}
          
          Page text (first 5000 chars):
          #{data[:text][0..5000]}
          
        PROMPT
        
        if question
          prompt += "\nQuestion: #{question}\n"
        else
          prompt += "\nProvide a brief summary of what this page contains.\n"
        end
        
        # If screenshot available and model supports vision, include it
        if data[:screenshot_base64]
          # For now, just mention screenshot was taken
          prompt += "\n[Screenshot saved to: #{data[:screenshot_path]}]\n"
        end
        
        llm.ask(prompt, tier: :medium)
      end
      
      def navigate(url, actions, llm)
        # actions: array of {action: "click/type/scroll", selector: "...", text: "..."}
        result = fetch(url)
        return result unless result.ok?
        
        actions.each do |action|
          case action[:action]
          when "click"
            browser.click(action[:selector])
          when "type"
            browser.type(action[:selector], action[:text])
          when "scroll"
            browser.scroll(action[:direction]&.to_sym || :down)
          when "wait"
            sleep(action[:seconds] || 1)
          end
        end
        
        # Get final state
        fetch(browser.instance_variable_get(:@browser)&.current_url || url)
      end
    end
  end
end
