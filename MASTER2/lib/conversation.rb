# frozen_string_literal: true

module Conversation
  DEFAULT_CONTEXT = {
    subject: nil,
    last_query: nil
  }.freeze

  class Engine
    def initialize(search_client:)
      @search_client = search_client
      @context = DEFAULT_CONTEXT.dup
    end

    def handle_input(user_text)
      text = user_text.to_s.strip
      return message("I didn't catch that.") if text.empty?

      resolved_text = resolve_pronouns(text)
      intent = detect_intent(resolved_text)
      execute_intent(intent, resolved_text)
    end

    def resolve_pronouns(text)
      subject = @context[:subject]
      return text unless subject

      text.gsub(/\b(it|that|they|them|those)\b/i, subject)
    end

    def detect_intent(text)
      return :search if text.match?(/\b(search|find|look up)\b/i)
      return :help if text.match?(/\b(help|commands)\b/i)

      :chat
    end

    def execute_intent(intent, text)
      case intent
      when :help
        message("Try: 'search cats', or ask a question.")
      when :search
        query = text.sub(/\A\s*(search|find|look up)\s+/i, "").strip
        return message("What would you like me to search for?") if query.empty?

        @context[:last_query] = query
        execute_search(query)
      else
        update_subject(text)
        message("You said: #{text}")
      end
    end

    def execute_search(query)
      results = begin
        @search_client.search(query)
      rescue StandardError => error
        return message("Search failed: #{error.message}")
      end

      message(format_results(results))
    end

    def format_results(results)
      items = Array(results).first(5)
      return "No results." if items.empty?

      items.each_with_index.map { |item, index| "#{index + 1}. #{item}" }.join("\n")
    end

    private

    def message(text)
      { type: "message", text: text }
    end

    def update_subject(text)
      candidate = text[/\b([A-Z][a-z]+)\b/, 1]
      @context[:subject] = candidate if candidate
    end
  end
end