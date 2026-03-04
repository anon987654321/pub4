# frozen_string_literal: true

module Commands
  module ChatCommands
    EXIT_COMMANDS  = %w[/exit /quit exit quit].freeze
    HELP_COMMANDS  = %w[/help help].freeze
    RESET_COMMANDS = %w[/reset reset /clear clear].freeze

    Result = Struct.new(:type, :payload, keyword_init: true)

    def enter_chat_mode(session:, chat_service:, input_lines:)
      return Result.new(type: :error, payload: "No active chat session") unless session
      return Result.new(type: :error, payload: "No chat service provided") unless chat_service
      return Result.new(type: :error, payload: "No input provided") unless input_lines

      results = []

      input_lines.each do |raw_line|
        result = handle_chat_line(session: session, chat_service: chat_service, line: raw_line)
        results << result
        break if result.type == :exit
      end

      results
    end

    private

    def handle_chat_line(session:, chat_service:, line:)
      normalized = normalize_line(line)
      return Result.new(type: :noop, payload: nil) if normalized.empty?

      command = command_for(normalized)
      return handle_command(session: session, chat_service: chat_service, command: command) if command

      handle_message(session: session, chat_service: chat_service, message: normalized)
    end

    def normalize_line(line)
      line.to_s.strip
    end

    def command_for(normalized)
      return :exit if EXIT_COMMANDS.include?(normalized)
      return :help if HELP_COMMANDS.include?(normalized)
      return :reset if RESET_COMMANDS.include?(normalized)

      nil
    end

    def handle_command(session:, chat_service:, command:)
      case command
      when :exit
        Result.new(type: :exit, payload: "Exiting chat mode")
      when :help
        Result.new(type: :help, payload: help_text)
      when :reset
        reset_session(session, chat_service)
      else
        Result.new(type: :error, payload: "Unknown command")
      end
    end

    def help_text
      [
        "Chat commands:",
        "  /help  - show this help",
        "  /reset - clear conversation context",
        "  /exit  - leave chat mode"
      ].join("\n")
    end

    def reset_session(session, chat_service)
      if chat_service.respond_to?(:reset!)
        chat_service.reset!(session: session)
      elsif chat_service.respond_to?(:reset)
        chat_service.reset(session: session)
      end

      Result.new(type: :reset, payload: "Conversation reset")
    rescue StandardError => e
      Result.new(type: :error, payload: "Reset failed: #{e.message}")
    end

    def handle_message(session:, chat_service:, message:)
      response = fetch_response(session: session, chat_service: chat_service, message: message)
      Result.new(type: :message, payload: response)
    rescue StandardError => e
      Result.new(type: :error, payload: e.message)
    end

    def fetch_response(session:, chat_service:, message:)
      return chat_service.call(session: session, message: message) if chat_service.respond_to?(:call)
      return chat_service.chat(session: session, message: message) if chat_service.respond_to?(:chat)

      raise ArgumentError, "Chat service must respond to #call or #chat"
    end
  end
end