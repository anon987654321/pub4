# frozen_string_literal: true

module MASTER
  # Token streamer for streaming LLM responses to UI
  class TokenStreamer
    attr_reader :buffer, :tokens_sent
    
    def initialize(endpoint: nil)
      @endpoint = endpoint
      @buffer = ""
      @tokens_sent = 0
      @callbacks = []
      @start_time = nil
      @complete = false
    end
    
    # Stream tokens one at a time
    def stream(text, delay: 0.01)
      @start_time = Time.now
      @complete = false
      
      text.each_char do |char|
        send_token(char)
        sleep(delay) if delay > 0
      end
      
      @complete = true
      notify_complete
    end
    
    # Stream with word boundaries
    def stream_words(text, delay: 0.05)
      @start_time = Time.now
      @complete = false
      
      words = text.split(/(\s+)/)
      words.each do |word|
        word.each_char { |char| send_token(char) }
        sleep(delay) if delay > 0
      end
      
      @complete = true
      notify_complete
    end
    
    # Stream with sentence boundaries
    def stream_sentences(text, delay: 0.1)
      @start_time = Time.now
      @complete = false
      
      sentences = text.split(/([.!?]+\s+)/)
      sentences.each do |sentence|
        sentence.each_char { |char| send_token(char) }
        sleep(delay) if delay > 0
      end
      
      @complete = true
      notify_complete
    end
    
    # Send single token
    def send_token(token)
      @buffer += token
      @tokens_sent += 1
      
      # Send to SSE endpoint if available
      @endpoint&.send_token(token, metadata: stats)
      
      # Notify callbacks
      @callbacks.each { |cb| cb.call(token, @buffer) }
    end
    
    # Register callback for each token
    def on_token(&block)
      @callbacks << block
    end
    
    # Register callback for completion
    def on_complete(&block)
      @on_complete = block
    end
    
    # Get streaming statistics
    def stats
      {
        tokens_sent: @tokens_sent,
        buffer_size: @buffer.size,
        elapsed: elapsed_time,
        tokens_per_second: tokens_per_second,
        complete: @complete
      }
    end
    
    # Clear buffer
    def clear
      @buffer = ""
      @tokens_sent = 0
      @start_time = nil
      @complete = false
    end
    
    # Check if streaming is complete
    def complete?
      @complete
    end
    
    # Get current buffer
    def current_text
      @buffer
    end
    
    private
    
    # Calculate elapsed time
    def elapsed_time
      @start_time ? Time.now - @start_time : 0
    end
    
    # Calculate tokens per second
    def tokens_per_second
      return 0 unless @start_time
      
      duration = Time.now - @start_time
      duration > 0 ? @tokens_sent / duration : 0
    end
    
    # Notify completion
    def notify_complete
      @on_complete&.call(@buffer, stats)
      @endpoint&.send_complete(stats)
    end
  end
end
