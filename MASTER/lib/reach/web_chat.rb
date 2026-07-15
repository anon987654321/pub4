# frozen_string_literal: true

require "timeout"
require "fileutils"

module Master
  module Reach
    # Headless-browser bridge to free web chat UIs (Grok, ChatGPT, Kimi, Gemini).
    # Auto-activates when no API keys; opt-in via MASTER_WEB_CHAT or MASTER_KEYLESS.
    class WebChat
      DEFAULT_TIMEOUT = 120
      ENABLE_ENV = "MASTER_WEB_CHAT"
      KEYLESS_ENV = "MASTER_KEYLESS"
      POLL_INTERVAL_S = 0.5

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
        raise DisabledError, disabled_message unless enabled?
        full_prompt = [system, prompt].compact.join("\n\n")
        with_browser { |page| converse(page, full_prompt) }
      end

      private

      def enabled?
        return true if ENV[KEYLESS_ENV].to_s != ""
        return true if ENV[ENABLE_ENV].to_s != ""
        Master.keyless_llm_enabled?
      end

      def disabled_message
        "web chat disabled; set #{ENABLE_ENV}=1, #{KEYLESS_ENV}=1, or configure API keys"
      end

      def provider_config(name)
        path = File.join(Master::ROOT, "data", "models.yml")
        providers = Master.load_yaml(path).dig("ferrum_web_chat", "providers") || {}
        providers.fetch(name) { raise ProviderError, "unknown web chat provider: #{name}" }
      end

      def ferrum_config
        path = File.join(Master::ROOT, "data", "models.yml")
        Master.load_yaml(path).dig("ferrum_web_chat") || {}
      end

      def profile_path
        raw = ferrum_config["profile_dir"].to_s
        raw = "~/.config/master/web-chat-profile" if raw.empty?
        File.expand_path(raw)
      end

      def with_browser
        require "ferrum"
        FileUtils.mkdir_p(profile_path)
        browser = Ferrum::Browser.new(
          headless: true,
          timeout: timeout_seconds,
          process_timeout: timeout_seconds,
          browser_options: { "user-data-dir" => profile_path }
        )
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
        field = find_element(page, @config.fetch("input_selector"))
        raise ProviderError, "#{@provider}: input not found (login required?)" unless field
        field.focus.type(text, :Enter)
      end

      def read_reply(page)
        wait_for_reply(page)
        node = find_element(page, @config.fetch("reply_selector"))
        raise ProviderError, "#{@provider}: no reply at configured selector" unless node
        extract_text(node)
      end

      def find_element(page, selector)
        selector.to_s.split(",").map(&:strip).each do |css|
          node = page.at_css(css)
          return node if node
        end
        nil
      end

      def extract_text(node)
        text = node.text.to_s.strip
        return text unless text.empty?
        node.inner_html.to_s.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
      end

      def wait_for_reply(page)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
        last_len = 0
        stable = 0
        loop do
          wait_idle(page)
          node = find_element(page, @config.fetch("reply_selector"))
          len = node ? extract_text(node).length : 0
          stable = len.positive? && len == last_len ? stable + 1 : 0
          last_len = len
          return if stable >= 2
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          sleep POLL_INTERVAL_S
        end
      end

      def wait_idle(page)
        page.network.wait_for_idle(timeout: 5)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WebChat.wait_idle")
        nil
      end

      def timeout_seconds = (@config["timeout"] || DEFAULT_TIMEOUT).to_i
    end
  end
end
