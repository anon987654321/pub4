# frozen_string_literal: true

require 'json'
require 'zlib'

module MASTER
  # Conversation history with rolling summary compression for long sessions
  class SessionPersistence
    HISTORY_FILE = File.join(Paths.var, 'session_history.json')
    MAX_MESSAGES = 100
    SUMMARY_THRESHOLD = 50  # Summarize when exceeding this many messages
    
    attr_reader :messages, :summary
    
    def initialize(llm: nil)
      @llm = llm || LLM.new
      @messages = []
      @summary = nil
      @session_id = generate_session_id
      load_history
    end
    
    # Add message to history
    def add(role:, content:, metadata: {})
      message = {
        role: role,
        content: content,
        metadata: metadata,
        timestamp: Time.now.to_i
      }
      
      @messages << message
      
      # Compress if too many messages
      compress_if_needed
      
      save_history
      message
    end
    
    # Get conversation context for LLM
    def context(include_summary: true)
      context = []
      
      # Add summary if available and requested
      if include_summary && @summary
        context << {
          role: 'system',
          content: "Previous conversation summary: #{@summary}"
        }
      end
      
      # Add recent messages
      context + @messages
    end
    
    # Get last N messages
    def recent(count = 10)
      @messages.last(count)
    end
    
    # Search messages by content
    def search(query)
      @messages.select do |msg|
        msg[:content].downcase.include?(query.downcase)
      end
    end
    
    # Clear history
    def clear
      @messages.clear
      @summary = nil
      save_history
    end
    
    # Get statistics
    def stats
      {
        session_id: @session_id,
        total_messages: @messages.size,
        has_summary: !@summary.nil?,
        user_messages: @messages.count { |m| m[:role] == 'user' },
        assistant_messages: @messages.count { |m| m[:role] == 'assistant' },
        total_tokens: estimate_tokens,
        oldest_message: @messages.first&.[](:timestamp),
        newest_message: @messages.last&.[](:timestamp)
      }
    end
    
    # Export to different formats
    def export(format: :json)
      case format
      when :json
        JSON.pretty_generate(
          session_id: @session_id,
          summary: @summary,
          messages: @messages
        )
      when :markdown
        export_markdown
      when :text
        export_text
      else
        raise ArgumentError, "Unknown format: #{format}"
      end
    end
    
    private
    
    # Compress old messages into summary
    def compress_if_needed
      return unless @messages.size > SUMMARY_THRESHOLD
      
      # Keep recent messages, summarize older ones
      keep_count = 20
      to_summarize = @messages[0...-keep_count]
      
      return if to_summarize.empty?
      
      # Generate summary
      old_summary = @summary
      new_context = to_summarize.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n\n")
      
      prompt = if old_summary
                 "Previous summary: #{old_summary}\n\nNew messages:\n#{new_context}\n\nProvide updated summary:"
               else
                 "Summarize this conversation:\n#{new_context}\n\nProvide concise summary:"
               end
      
      @summary = @llm.quick_ask(prompt, model: 'deepseek')
      
      # Keep only recent messages
      @messages = @messages.last(keep_count)
      
      puts "Compressed #{to_summarize.size} messages into summary" if ENV['DEBUG']
    end
    
    # Load history from disk
    def load_history
      return unless File.exist?(HISTORY_FILE)
      
      data = JSON.parse(File.read(HISTORY_FILE), symbolize_names: true)
      @session_id = data[:session_id] || generate_session_id
      @summary = data[:summary]
      @messages = data[:messages] || []
    rescue => e
      puts "Failed to load history: #{e.message}" if ENV['DEBUG']
    end
    
    # Save history to disk
    def save_history
      data = {
        session_id: @session_id,
        summary: @summary,
        messages: @messages,
        saved_at: Time.now.to_i
      }
      
      File.write(HISTORY_FILE, JSON.pretty_generate(data))
    end
    
    # Generate unique session ID
    def generate_session_id
      "session_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
    end
    
    # Estimate token count
    def estimate_tokens
      # Rough estimate: 1 token ≈ 4 characters
      total_chars = @messages.sum { |m| m[:content].size }
      (total_chars / 4.0).round
    end
    
    # Export as markdown
    def export_markdown
      lines = ["# Session #{@session_id}", ""]
      
      if @summary
        lines << "## Summary"
        lines << @summary
        lines << ""
      end
      
      lines << "## Messages"
      lines << ""
      
      @messages.each do |msg|
        time = Time.at(msg[:timestamp]).strftime('%Y-%m-%d %H:%M:%S')
        lines << "### #{msg[:role].capitalize} (#{time})"
        lines << msg[:content]
        lines << ""
      end
      
      lines.join("\n")
    end
    
    # Export as plain text
    def export_text
      lines = []
      
      if @summary
        lines << "=== SUMMARY ==="
        lines << @summary
        lines << ""
      end
      
      @messages.each do |msg|
        time = Time.at(msg[:timestamp]).strftime('%Y-%m-%d %H:%M:%S')
        lines << "[#{time}] #{msg[:role]}:"
        lines << msg[:content]
        lines << ""
      end
      
      lines.join("\n")
    end
  end
end
