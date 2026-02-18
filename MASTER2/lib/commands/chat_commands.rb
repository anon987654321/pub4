# frozen_string_literal: true

module MASTER
  module Commands
    # Lightweight conversational mode that bypasses the full engineering pipeline
    module ChatCommands
      def enter_chat_mode(_args)
        puts "\n  Entering conversational mode. Type 'exit' or Ctrl+D to return.\n"
        session = Session.current

        system_msg = {
          role: "system",
          content: "You are a concise, thoughtful assistant. Respond naturally in prose. " \
                   "Keep replies short unless asked to elaborate. No bullet points unless requested."
        }

        loop do
          print "→ "
          input = $stdin.gets&.strip
          break if input.nil? || input.empty? || input.downcase == "exit"

          session.add_user(input) if session.respond_to?(:add_user)

          messages = [system_msg]
          if session.respond_to?(:context_for_llm)
            messages += session.context_for_llm(max_messages: 12)
          else
            messages << { role: "user", content: input }
          end

          result = LLM.ask(
            input,
            messages: messages,
            tier: :fast,
            stream: true
          )

          if result.ok?
            content = result.value[:content]
            puts
            session.add_assistant(content, cost: result.value[:cost]) if session.respond_to?(:add_assistant)
          else
            UI.error(result.error) if defined?(UI)
          end
        end

        puts "  Back to command mode.\n"
      end
    end
  end
end
