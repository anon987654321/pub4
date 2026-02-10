# frozen_string_literal: true

module MASTER
  # Conversation - Conversational context tracking stub
  # Simplified version for MASTER2 autonomy
  module Conversation
    extend self
    
    @history = []
    
    def add(role:, content:)
      @history << { role: role, content: content, timestamp: Time.now }
      @history = @history.last(20) if @history.size > 20 # Keep last 20
      true
    end
    
    def history
      @history
    end
    
    def clear
      @history = []
    end
    
    def last(n = 1)
      @history.last(n)
    end
    
    def context
      @history.map { |h| "#{h[:role]}: #{h[:content]}" }.join("\n")
    end
  end
end
