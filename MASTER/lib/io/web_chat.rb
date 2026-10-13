# frozen_string_literal: true

require "timeout"
require "fileutils"
require "digest"

module Master
  module Io
    # Browser bridge to free web chat UIs (Grok, ChatGPT, Kimi, Gemini). This
    # needs a signed-in provider website profile, not an API key; it stays in the
    # fallback pool even when API keys exist and is disabled only by explicit opt-out.
    class WebChat
      DEFAULT_TIMEOUT = 120
      ENABLE_ENV = "MASTER_WEB_CHAT"
      HEADFUL_ENV = "MASTER_WEB_CHAT_HEADFUL"
      POLL_INTERVAL_S = 0.5
      LOGIN_POLL_INTERVAL_S = 1.0
      PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
      PROFILE_MUTEX = Mutex.new

      DisabledError = Class.new(StandardError)
      ProviderError = Class.new(StandardError)

      def self.call(provider:, prompt:, system: nil)
        new(provider:).ask(prompt:, system:)
      end

      def initialize(provider:)
        @provider = provider.to_s
        @config = provider_config(@provider)
      end

      def ask(prompt:, system: nil)
        raise DisabledError, disabled_message unless enabled?

        @screenshot_evidence = []
        @screenshot_capture_failure_reported = false
        @submitted_text = nil
        full_prompt = [system, prompt].compact.join("\n\n")
        with_browser { |page| converse(page, full_prompt) }
      end

      # Metadata proves which visible states were captured without retaining chat
      # images in memory after the request or writing private screenshots by default.
      def screenshot_evidence = Array(@screenshot_evidence).map(&:dup)

      private

      def enabled?
        return false if ENV["MASTER_NO_WEB_CHAT"] == "1"
        ENV[ENABLE_ENV].to_s != "0"
      end

      def disabled_message
        "web chat disabled; unset MASTER_WEB_CHAT=0 and MASTER_NO_WEB_CHAT=1"
      end

      def provider_config(name)
        providers = Master.models_config.dig("ferrum_web_chat", "providers") || {}
        providers.fetch(name) { raise ProviderError, "unknown web chat provider: #{name}" }
      end

      def ferrum_config
        Master.models_config.dig("ferrum_web_chat") || {}
      end

      def profile_path
        raw = ferrum_config["profile_dir"].to_s
        raw = "~/.config/master/web-chat-profile" if raw.empty?
        File.expand_path(raw)
      end

      def with_browser
        require "ferrum"
        PROFILE_MUTEX.synchronize do
          browser = nil
          begin
            FileUtils.mkdir_p(profile_path, mode: 0o700)
            File.chmod(0o700, profile_path)
            browser = Ferrum::Browser.new(
              headless: ENV[HEADFUL_ENV] != "1",
              timeout: timeout_seconds,
              process_timeout: timeout_seconds,
              browser_options: { "user-data-dir" => profile_path },
            )
            yield browser.create_page
          ensure
            browser&.quit
          end
        end
      end

      def converse(page, text)
        Timeout.timeout(timeout_seconds) do
          page.go_to(@config.fetch("url"))
          capture_screenshot(page, stage: "loaded")
          previous = reply_state(page)
          @submitted_text = text.to_s
          fill_prompt(page, text)
          capture_screenshot(page, stage: "submitted")
          reply = read_reply(page, previous:)
          capture_screenshot(page, stage: "answered")
          reply
        end
      rescue Timeout::Error
        raise ProviderError, "#{@provider}: timed out after #{timeout_seconds}s"
      end

      def fill_prompt(page, text)
        selector = @config.fetch("input_selector")
        field = find_element(page, selector)
        field ||= wait_for_login(page, selector) if ENV[HEADFUL_ENV] == "1"
        unless field
          detail = ENV[HEADFUL_ENV] == "1" ? "sign-in did not expose the chat input" : "login required? set #{HEADFUL_ENV}=1 to sign in once"
          raise ProviderError, "#{@provider}: input not found (#{detail})"
        end
        field.focus.type(text, :Enter)
      end

      # A dedicated Ferrum profile has its own cookies. In explicit headful mode,
      # let the operator sign in on the real provider page before sending a prompt.
      def wait_for_login(page, selector)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + [timeout_seconds - 5, 1].max
        loop do
          field = find_element(page, selector)
          return field if field
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep LOGIN_POLL_INTERVAL_S
        end
        nil
      end

      def read_reply(page, previous: nil)
        reply = wait_for_reply(page, previous:)
        return reply unless reply.to_s.strip.empty?

        raise ProviderError, "#{@provider}: no new assistant reply appeared after submission"
      end

      # A page can contain earlier assistant turns. Read the last matching node
      # and its count so a repeated, text-identical answer still counts as new.
      def reply_state(page)
        nodes = page.css(@config.fetch("reply_selector")).select { |node| reply_candidate?(node) }
        node = nodes.last
        [nodes.size, node ? extract_text(node) : ""]
      end

      # Some provider selectors include both sides of the conversation. Reject
      # nodes marked as user input and the prompt echo before deciding that a
      # visible change is a new assistant answer.
      def reply_candidate?(node)
        roles = %w[data-message-author-role data-role role].filter_map do |name|
          value = node.attribute(name).to_s.strip.downcase
          value unless value.empty?
        rescue StandardError
          nil
        end
        return false if roles.any? { |value| value.match?(/\b(user|human|prompt|question|query)\b/) }
        return true if roles.any? { |value| value.match?(/\b(assistant|bot|model)\b/) }

        metadata = %w[class data-testid aria-label].filter_map do |name|
          value = node.attribute(name).to_s.strip.downcase
          value unless value.empty?
        rescue StandardError
          nil
        end.join(" ")
        return false if metadata.match?(/(?:\A|[\s_-])(user|human|prompt|question|query)(?:\z|[\s_-])/)
        return true if metadata.match?(/assistant|response|bot|model|markdown-body|message-content/)

        text = extract_text(node)
        !submitted_prompt_echo?(text) && !submitted_prompt_in_container?(text)
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "WebChat.reply_candidate", provider: @provider)
        false
      end

      def submitted_prompt_echo?(value)
        prompt = normalized_text(@submitted_text)
        text = normalized_text(value)
        !prompt.empty? && text == prompt
      end

      def submitted_prompt_in_container?(value)
        prompt = normalized_text(@submitted_text)
        text = normalized_text(value)
        !prompt.empty? && text.include?(prompt)
      end

      def normalized_text(value)
        value.to_s.gsub(/\s+/, " ").strip.downcase
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

      def wait_for_reply(page, previous: nil)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
        last_state = nil
        stable = 0
        loop do
          wait_idle(page)
          state = reply_state(page)
          changed = previous.nil? || state[0] > previous[0] || state[1] != previous[1]
          if changed && !state[1].strip.empty? && state == last_state
            stable += 1
          elsif changed && !state[1].strip.empty?
            stable = 1
          else
            stable = 0
          end
          return state[1] if stable >= 2

          last_state = state
          break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep POLL_INTERVAL_S
        end
        nil
      end

      # Ferrum returns the PNG bytes directly when :binary is requested. Images
      # stay in memory unless the operator explicitly sets a capture directory.
      def capture_screenshot(page, stage:)
        bytes = page.screenshot(encoding: :binary, format: "png")
        return unless bytes.is_a?(String) && bytes.start_with?(PNG_SIGNATURE)

        evidence = { stage:, bytes: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
        directory = ENV["MASTER_WEB_CHAT_SCREENSHOT_DIR"].to_s.strip
        unless directory.empty?
          capture_dir = File.expand_path(directory)
          FileUtils.mkdir_p(capture_dir, mode: 0o700)
          File.chmod(0o700, capture_dir)
          provider = @provider.gsub(/[^a-z0-9_-]/i, "_")
          stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
          path = File.join(capture_dir, "#{provider}-#{Process.pid}-#{stamp}-#{stage}-#{evidence[:sha256][0, 10]}.png")
          File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(bytes) }
          evidence[:path] = path
        end
        (@screenshot_evidence ||= []) << evidence.freeze
        evidence
      rescue StandardError => e
        unless @screenshot_capture_failure_reported
          @screenshot_capture_failure_reported = true
          Master::Ground::Swallow.log(e, context: "WebChat.screenshot", provider: @provider)
        end
        nil
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
