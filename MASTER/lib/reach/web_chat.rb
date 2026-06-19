# frozen_string_literal: true

require "timeout"

module Master
  module Reach
    # Opt-in headless-browser bridge to free web chat UIs (ChatGPT, Gemini, etc).
    # Experimental and ToS-sensitive: never in the default chain — gate on MASTER_WEB_CHAT.
    class WebChat
      DEFAULT_TIMEOUT = 120
      ENABLE_ENV = "MASTER_WEB_CHAT"

      DisabledError = Class.new(StandardError)
      ProviderError = Class.new(StandardError)

      def self.call(provider:, prompt:, system: nil)
        new(provider: provider).ask(prompt: prompt, system: system)
      end

      def initialize(provider:)
        @provider = provider.to_s
        @config = provider_config(@provider)
      end

      def ask(prompt:, system: nil)
        raise DisabledError, "web chat disabled; set #{ENABLE_ENV}=1" unless enabled?
        full_prompt = [system, prompt].compact.join("\n\n")
        with_browser { |page| converse(page, full_prompt) }
      end

      private

      def enabled? = ENV[ENABLE_ENV].to_s != ""

      def provider_config(name)
        path = File.join(Master::ROOT, "data", "models.yml")
        providers = Master.load_yaml(path).dig("ferrum_web_chat", "providers") || {}
        providers.fetch(name) { raise ProviderError, "unknown web chat provider: #{name}" }
      end

      def with_browser
        require "ferrum"
        browser = Ferrum::Browser.new(headless: true, timeout: timeout_seconds, process_timeout: timeout_seconds)
        yield browser.create_page
      ensure
        browser&.quit
      end

      def converse(page, text)
        Timeout.timeout(timeout_seconds) do
          page.go_to(@config.fetch("url"))
          fill_prompt(page, text)
          read_reply(page)
        end
      rescue Timeout::Error
        raise ProviderError, "#{@provider}: timed out after #{timeout_seconds}s"
      end

      def fill_prompt(page, text)
        field = page.at_css(@config.fetch("input_selector"))
        raise ProviderError, "#{@provider}: input not found (login required?)" unless field
        field.focus.type(text, :Enter)
      end

      def read_reply(page)
        wait_idle(page)
        node = page.at_css(@config.fetch("reply_selector"))
        raise ProviderError, "#{@provider}: no reply at configured selector" unless node
        node.text.to_s.strip
      end

      def wait_idle(page)
        page.network.wait_for_idle(timeout: timeout_seconds)
      rescue StandardError
        nil
      end

      def timeout_seconds = (@config["timeout"] || DEFAULT_TIMEOUT).to_i
    end
  end
end
