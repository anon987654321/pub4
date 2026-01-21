#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI - WebChat Component
# Universal Free LLM Browser Client with Ferrum stealth mode

require "json"
require "fileutils"

module Convergence
  class WebChatClient
    PROVIDERS = {
      duckduckgo: {
        url: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=1",
        input_selector: 'textarea[name="user-prompt"]',
        submit_selector: 'button[type="submit"]',
        response_selector: '[data-testid="chat-message-content"]',
        daily_limit: Float::INFINITY,
        models: ["Claude 3.5 Haiku", "Llama 4", "Mistral", "GPT-4o mini"]
      },
      huggingchat: {
        url: "https://huggingface.co/chat/",
        input_selector: 'textarea[placeholder*="message"]',
        response_selector: ".prose",
        daily_limit: 50,
        models: ["Llama 3", "Mistral", "Falcon"]
      },
      perplexity: {
        url: "https://www.perplexity.ai/",
        input_selector: 'textarea[placeholder*="Ask"]',
        response_selector: ".prose",
        daily_limit: 20,
        models: ["Llama 3", "Mistral", "GPT-3.5"]
      },
      youchat: {
        url: "https://you.com/chat",
        input_selector: 'textarea[placeholder*="Ask"]',
        response_selector: '[data-testid="youchat-answer"]',
        daily_limit: 30,
        models: ["Multiple open models"]
      },
      poe: {
        url: "https://poe.com",
        input_selector: 'textarea',
        response_selector: '.Message_botMessageBubble',
        daily_limit: 100,
        models: ["GPT-3.5", "Claude", "Llama"],
        requires_login: true
      }
    }.freeze

    STATES = %i[ready connecting waiting_response streaming completed failed].freeze

    attr_reader :state, :current_provider, :session_path

    def initialize(initial_provider: :duckduckgo, session_dir: nil)
      @current_provider = initial_provider
      @state = :ready
      @browser = nil
      @page = nil
      @session_dir = session_dir || File.expand_path("~/.convergence/sessions")
      @session_path = File.join(@session_dir, "#{@current_provider}.json")
      @provider_attempts = Hash.new(0)
      @ferrum_available = ensure_ferrum
    end

    def send_message(text, &block)
      raise "Ferrum not available" unless @ferrum_available
      
      ensure_connected
      
      @state = :waiting_response
      
      input_el = find_element(@current_config[:input_selector])
      raise "Input element not found" unless input_el

      input_el.focus
      input_el.type(text)
      sleep 0.2

      if @current_config[:submit_selector]
        submit_el = find_element(@current_config[:submit_selector])
        submit_el&.click
      else
        input_el.type(:Enter)
      end

      @state = :streaming
      response = wait_for_response(&block)
      
      @state = :completed
      response
    rescue => e
      @state = :failed
      Log.warn("WebChat error", error: e.message) if defined?(Log)
      handle_failure(e)
    end

    def screenshot(path = nil)
      return nil unless @page
      
      path ||= "/tmp/webchat_screenshot_#{Time.now.to_i}.png"
      @page.screenshot(path: path)
      path
    rescue => e
      Log.warn("Screenshot failed", error: e.message) if defined?(Log)
      nil
    end

    def page_source
      @page&.body
    end

    def switch_provider(provider_name)
      raise "Unknown provider: #{provider_name}" unless PROVIDERS.key?(provider_name)
      
      disconnect
      @current_provider = provider_name
      @session_path = File.join(@session_dir, "#{@current_provider}.json")
      connect
    end

    def rotate_provider
      available = PROVIDERS.keys - [@current_provider]
      next_provider = available.min_by { |p| @provider_attempts[p] }
      
      if next_provider
        Log.info("Rotating to provider", provider: next_provider) if defined?(Log)
        switch_provider(next_provider)
      end
    end

    def connect
      return if @browser && @page
      
      @state = :connecting
      @current_config = PROVIDERS[@current_provider]
      
      setup_browser
      @page = @browser.create_page
      
      load_session if File.exist?(@session_path)
      
      @page.go_to(@current_config[:url])
      wait_for_ready
      
      @state = :ready
      @provider_attempts[@current_provider] += 1
    rescue => e
      @state = :failed
      raise "Connection failed: #{e.message}"
    end

    def disconnect
      @browser&.quit
      @browser = nil
      @page = nil
      @state = :ready
    end

    alias quit disconnect

    private

    def ensure_ferrum
      begin
        require "ferrum"
        true
      rescue LoadError
        return false if ENV["NO_AUTO_INSTALL"]
        
        first_run = !File.exist?(File.expand_path("~/.convergence_installed"))
        warn "Installing ferrum..." if first_run
        result = system("gem install ferrum --user-install --no-document --quiet 2>/dev/null")
        return false unless result
        
        Gem.clear_paths
        begin
          require "ferrum"
          true
        rescue LoadError
          false
        end
      end
    end

    def setup_browser
      browser_path = find_browser_path
      raise "No browser found" unless browser_path

      # Ferrum stealth mode configuration
      options = {
        headless: true,
        timeout: 90,
        browser_path: browser_path,
        browser_options: {
          "no-sandbox": nil,
          "disable-blink-features": "AutomationControlled",
          "disable-dev-shm-usage": nil,
          "disable-gpu": nil,
          "window-size": "1920,1080"
        }
      }

      @browser = Ferrum::Browser.new(**options)
      
      # Override navigator properties to avoid detection
      @browser.evaluate_on_new_document(<<~JS)
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
        Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3, 4, 5] });
        Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
        window.chrome = { runtime: {} };
      JS
    end

    def find_browser_path
      paths = %w[
        /usr/local/bin/chromium
        /usr/bin/chromium
        /usr/bin/google-chrome
        /usr/local/bin/chrome
        /usr/bin/chromium-browser
        /snap/bin/chromium
      ]
      
      paths.find { |p| File.executable?(p) }
    end

    def ensure_connected
      connect unless @browser && @page
    end

    def find_element(selectors)
      return nil unless @page
      
      selectors = [selectors] unless selectors.is_a?(Array)
      selectors = selectors.first.split(", ") if selectors.size == 1
      
      selectors.each do |selector|
        begin
          el = @page.at_css(selector)
          return el if el
        rescue
          next
        end
      end
      
      nil
    end

    def wait_for_ready
      deadline = Time.now + 30
      
      until find_element(@current_config[:input_selector]) || Time.now > deadline
        sleep 0.5
      end
      
      raise "Timeout waiting for page ready" if Time.now > deadline
    end

    def wait_for_response(&block)
      deadline = Time.now + 90
      last_text = ""
      stable_count = 0
      
      loop do
        raise "Timeout waiting for response" if Time.now > deadline
        
        elements = begin
          @page.css(@current_config[:response_selector])
        rescue
          []
        end
        
        if elements.any?
          current_text = elements.last.text.strip
          
          if current_text == last_text && !current_text.empty?
            stable_count += 1
            if stable_count >= 3
              final_text = current_text.sub(/^(Model [AB]?:?\s*|Response:?\s*)/i, "").strip
              return final_text
            end
          else
            # Call streaming callback before updating last_text
            block&.call(current_text) if !current_text.empty? && current_text != last_text
            
            stable_count = 0
            last_text = current_text
          end
        end
        
        sleep 1
      end
    end

    def handle_failure(error)
      case error.message
      when /daily limit/i, /rate limit/i
        rotate_provider
        "Provider limit reached, rotated to #{@current_provider}"
      when /timeout/i
        rotate_provider
        "Timeout, rotated to #{@current_provider}"
      else
        "Error: #{error.message}"
      end
    end

    def save_session
      return unless @browser && @page
      
      FileUtils.mkdir_p(@session_dir)
      cookies = @page.cookies.all
      
      File.write(@session_path, JSON.generate({
        provider: @current_provider,
        cookies: cookies,
        timestamp: Time.now.to_i
      }))
    rescue => e
      Log.warn("Failed to save session", error: e.message) if defined?(Log)
    end

    def load_session
      return unless File.exist?(@session_path)
      
      data = JSON.parse(File.read(@session_path))
      return if Time.now.to_i - data["timestamp"] > 86400 # 24 hours
      
      data["cookies"]&.each do |cookie|
        @page.cookies.set(**cookie.transform_keys(&:to_sym))
      end
    rescue => e
      Log.warn("Failed to load session", error: e.message) if defined?(Log)
    end
  end
end
