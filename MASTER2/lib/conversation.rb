# frozen_string_literal: true

module MASTER
  # Conversational interface for natural language commands
  # Maintains context and handles follow-up questions
  # Standalone stub implementation for MASTER2
  class Conversation
    MAX_HISTORY = 10
    PRONOUNS = %w[it that this them these those].freeze

    attr_reader :history, :context

    def initialize
      @history = []
      @context = {
        current_file: nil,
        current_directory: nil,
        last_files: [],
        last_result: nil,
        last_intent: nil
      }
    end

    # Add a message to conversation history
    # @param role [Symbol] :user or :assistant
    # @param content [String] Message content
    # @return [void]
    def add_message(role, content)
      @history << { role: role, content: content, timestamp: Time.now }
      trim_history
    end

    # Get conversation history
    # @param limit [Integer] Max messages to return
    # @return [Array<Hash>] Recent messages
    def get_history(limit = MAX_HISTORY)
      @history.last(limit)
    end

    # Clear conversation history
    # @return [void]
    def clear
      @history.clear
      @context = {
        current_file: nil,
        current_directory: nil,
        last_files: [],
        last_result: nil,
        last_intent: nil
      }
    end

    # Update conversation context
    # @param key [Symbol] Context key
    # @param value [Object] Context value
    # @return [void]
    def update_context(key, value)
      @context[key] = value
    end

    # Get context value
    # @param key [Symbol] Context key
    # @return [Object] Context value or nil
    def get_context(key)
      @context[key]
    end

    # Check if input contains pronouns
    # @param text [String] Input text
    # @return [Boolean] true if pronouns detected
    def has_pronouns?(text)
      PRONOUNS.any? { |pronoun| text.downcase.include?(pronoun) }
    end

    # Build context string for LLM
    # @return [String] Context summary
    def context_string
      parts = []
      parts << "Current file: #{@context[:current_file]}" if @context[:current_file]
      parts << "Current directory: #{@context[:current_directory]}" if @context[:current_directory]
      parts << "Last files: #{@context[:last_files].join(', ')}" if @context[:last_files]&.any?
      parts.join("\n")
    end

    private

    def trim_history
      @history.shift while @history.size > MAX_HISTORY
    end
  end
end
