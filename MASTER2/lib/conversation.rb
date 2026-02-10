# frozen_string_literal: true

module MASTER
  class Conversation
    attr_reader :turns, :context

    def initialize
      @turns = []
      @context = {}
    end

    def add_message(role:, content:)
      @turns << { role: role.to_sym, content: content, timestamp: Time.now.utc.iso8601 }
      self
    end

    def history(limit: nil)
      limit ? @turns.last(limit) : @turns.dup
    end

    def last_message
      @turns.last
    end

    def clear
      @turns.clear
      @context.clear
      self
    end

    def set_context(key, value)
      @context[key.to_sym] = value
    end

    def to_messages(max: 20)
      @turns.last(max).map { |t| { role: t[:role].to_s, content: t[:content] } }
    end
  end
end
