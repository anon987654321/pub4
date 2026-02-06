# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module MASTER
  module Autonomy
    # Adaptive UI/UX that learns user preferences
    class AdaptiveUI
      PREFERENCES_FILE = File.join(Paths.var, 'ui_preferences.yml')
      
      def initialize
        @preferences = load_preferences
        @interaction_log = []
      end
      
      # Determine optimal verbosity based on user patterns
      def optimal_verbosity(context = {})
        # Start with preference
        base = @preferences[:verbosity] || :medium
        
        # Adjust based on context
        case context[:command_type]
        when :debug
          :high
        when :quick_query
          :low
        when :complex_task
          :high
        else
          base
        end
      end
      
      # Record user interaction for learning
      def record_interaction(type:, duration:, user_feedback: nil)
        @interaction_log << {
          type: type,
          duration: duration,
          feedback: user_feedback,
          timestamp: Time.now.to_i
        }
        
        # Keep last 200 interactions
        @interaction_log = @interaction_log.last(200)
        
        # Update preferences periodically
        update_preferences if @interaction_log.size % 10 == 0
      end
      
      # Get adaptive formatting for output
      def format_output(content, type:)
        style = @preferences[:output_style] || :balanced
        
        case style
        when :minimal
          format_minimal(content, type)
        when :verbose
          format_verbose(content, type)
        else
          format_balanced(content, type)
        end
      end
      
      # Determine if user prefers colors
      def use_colors?
        @preferences[:colors] != false
      end
      
      # Get preferred response timing
      def response_timing
        @preferences[:timing] || :normal
      end
      
      # Adjust timing based on user patience
      def adaptive_delay(base_delay)
        timing = response_timing
        
        case timing
        when :immediate
          base_delay * 0.5
        when :patient
          base_delay * 1.5
        else
          base_delay
        end
      end
      
      # Smart truncation based on preferences
      def truncate_intelligently(text, max_length)
        return text if text.length <= max_length
        
        style = @preferences[:truncation] || :smart
        
        case style
        when :hard
          text[0...max_length] + "..."
        when :smart
          # Try to truncate at sentence boundary
          truncated = text[0...max_length]
          last_sentence = truncated.rindex(/[.!?]\s+/)
          
          if last_sentence && last_sentence > max_length * 0.7
            text[0..last_sentence]
          else
            truncated + "..."
          end
        when :preserve_end
          "...[truncated]..." + text[-max_length/4..]
        end
      end
      
      # Determine if user wants suggestions
      def show_suggestions?
        @preferences[:suggestions] != false
      end
      
      # Get emoji preference
      def emoji_style
        @preferences[:emoji] || :moderate
      end
      
      # Format with adaptive emoji
      def with_emoji(text, type)
        return text if emoji_style == :none
        
        emoji = case type
        when :success then "✓"
        when :error then "✗"
        when :warning then "!"
        when :info then "·"
        when :progress then "→"
        else ""
        end
        
        emoji.empty? ? text : "#{emoji} #{text}"
      end
      
      private
      
      def load_preferences
        return default_preferences unless File.exist?(PREFERENCES_FILE)
        
        saved = YAML.load_file(PREFERENCES_FILE, symbolize_names: true) rescue {}
        default_preferences.merge(saved)
      end
      
      def default_preferences
        {
          verbosity: :medium,
          output_style: :balanced,
          colors: true,
          timing: :normal,
          truncation: :smart,
          suggestions: true,
          emoji: :moderate,
          auto_confirm: false,
          compact_tables: false
        }
      end
      
      def save_preferences
        FileUtils.mkdir_p(File.dirname(PREFERENCES_FILE))
        File.write(PREFERENCES_FILE, @preferences.to_yaml)
      end
      
      def update_preferences
        # Analyze interaction patterns
        recent = @interaction_log.last(50)
        
        # Adjust verbosity based on interaction duration
        avg_duration = recent.sum { |i| i[:duration] }.to_f / recent.size
        if avg_duration < 5
          @preferences[:verbosity] = :low
        elsif avg_duration > 30
          @preferences[:verbosity] = :high
        end
        
        # Learn from explicit feedback
        positive_feedback = recent.count { |i| i[:feedback] == :positive }
        negative_feedback = recent.count { |i| i[:feedback] == :negative }
        
        if negative_feedback > positive_feedback * 2
          # User seems frustrated, adjust settings
          @preferences[:suggestions] = false
          @preferences[:verbosity] = :low
        end
        
        save_preferences
      end
      
      def format_minimal(content, type)
        case type
        when :success
          "✓"
        when :error
          "✗ #{content[0..50]}"
        when :info
          content[0..100]
        else
          content
        end
      end
      
      def format_verbose(content, type)
        timestamp = Time.now.strftime("%H:%M:%S")
        
        header = case type
        when :success then "━━━ SUCCESS [#{timestamp}] ━━━"
        when :error then "━━━ ERROR [#{timestamp}] ━━━"
        when :info then "━━━ INFO [#{timestamp}] ━━━"
        else "━━━ #{type.to_s.upcase} [#{timestamp}] ━━━"
        end
        
        "#{header}\n#{content}\n#{'━' * 40}"
      end
      
      def format_balanced(content, type)
        prefix = case type
        when :success then "✓"
        when :error then "✗"
        when :warning then "!"
        when :info then "·"
        else "→"
        end
        
        "#{prefix} #{content}"
      end
    end
    
    # Learning system that improves from user feedback
    class FeedbackLearning
      FEEDBACK_FILE = File.join(Paths.var, 'user_feedback.yml')
      
      def initialize
        @feedback_data = load_feedback
        @satisfaction_scores = []
      end
      
      # Record user satisfaction
      def record_satisfaction(score, context: {})
        @satisfaction_scores << {
          score: score,
          context: context,
          timestamp: Time.now.to_i
        }
        
        # Keep last 100 scores
        @satisfaction_scores = @satisfaction_scores.last(100)
        save_feedback
      end
      
      # Record correction from user
      def record_correction(incorrect:, correct:, context:)
        @feedback_data[:corrections] ||= []
        @feedback_data[:corrections] << {
          incorrect: incorrect[0..200],
          correct: correct[0..200],
          context: context,
          timestamp: Time.now.to_i
        }
        
        # Keep last 50 corrections
        @feedback_data[:corrections] = @feedback_data[:corrections].last(50)
        save_feedback
      end
      
      # Get average satisfaction
      def average_satisfaction
        return 0.0 if @satisfaction_scores.empty?
        
        @satisfaction_scores.sum { |s| s[:score] }.to_f / @satisfaction_scores.size
      end
      
      # Get satisfaction trend
      def satisfaction_trend
        return :unknown if @satisfaction_scores.size < 10
        
        recent = @satisfaction_scores.last(10).sum { |s| s[:score] } / 10.0
        older = @satisfaction_scores.first(10).sum { |s| s[:score] } / 10.0
        
        diff = recent - older
        
        if diff > 0.5
          :improving
        elsif diff < -0.5
          :declining
        else
          :stable
        end
      end
      
      # Get insights from feedback
      def feedback_insights
        {
          total_feedback: @satisfaction_scores.size,
          average_score: average_satisfaction.round(2),
          trend: satisfaction_trend,
          correction_count: @feedback_data[:corrections]&.size || 0,
          recent_corrections: recent_correction_patterns
        }
      end
      
      private
      
      def load_feedback
        return { corrections: [], scores: [] } unless File.exist?(FEEDBACK_FILE)
        
        YAML.load_file(FEEDBACK_FILE, symbolize_names: true) rescue { corrections: [], scores: [] }
      end
      
      def save_feedback
        @feedback_data[:scores] = @satisfaction_scores
        
        FileUtils.mkdir_p(File.dirname(FEEDBACK_FILE))
        File.write(FEEDBACK_FILE, @feedback_data.to_yaml)
      end
      
      def recent_correction_patterns
        return [] unless @feedback_data[:corrections]
        
        @feedback_data[:corrections].last(10).map do |c|
          {
            issue: detect_issue_type(c[:incorrect], c[:correct]),
            frequency: 1
          }
        end
      end
      
      def detect_issue_type(incorrect, correct)
        return :verbosity if incorrect.length > correct.length * 1.5
        return :accuracy if incorrect.downcase != correct.downcase
        return :format if incorrect.strip != correct.strip
        
        :other
      end
    end
  end
end
