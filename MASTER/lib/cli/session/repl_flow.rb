# frozen_string_literal: true

require_relative "repl_io"

module Master
  module CLI
    class Session
      CONTEXT_STEP = 10_000
      CLOSE_WINDOW_S = 3
      BANG = /\A!(?<command>\S.*)\z/m

      private

      def set_visitor_mode_if_unauthenticated
        # Visitor is a web-request flag, set per request on ai.brgen.no.
        # The local CLI is the operator surface: treating a missing web_token
        # as a visitor handed `bin/master "read CLAUDE.md"` AskLlm and
        # WebSearch, no ReadFile, and a 45-cent reply asking for the text.
      end

      # ^D reads nil and closes the session. ^C at the prompt clears the line, as
      # zsh does, and a second ^C inside CLOSE_WINDOW_S closes it: on a phone
      # keyboard one stray press cost the session. A second ^C while it closes
      # exits at once, so a save stuck on a full disk cannot hold the terminal.
      def repl_loop
        while @running
          line = read_prompt_line
          break if line.nil?

          handle_repl_line(line) unless line == :interrupted
        end
      rescue Interrupt
        puts
      ensure
        trap("INT") { exit!(130) }
        close_session
      end

      def read_prompt_line
        line = safe_read_line(prompt_for_mode)
        puts if line.nil?
        line
      rescue Interrupt
        puts
        return if close_requested?

        Master::Trace::Dmesg.status("cli0", "^C again to exit")
        :interrupted
      end

      def close_requested?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        recent = @interrupted_at && now - @interrupted_at <= CLOSE_WINDOW_S
        @interrupted_at = now
        recent
      end

      def close_session
        return if @closed

        @closed = true
        stop_background_loop
        save_cli_history
        save_session_on_exit
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.close_session", event_bus: @refs.bus)
      end

      def prompt_for_mode
...[truncated]