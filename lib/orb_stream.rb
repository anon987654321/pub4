# frozen_string_literal: true

require 'async'
require 'json'

module MASTER
  # Token streaming with mood detection for live orb updates
  class OrbStream
    MOODS = {
      thinking: { color: '#4dccaa', animation: 'pulse' },
      excited: { color: '#ff6b6b', animation: 'bounce' },
      calm: { color: '#5eb3f6', animation: 'sway' },
      focused: { color: '#f8d347', animation: 'rotate' },
      complete: { color: '#51cf66', animation: 'fade' },
      error: { color: '#ff6b6b', animation: 'shake' }
    }.freeze
    
    attr_reader :mood, :tokens_per_second
    
    def initialize
      @mood = :thinking
      @tokens = []
      @start_time = nil
      @callbacks = []
      @sentiment_buffer = []
    end
    
    # Stream tokens and detect mood in real-time
    def stream_tokens(text, &block)
      @start_time = Time.now
      
      text.each_char.with_index do |char, i|
        @tokens << char
        @sentiment_buffer << char
        
        # Detect mood every 50 chars
        if (i + 1) % 50 == 0
          detect_mood(@sentiment_buffer.join)
          @sentiment_buffer.clear
        end
        
        yield(char, @mood) if block_given?
        notify_callbacks(char, @mood)
      end
      
      @mood = :complete
      calculate_tokens_per_second
    end
    
    # Detect mood from text sentiment
    def detect_mood(text)
      old_mood = @mood
      
      @mood = case text
              when /\b(error|failed|wrong|problem)\b/i
                :error
              when /\b(yes|great|success|perfect|excellent)\b/i
                :excited
              when /\b(consider|perhaps|might|could|possibly)\b/i
                :thinking
              when /\b(sure|okay|noted|understood)\b/i
                :calm
              when /\b(analyzing|processing|calculating|computing)\b/i
                :focused
              else
                @mood # Keep current mood
              end
      
      # Notify if mood changed
      notify_mood_change(old_mood, @mood) if old_mood != @mood
    end
    
    # Register callback for token events
    def on_token(&block)
      @callbacks << block
    end
    
    # Get current orb state as JSON
    def state
      {
        mood: @mood,
        color: MOODS[@mood][:color],
        animation: MOODS[@mood][:animation],
        tokens_count: @tokens.size,
        tokens_per_second: @tokens_per_second,
        elapsed: elapsed_time
      }
    end
    
    # Generate SSE event
    def to_sse
      "data: #{state.to_json}\n\n"
    end
    
    private
    
    def notify_callbacks(char, mood)
      @callbacks.each { |cb| cb.call(char, mood) }
    end
    
    def notify_mood_change(old_mood, new_mood)
      # Could broadcast to SSE endpoint here
      puts "Mood: #{old_mood} -> #{new_mood}" if ENV['DEBUG']
    end
    
    def calculate_tokens_per_second
      return 0 unless @start_time
      
      duration = Time.now - @start_time
      @tokens_per_second = duration > 0 ? @tokens.size / duration : 0
    end
    
    def elapsed_time
      @start_time ? Time.now - @start_time : 0
    end
  end
end
