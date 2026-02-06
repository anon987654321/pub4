# frozen_string_literal: true

require 'yaml'
require 'json'

module MASTER
  module Autonomy
    # Advanced metrics tracking and reporting
    class MetricsTracker
      METRICS_FILE = File.join(Paths.var, 'autonomy_metrics.yml')
      METRICS_LOG = File.join(Paths.var, 'metrics.jsonl')
      
      def initialize
        @metrics = load_metrics
        @session_start = Time.now
      end
      
      # Track autonomy event
      def track_event(category, action, metadata = {})
        event = {
          category: category,
          action: action,
          metadata: metadata,
          timestamp: Time.now.to_i
        }
        
        # Append to JSONL log
        File.open(METRICS_LOG, 'a') do |f|
          f.puts(event.to_json)
        end
        
        # Update aggregated metrics
        update_aggregates(category, action)
      end
      
      # Track performance metric
      def track_performance(operation, duration:, success:, metadata: {})
        track_event(:performance, operation, {
          duration: duration,
          success: success,
          **metadata
        })
        
        @metrics[:performance] ||= {}
        @metrics[:performance][operation] ||= {
          count: 0,
          total_duration: 0.0,
          successes: 0,
          failures: 0
        }
        
        stats = @metrics[:performance][operation]
        stats[:count] += 1
        stats[:total_duration] += duration
        stats[:successes] += 1 if success
        stats[:failures] += 1 unless success
        
        save_metrics
      end
      
      # Track learning event
      def track_learning(type, metadata = {})
        track_event(:learning, type, metadata)
        
        @metrics[:learning] ||= {}
        @metrics[:learning][type] ||= 0
        @metrics[:learning][type] += 1
        
        save_metrics
      end
      
      # Track autonomy action
      def track_autonomy(action_type, metadata = {})
        track_event(:autonomy, action_type, metadata)
        
        @metrics[:autonomy] ||= {}
        @metrics[:autonomy][action_type] ||= 0
        @metrics[:autonomy][action_type] += 1
        
        save_metrics
      end
      
      # Generate comprehensive report
      def generate_report
        {
          session: session_summary,
          performance: performance_summary,
          learning: learning_summary,
          autonomy: autonomy_summary,
          trends: trend_analysis,
          recommendations: generate_recommendations
        }
      end
      
      # Get real-time dashboard data
      def dashboard
        {
          uptime: uptime,
          events_per_minute: events_per_minute,
          success_rate: overall_success_rate,
          learning_rate: learning_rate,
          autonomy_score: autonomy_score,
          health: health_score
        }
      end
      
      # Export metrics to file
      def export_report(format: :markdown)
        report = generate_report
        
        case format
        when :markdown
          export_markdown(report)
        when :json
          export_json(report)
        when :yaml
          export_yaml(report)
        end
      end
      
      private
      
      def load_metrics
        return default_metrics unless File.exist?(METRICS_FILE)
        
        YAML.load_file(METRICS_FILE, symbolize_names: true) rescue default_metrics
      end
      
      def default_metrics
        {
          performance: {},
          learning: {},
          autonomy: {},
          sessions: 0,
          first_seen: Time.now.to_i
        }
      end
      
      def save_metrics
        FileUtils.mkdir_p(File.dirname(METRICS_FILE))
        File.write(METRICS_FILE, @metrics.to_yaml)
      end
      
      def update_aggregates(category, action)
        key = "#{category}_#{action}".to_sym
        @metrics[key] ||= 0
        @metrics[key] += 1
      end
      
      def session_summary
        {
          duration: uptime,
          start_time: @session_start,
          total_events: count_session_events,
          session_number: @metrics[:sessions] + 1
        }
      end
      
      def performance_summary
        return {} unless @metrics[:performance]
        
        summary = {}
        @metrics[:performance].each do |operation, stats|
          summary[operation] = {
            count: stats[:count],
            avg_duration: (stats[:total_duration] / stats[:count]).round(2),
            success_rate: (stats[:successes].to_f / stats[:count] * 100).round(1),
            total_duration: stats[:total_duration].round(2)
          }
        end
        
        summary
      end
      
      def learning_summary
        return {} unless @metrics[:learning]
        
        {
          total_learning_events: @metrics[:learning].values.sum,
          by_type: @metrics[:learning],
          learning_velocity: learning_velocity
        }
      end
      
      def autonomy_summary
        return {} unless @metrics[:autonomy]
        
        {
          total_autonomous_actions: @metrics[:autonomy].values.sum,
          by_type: @metrics[:autonomy],
          autonomy_level: calculate_autonomy_level
        }
      end
      
      def trend_analysis
        events = load_recent_events(limit: 100)
        
        {
          event_frequency: analyze_frequency(events),
          peak_times: detect_peak_times(events),
          improvement_rate: calculate_improvement_rate(events)
        }
      end
      
      def generate_recommendations
        recommendations = []
        
        # Performance recommendations
        slow_operations = find_slow_operations
        if slow_operations.any?
          recommendations << {
            type: :performance,
            priority: :high,
            message: "Optimize slow operations: #{slow_operations.join(', ')}"
          }
        end
        
        # Learning recommendations
        if learning_rate < 0.1
          recommendations << {
            type: :learning,
            priority: :medium,
            message: "Low learning rate detected. Consider enabling more feedback mechanisms."
          }
        end
        
        # Autonomy recommendations
        if autonomy_score < 0.5
          recommendations << {
            type: :autonomy,
            priority: :medium,
            message: "Autonomy score is low. Consider enabling more proactive features."
          }
        end
        
        recommendations
      end
      
      def uptime
        Time.now - @session_start
      end
      
      def events_per_minute
        return 0 if uptime.zero?
        
        (count_session_events.to_f / (uptime / 60.0)).round(2)
      end
      
      def count_session_events
        return 0 unless File.exist?(METRICS_LOG)
        
        File.readlines(METRICS_LOG).count
      end
      
      def overall_success_rate
        return 0.0 unless @metrics[:performance]
        
        total_success = @metrics[:performance].values.sum { |s| s[:successes] }
        total_count = @metrics[:performance].values.sum { |s| s[:count] }
        
        return 0.0 if total_count.zero?
        
        (total_success.to_f / total_count * 100).round(1)
      end
      
      def learning_rate
        return 0.0 unless @metrics[:learning]
        
        total_learning = @metrics[:learning].values.sum
        total_events = count_session_events
        
        return 0.0 if total_events.zero?
        
        (total_learning.to_f / total_events).round(3)
      end
      
      def autonomy_score
        return 0.0 unless @metrics[:autonomy]
        
        # Score based on variety and frequency of autonomous actions
        variety = @metrics[:autonomy].keys.size
        frequency = @metrics[:autonomy].values.sum
        
        # Normalize to 0-1 scale
        [(variety * 0.1 + frequency * 0.01), 1.0].min
      end
      
      def health_score
        # Simple health score based on success rate and uptime
        success = overall_success_rate / 100.0
        uptime_score = [uptime / 3600.0, 1.0].min
        
        (success * 0.7 + uptime_score * 0.3).round(2)
      end
      
      def find_slow_operations
        return [] unless @metrics[:performance]
        
        @metrics[:performance]
          .select { |_, stats| stats[:total_duration] / stats[:count] > 5.0 }
          .keys
      end
      
      def learning_velocity
        # Events per hour
        return 0 unless @metrics[:learning]
        
        total_learning = @metrics[:learning].values.sum
        hours_since_start = (Time.now.to_i - @metrics[:first_seen]) / 3600.0
        
        return 0 if hours_since_start.zero?
        
        (total_learning / hours_since_start).round(2)
      end
      
      def calculate_autonomy_level
        score = autonomy_score
        
        case score
        when 0...0.3 then :low
        when 0.3...0.6 then :medium
        when 0.6...0.8 then :high
        else :very_high
        end
      end
      
      def load_recent_events(limit: 100)
        return [] unless File.exist?(METRICS_LOG)
        
        File.readlines(METRICS_LOG).last(limit).map do |line|
          JSON.parse(line, symbolize_names: true) rescue nil
        end.compact
      end
      
      def analyze_frequency(events)
        return 0 if events.empty?
        
        time_span = events.last[:timestamp] - events.first[:timestamp]
        return 0 if time_span.zero?
        
        (events.size.to_f / time_span * 60).round(2) # events per minute
      end
      
      def detect_peak_times(events)
        return [] if events.empty?
        
        by_hour = events.group_by { |e| Time.at(e[:timestamp]).hour }
        by_hour.sort_by { |_, evts| -evts.size }.first(3).map(&:first)
      end
      
      def calculate_improvement_rate(events)
        return 0.0 if events.empty?
        
        # Compare first half to second half success rates
        mid = events.size / 2
        first_half = events[0...mid]
        second_half = events[mid..]
        
        first_success = success_rate_of(first_half)
        second_success = success_rate_of(second_half)
        
        second_success - first_success
      end
      
      def success_rate_of(events)
        performance_events = events.select { |e| e[:category] == :performance }
        return 0.0 if performance_events.empty?
        
        successes = performance_events.count { |e| e[:metadata][:success] }
        (successes.to_f / performance_events.size * 100).round(1)
      end
      
      def export_markdown(report)
        output = []
        output << "# MASTER Autonomy Metrics Report"
        output << ""
        output << "Generated: #{Time.now}"
        output << ""
        
        output << "## Session Summary"
        output << "- Duration: #{report[:session][:duration].round(0)} seconds"
        output << "- Total Events: #{report[:session][:total_events]}"
        output << "- Session ##{report[:session][:session_number]}"
        output << ""
        
        output << "## Performance"
        report[:performance].each do |op, stats|
          output << "### #{op}"
          output << "- Count: #{stats[:count]}"
          output << "- Avg Duration: #{stats[:avg_duration]}s"
          output << "- Success Rate: #{stats[:success_rate]}%"
          output << ""
        end
        
        output << "## Learning"
        output << "- Total Learning Events: #{report[:learning][:total_learning_events]}"
        output << "- Learning Velocity: #{report[:learning][:learning_velocity]} events/hour"
        output << ""
        
        output << "## Autonomy"
        output << "- Autonomous Actions: #{report[:autonomy][:total_autonomous_actions]}"
        output << "- Autonomy Level: #{report[:autonomy][:autonomy_level]}"
        output << ""
        
        if report[:recommendations].any?
          output << "## Recommendations"
          report[:recommendations].each do |rec|
            output << "- [#{rec[:priority].upcase}] #{rec[:message]}"
          end
          output << ""
        end
        
        output.join("\n")
      end
      
      def export_json(report)
        JSON.pretty_generate(report)
      end
      
      def export_yaml(report)
        report.to_yaml
      end
    end
  end
end
