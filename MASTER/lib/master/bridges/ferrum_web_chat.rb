# frozen_string_literal: true

module Master
  module Bridges
    class FerrumWebChat
      # TODO: Interactive login flow is not implemented.
      # The browser is navigated to the provider URL but there is no mechanism to
      # authenticate, handle cookies, or wait for a logged-in session. This bridge
      # will always return an error until a session-management strategy is added.

      def ask(model_alias:, prompt:)
        ferrum = load_ferrum
        return ferrum if ferrum.respond_to?(:err?) && ferrum.err?

        browser = ferrum::Browser.new(timeout: 20)
        begin
          case model_alias
          when /openrouter/i
            browser.go_to("https://openrouter.ai/chat")
          when /replicate/i
            browser.go_to("https://replicate.com")
          else
            return Result.err("unsupported ferrum web chat alias: #{model_alias}", category: :validation)
          end

          Result.err("ferrum web chat requires interactive login/session; no session present", category: :provider)
        ensure
          browser.quit
        end
      rescue StandardError => e
        Result.err("ferrum bridge failed: #{e.message}", category: :provider)
      end

      private

      def load_ferrum
        # Use defined? to avoid double-requiring and the side-effects of re-running require
        return Ferrum if defined?(Ferrum)
        require "ferrum"
        Ferrum
      rescue LoadError
        Result.err("ferrum gem not installed; skipping web-chat piggyback", category: :provider)
      end
    end
  end
end
