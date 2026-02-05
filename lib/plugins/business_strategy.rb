# frozen_string_literal: true

require 'yaml'

module MASTER
  module Plugins
    class BusinessStrategy
      @config = nil
      @config_mtime = nil
      @enabled = false

      class << self
        def config
          load_config unless @config
          @config
        end

        def load_config
          path = config_path
          return @config = default_config unless File.exist?(path)

          current_mtime = File.mtime(path)
          if @config && @config_mtime == current_mtime
            return @config
          end

          @config = YAML.load_file(path, symbolize_names: true)
          @config_mtime = current_mtime
          @config
        rescue => e
          warn "Failed to load business strategy config: #{e.message}"
          @config = default_config
        end

        def config_path
          File.join(__dir__, '..', 'config', 'plugins', 'business_strategy.yml')
        end

        def default_config
          {
            enabled: false,
            planning: { horizon: 'quarterly', frameworks: ['okr', 'smart'], review_cycle: 'monthly' },
            metrics: { kpis: [], categories: ['revenue', 'users', 'engagement', 'retention'], tracking: 'daily' },
            analytics: { tools: ['custom'], dashboards: true, real_time: true, reporting: 'weekly' },
            growth: { channels: ['organic', 'paid', 'referral'], experiments: true, optimization: true },
            market: { research: true, competitive_analysis: true, customer_feedback: true },
            financial: { budgeting: true, forecasting: true, roi_tracking: true }
          }
        end

        def enabled?
          @enabled
        end

        def enable
          @enabled = true
          load_config
          validate
        end

        def disable
          @enabled = false
        end

        def configure(options = {})
          load_config
          @config = @config.merge(options)
          validate
        end

        def apply(context = {})
          return { success: false, error: 'Plugin not enabled' } unless enabled?

          results = []
          
          # Apply planning framework
          if config[:planning]
            results << apply_planning(context)
          end

          # Apply metrics tracking
          if config[:metrics]
            results << apply_metrics(context)
          end

          # Apply analytics
          if config[:analytics]
            results << apply_analytics(context)
          end

          # Apply growth strategies
          if config[:growth]
            results << apply_growth(context)
          end

          # Apply market analysis
          if config[:market]
            results << apply_market(context)
          end

          # Apply financial tracking
          if config[:financial]
            results << apply_financial(context)
          end

          {
            success: true,
            applied: results.compact,
            timestamp: Time.now
          }
        rescue => e
          { success: false, error: e.message }
        end

        def validate
          errors = []

          # Validate planning config
          if config[:planning]
            errors << 'Planning config must be a hash' unless config[:planning].is_a?(Hash)
            if config[:planning][:horizon]
              valid_horizons = ['weekly', 'monthly', 'quarterly', 'yearly']
              horizon = config[:planning][:horizon].to_s
              errors << "Invalid planning horizon: #{horizon}" unless valid_horizons.include?(horizon)
            end
            if config[:planning][:frameworks]
              errors << 'Frameworks must be an array' unless config[:planning][:frameworks].is_a?(Array)
            end
          end

          # Validate metrics config
          if config[:metrics]
            errors << 'Metrics config must be a hash' unless config[:metrics].is_a?(Hash)
            if config[:metrics][:kpis]
              errors << 'KPIs must be an array' unless config[:metrics][:kpis].is_a?(Array)
            end
            if config[:metrics][:categories]
              errors << 'Categories must be an array' unless config[:metrics][:categories].is_a?(Array)
            end
          end

          # Validate analytics config
          if config[:analytics]
            errors << 'Analytics config must be a hash' unless config[:analytics].is_a?(Hash)
            if config[:analytics][:tools]
              errors << 'Tools must be an array' unless config[:analytics][:tools].is_a?(Array)
            end
          end

          # Validate growth config
          if config[:growth]
            errors << 'Growth config must be a hash' unless config[:growth].is_a?(Hash)
            if config[:growth][:channels]
              errors << 'Channels must be an array' unless config[:growth][:channels].is_a?(Array)
            end
          end

          # Validate market config
          if config[:market]
            errors << 'Market config must be a hash' unless config[:market].is_a?(Hash)
          end

          # Validate financial config
          if config[:financial]
            errors << 'Financial config must be a hash' unless config[:financial].is_a?(Hash)
          end

          if errors.any?
            { valid: false, errors: errors }
          else
            { valid: true }
          end
        end

        def planning_config
          config[:planning] || {}
        end

        def create_okr(objective, key_results = [])
          {
            type: 'okr',
            objective: objective,
            key_results: key_results,
            horizon: planning_config[:horizon],
            status: 'draft',
            created_at: Time.now
          }
        end

        def create_smart_goal(description, criteria = {})
          {
            type: 'smart',
            description: description,
            specific: criteria[:specific],
            measurable: criteria[:measurable],
            achievable: criteria[:achievable],
            relevant: criteria[:relevant],
            time_bound: criteria[:time_bound],
            status: 'active',
            created_at: Time.now
          }
        end

        def metrics_config
          config[:metrics] || {}
        end

        def define_kpi(name, target, unit = nil)
          {
            name: name,
            target: target,
            unit: unit,
            current: 0,
            tracking: metrics_config[:tracking],
            category: nil,
            created_at: Time.now
          }
        end

        def track_metric(name, value, timestamp = Time.now)
          {
            metric: name,
            value: value,
            timestamp: timestamp,
            recorded_at: Time.now
          }
        end

        def calculate_metric_progress(current, target)
          return 0 if target.nil? || target.zero?
          
          progress = (current.to_f / target.to_f) * 100
          {
            current: current,
            target: target,
            progress: progress.round(2),
            status: progress >= 100 ? 'achieved' : 'in_progress'
          }
        end

        def analytics_config
          config[:analytics] || {}
        end

        def create_dashboard(name, widgets = [])
          {
            name: name,
            widgets: widgets,
            real_time: analytics_config[:real_time],
            refresh_interval: analytics_config[:real_time] ? 60 : 300,
            created_at: Time.now
          }
        end

        def generate_report(type, data, period)
          {
            type: type,
            period: period,
            data: data,
            summary: summarize_data(data),
            insights: generate_insights(data),
            generated_at: Time.now
          }
        end

        def growth_config
          config[:growth] || {}
        end

        def plan_experiment(name, hypothesis, metrics = [])
          {
            name: name,
            hypothesis: hypothesis,
            metrics: metrics,
            channels: growth_config[:channels],
            status: 'planned',
            created_at: Time.now
          }
        end

        def analyze_channel_performance(channel, data)
          {
            channel: channel,
            metrics: {
              conversions: data[:conversions] || 0,
              cost: data[:cost] || 0,
              roi: calculate_roi(data[:revenue] || 0, data[:cost] || 0),
              cpa: calculate_cpa(data[:cost] || 0, data[:conversions] || 0)
            },
            recommendation: channel_recommendation(channel, data),
            analyzed_at: Time.now
          }
        end

        def market_config
          config[:market] || {}
        end

        def conduct_competitive_analysis(competitors = [])
          return nil unless market_config[:competitive_analysis]
          
          {
            competitors: competitors,
            dimensions: ['pricing', 'features', 'market_share', 'positioning'],
            methodology: 'swot',
            findings: [],
            conducted_at: Time.now
          }
        end

        def collect_customer_feedback(source, feedback)
          return nil unless market_config[:customer_feedback]
          
          {
            source: source,
            feedback: feedback,
            sentiment: analyze_sentiment(feedback),
            tags: extract_tags(feedback),
            collected_at: Time.now
          }
        end

        def financial_config
          config[:financial] || {}
        end

        def create_budget(period, allocations = {})
          return nil unless financial_config[:budgeting]
          
          {
            period: period,
            allocations: allocations,
            total: allocations.values.sum,
            status: 'active',
            created_at: Time.now
          }
        end

        def forecast_revenue(current, growth_rate, periods)
          return nil unless financial_config[:forecasting]
          
          forecasts = []
          value = current
          
          periods.times do |i|
            value *= (1 + growth_rate)
            forecasts << {
              period: i + 1,
              value: value.round(2)
            }
          end
          
          {
            starting_value: current,
            growth_rate: growth_rate,
            periods: periods,
            forecasts: forecasts,
            total_growth: ((value - current) / current * 100).round(2)
          }
        end

        def calculate_roi(revenue, cost)
          return 0 if cost.zero?
          ((revenue - cost) / cost * 100).round(2)
        end

        private

        def apply_planning(context)
          {
            type: 'planning',
            data: planning_config,
            frameworks: planning_config[:frameworks],
            applied_to: context[:target] || 'organization'
          }
        end

        def apply_metrics(context)
          {
            type: 'metrics',
            data: metrics_config,
            kpis: metrics_config[:kpis],
            applied_to: context[:target] || 'organization'
          }
        end

        def apply_analytics(context)
          {
            type: 'analytics',
            data: analytics_config,
            tools: analytics_config[:tools],
            applied_to: context[:target] || 'organization'
          }
        end

        def apply_growth(context)
          {
            type: 'growth',
            data: growth_config,
            channels: growth_config[:channels],
            applied_to: context[:target] || 'marketing'
          }
        end

        def apply_market(context)
          {
            type: 'market',
            data: market_config,
            applied_to: context[:target] || 'organization'
          }
        end

        def apply_financial(context)
          {
            type: 'financial',
            data: financial_config,
            applied_to: context[:target] || 'organization'
          }
        end

        def summarize_data(data)
          return {} unless data.is_a?(Hash) || data.is_a?(Array)
          
          if data.is_a?(Array)
            { count: data.length, items: data.length }
          else
            { keys: data.keys.length }
          end
        end

        def generate_insights(data)
          []
        end

        def calculate_cpa(cost, conversions)
          return 0 if conversions.zero?
          (cost.to_f / conversions).round(2)
        end

        def channel_recommendation(channel, data)
          roi = calculate_roi(data[:revenue] || 0, data[:cost] || 0)
          
          if roi > 200
            'Scale investment - strong performance'
          elsif roi > 100
            'Maintain current investment'
          elsif roi > 0
            'Optimize or reduce investment'
          else
            'Consider pausing - negative ROI'
          end
        end

        def analyze_sentiment(text)
          'neutral'
        end

        def extract_tags(text)
          []
        end
      end
    end
  end
end
