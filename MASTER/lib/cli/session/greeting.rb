# frozen_string_literal: true

require_relative "../welcome"

module Master
  module CLI
    class Session
      private

      # The model greets in its own words once the runtime is up, beside the prompt rather than before it: the
      # live-state line Welcome printed before boot is the instant answer, this is the personal one. It never
      # joins the conversation's history, and a model that cannot answer leaves nothing behind.
      # MASTER_GREETING=0 switches it off.
      def greet_from_model
        return if ENV["MASTER_GREETING"] == "0" || !$stdout.tty?

        Thread.new { deliver_greeting }
      end

      # A greeting that arrives after the operator has started talking is stale, and it printed onto the end of
      # the first reply ("...or mainly you?Late for hard conversations, Johann."), so it stands down.
      def deliver_greeting
        text = @refs.agent.ask_once(greeting_prompt, law: false).to_s.strip
        # A full-screen face owns the terminal until it closes.
        sleep 0.2 while @face_open
        return if text.empty? || @pipeline_thread

        terminal_puts(@refs.renderer.render(text.lines.first.to_s.strip, mode: :dim))
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "cli.greeting", event_bus: @refs.bus)
      end

      # Named outright: told only "the language of his last message", the model answered an English
      # message in Norwegian about half the time, cued by the hour and the city.
      GREETING_LANGUAGES = { nb: "Norwegian Bokmål", ms: "Malay", en: "English" }.freeze

      def greeting_prompt
        context = Master::CLI::Welcome.context(Master::ROOT)
        language = GREETING_LANGUAGES.fetch(Master::Voice::Language.detect(context[:last_message]), "English")

        <<~PROMPT
          You are MASTER, greeting Johann as a terminal session opens. One line, at most twenty words, in
          #{language}. Draw on the moment, not on a formula; no question about goals.

          Now: #{context[:time]}. #{context[:line]}.
          His last message: #{context[:last_message].to_s[0, 300].inspect}
        PROMPT
      end
    end
  end
end
