# frozen_string_literal: true

require 'json'
require 'fileutils'

module MASTER
  # Cost and token monitoring for LLM usage
  # Tracks metrics like tokscale and crabwalk
  class Monitor
    CHARS_PER_TOKEN = 4 # simple estimation
    
    # Model pricing (per 1M tokens)
    PRICING = {
      'deepseek/deepseek-chat' => { input: 0.14, output: 0.28 },
      'x-ai/grok-4-fast' => { input: 0.20, output: 0.50 },
      'anthropic/claude-3.5-sonnet' => { input: 3.0, output: 15.0 },
      'anthropic/claude-opus-4' => { input: 15.0, output: 75.0 },
      'mistral/codestral-latest' => { input: 0.30, output: 0.90 }
    }.freeze
    
    attr_reader :entries, :current_session
    
    def initialize(log_path: nil)
      @log_path = log_path || default_log_path
      @entries = []
      @current_session = {
        started_at: Time.now,
        total_tokens: 0,
        total_cost: 0.0,
        task_count: 0
      }
      
      ensure_log_directory
    end
    
    # Track an LLM operation
    # @param task_name [String] Name of the task
    # @param model [String] Model identifier or tier
    # @yield Block to execute and measure
    # @return Result of the block
    def track(task_name, model: 'strong', &block)
      start_time = Time.now
      
      # Execute the block
      result = block.call if block_given?
      
      duration = Time.now - start_time
      
      # Estimate tokens from result if it's a string
      tokens = estimate_tokens(result)
      
      # Create entry
      entry = create_entry(
        task: task_name,
        model: resolve_model(model),
        duration: duration,
        tokens_in: tokens[:input] || 0,
        tokens_out: tokens[:output] || 0
      )
      
      # Log immediately
      log_entry(entry)
      
      result
    end
    
    # Track with explicit token counts
    def track_tokens(task_name, model:, tokens_in:, tokens_out:, duration: 0)
      entry = create_entry(
        task: task_name,
        model: resolve_model(model),
        duration: duration,
        tokens_in: tokens_in,
        tokens_out: tokens_out
      )
      
      log_entry(entry)
    end
    
    # Generate usage report
    # @return [Hash] Summary statistics
    def report
      reload_entries
      
      return empty_report if @entries.empty?
      
      # Calculate totals
      total_tokens_in = @entries.sum { |e| e[:tokens_in] || 0 }
      total_tokens_out = @entries.sum { |e| e[:tokens_out] || 0 }
      total_cost = @entries.sum { |e| e[:cost] || 0 }
      
      # By model breakdown
      by_model = @entries.group_by { |e| e[:model] }
      model_stats = by_model.transform_values do |entries|
        {
          calls: entries.size,
          tokens_in: entries.sum { |e| e[:tokens_in] || 0 },
          tokens_out: entries.sum { |e| e[:tokens_out] || 0 },
          cost: entries.sum { |e| e[:cost] || 0 }
        }
      end
      
      # Recent activity
      recent = @entries.last(10)
      
      {
        summary: {
          total_calls: @entries.size,
          total_tokens: total_tokens_in + total_tokens_out,
          tokens_in: total_tokens_in,
          tokens_out: total_tokens_out,
          total_cost: total_cost.round(4),
          period: {
            from: @entries.first[:timestamp],
            to: @entries.last[:timestamp]
          }
        },
        by_model: model_stats,
        recent_activity: recent,
        efficiency: calculate_efficiency(total_tokens_in, total_tokens_out, total_cost)
      }
    end
    
    # Print formatted report
    def print_report
      data = report
      
      puts "\n" + "=" * 60
      puts "  MASTER Monitoring Report"
      puts "=" * 60
      
      if data[:summary][:total_calls].zero?
        puts "\n  No usage data recorded yet."
        puts
        return
      end
      
      puts "\n📊 Summary:"
      puts "  Total Calls:    #{data[:summary][:total_calls]}"
      puts "  Total Tokens:   #{format_number(data[:summary][:total_tokens])}"
      puts "    Input:        #{format_number(data[:summary][:tokens_in])}"
      puts "    Output:       #{format_number(data[:summary][:tokens_out])}"
      puts "  Total Cost:     $#{data[:summary][:total_cost].round(4)}"
      
      puts "\n🤖 By Model:"
      data[:by_model].each do |model, stats|
        puts "  #{model}:"
        puts "    Calls:  #{stats[:calls]}"
        puts "    Cost:   $#{stats[:cost].round(4)}"
      end
      
      puts "\n⚡ Efficiency:"
      puts "  Cost per 1K tokens: $#{data[:efficiency][:cost_per_1k].round(4)}"
      puts "  Avg tokens/call:    #{data[:efficiency][:avg_tokens_per_call]}"
      
      puts "\n" + "=" * 60
      puts
    end
    
    # Clear all logged data (use with caution)
    def clear_logs
      File.write(@log_path, '')
      @entries = []
    end
    
    private
    
    def default_log_path
      File.join(Paths.root, 'data', 'monitoring', 'usage.jsonl')
    end
    
    def ensure_log_directory
      FileUtils.mkdir_p(File.dirname(@log_path))
    end
    
    def create_entry(task:, model:, duration:, tokens_in:, tokens_out:)
      total_tokens = tokens_in + tokens_out
      cost = calculate_cost(model, tokens_in, tokens_out)
      
      entry = {
        timestamp: Time.now.iso8601,
        task: task,
        model: model,
        duration: duration.round(3),
        tokens_in: tokens_in,
        tokens_out: tokens_out,
        total_tokens: total_tokens,
        cost: cost.round(6)
      }
      
      @entries << entry
      @current_session[:total_tokens] += total_tokens
      @current_session[:total_cost] += cost
      @current_session[:task_count] += 1
      
      entry
    end
    
    def log_entry(entry)
      File.open(@log_path, 'a') do |f|
        f.puts JSON.generate(entry)
      end
    end
    
    def reload_entries
      return unless File.exist?(@log_path)
      
      @entries = File.readlines(@log_path).map do |line|
        JSON.parse(line.strip, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end.compact
    end
    
    def resolve_model(tier_or_model)
      # If it's a tier, resolve to model name
      tiers = {
        'cheap' => 'deepseek/deepseek-chat',
        'fast' => 'x-ai/grok-4-fast',
        'strong' => 'anthropic/claude-3.5-sonnet',
        'frontier' => 'anthropic/claude-opus-4',
        'code' => 'mistral/codestral-latest'
      }
      
      tiers[tier_or_model] || tier_or_model
    end
    
    def calculate_cost(model, tokens_in, tokens_out)
      pricing = PRICING[model]
      return 0.0 unless pricing
      
      # Cost per million tokens
      input_cost = (tokens_in / 1_000_000.0) * pricing[:input]
      output_cost = (tokens_out / 1_000_000.0) * pricing[:output]
      
      input_cost + output_cost
    end
    
    def estimate_tokens(text)
      return { input: 0, output: 0 } unless text.is_a?(String)
      
      # Simple character-based estimation
      tokens = text.length / CHARS_PER_TOKEN
      
      # Assume most is output
      {
        input: (tokens * 0.3).to_i,
        output: (tokens * 0.7).to_i
      }
    end
    
    def calculate_efficiency(tokens_in, tokens_out, total_cost)
      total_tokens = tokens_in + tokens_out
      
      {
        cost_per_1k: total_tokens.zero? ? 0 : (total_cost / total_tokens * 1000),
        avg_tokens_per_call: @entries.empty? ? 0 : total_tokens / @entries.size,
        input_output_ratio: tokens_in.zero? ? 0 : (tokens_out.to_f / tokens_in).round(2)
      }
    end
    
    def empty_report
      {
        summary: {
          total_calls: 0,
          total_tokens: 0,
          tokens_in: 0,
          tokens_out: 0,
          total_cost: 0.0
        },
        by_model: {},
        recent_activity: [],
        efficiency: {
          cost_per_1k: 0,
          avg_tokens_per_call: 0,
          input_output_ratio: 0
        }
      }
    end
    
    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end
end

# CLI execution
if __FILE__ == $0
  require_relative 'master'
  
  monitor = MASTER::Monitor.new
  monitor.print_report
end
