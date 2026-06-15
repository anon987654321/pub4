# frozen_string_literal: true

require 'openai'
require 'anthropic'
require 'ollama-ai'
require 'faraday'
require 'json'

# Multi-LLM Manager with fallback chains and circuit breaker protection
class MultiLLMManager
  PROVIDERS = {
    xai: 'X.AI/Grok',
    anthropic: 'Anthropic/Claude',
    openai: 'OpenAI/o3-mini',
    ollama: 'Ollama/DeepSeek-R1:1.5b'
  }.freeze

  attr_reader :current_provider, :fallback_chain, :circuit_breakers

  def initialize(config = {})
    @config = config
    @providers = {}
    @fallback_chain = %i[xai anthropic openai ollama]
    @circuit_breakers = {}
    @current_provider = @fallback_chain.first
    @request_history = []

    initialize_providers
  end

  # Route query with fallback support
  def route_query(query, preferred_provider: nil, fallback: true, max_tokens: 1000)
    provider = preferred_provider || @current_provider
    providers_to_try = fallback ? @fallback_chain : [provider]

    providers_to_try.each do |provider_name|
      next if circuit_breaker_open?(provider_name)

      begin
        start_time = Time.now
        response = query_provider(provider_name, query, max_tokens)
        response_time = Time.now - start_time

        record_success(provider_name, response_time)
        @current_provider = provider_name

        return {
          response: response,
          provider: provider_name,
          fallback_used: provider_name != (preferred_provider || @fallback_chain.first),
          response_time: response_time,
          timestamp: Time.now
        }
      rescue StandardError => e
        record_failure(provider_name, e)
        puts "❌ #{PROVIDERS[provider_name]} failed: #{e.message}"
        next if fallback

        raise
      end
    end

    raise "All LLM providers failed for query: #{query.truncate(100)}"
  end

  # Get provider status
  def provider_status
    status = {}

    PROVIDERS.each do |provider_name, display_name|
      breaker = @circuit_breakers[provider_name] || {}
      status[provider_name] = {
        name: display_name,
        available: !circuit_breaker_open?(provider_name),
        failure_count: breaker[:failure_count] || 0,
        last_success: breaker[:last_success],
        last_failure: breaker[:last_failure],
        cooldown_remaining: calculate_cooldown_remaining(provider_name)
      }
    end

    status
  end

  # Switch primary provider
  def switch_provider(provider_name)
    unless PROVIDERS.key?(provider_name)
      raise "Unknown provider: #{provider_name}. Available: #{PROVIDERS.keys.join(', ')}"
    end

    if circuit_breaker_open?(provider_name)
      cooldown = calculate_cooldown_remaining(provider_name)
      raise "Provider #{provider_name} is in cooldown for #{cooldown} more seconds"
    end

    @current_provider = provider_name
    puts "🔄 Switched to #{PROVIDERS[provider_name]}"
  end

  # Reset circuit breaker for provider
  def reset_circuit_breaker(provider_name)
    @circuit_breakers[provider_name] = {
      failure_count: 0,
      last_success: Time.now
    }
    puts "🔧 Reset circuit breaker for #{PROVIDERS[provider_name]}"
  end

  # Get request history and stats
  def request_stats
    total_requests = @request_history.size
    successful_requests = @request_history.count { |r| r[:success] }

    {
      total_requests: total_requests,
      successful_requests: successful_requests,
      success_rate: total_requests > 0 ? (successful_requests.to_f / total_requests * 100).round(2) : 0,
      avg_response_time: calculate_average_response_time,
      provider_usage: calculate_provider_usage
    }
  end

  private

  # Initialize LLM provider clients
  def initialize_providers
    @providers = {
      xai: XAIProvider.new(@config),
      anthropic: AnthropicProvider.new(@config),
      openai: OpenAIProvider.new(@config),
      ollama: OllamaProvider.new(@config)
    }
  end

  # Query specific provider
  def query_provider(provider_name, query, max_tokens)
    provider = @providers[provider_name]
    raise "Provider #{provider_name} not initialized" unless provider

    provider.query(query, max_tokens: max_tokens)
  end

  # Check if circuit breaker is open
  def circuit_breaker_open?(provider_name)
    breaker = @circuit_breakers[provider_name]
    return false unless breaker

    if breaker[:failure_count] >= 5 &&
       (Time.now - breaker[:last_failure]) < 300 # 5 minute cooldown
      return true
    end

    false
  end

  # Record successful request
  def record_success(provider_name, response_time)
    @circuit_breakers[provider_name] = {
      failure_count: 0,
      last_success: Time.now
    }

    @request_history << {
      provider: provider_name,
      success: true,
      response_time: response_time,
      timestamp: Time.now
    }

    cleanup_request_history
  end

  # Record failed request
  def record_failure(provider_name, error)
    breaker = @circuit_breakers[provider_name] ||= { failure_count: 0 }
    breaker[:failure_count] += 1
    breaker[:last_failure] = Time.now
    breaker[:last_error] = error.message

    @request_history << {
      provider: provider_name,
      success: false,
      error: error.message,
      timestamp: Time.now
    }

    cleanup_request_history
    puts "🔴 LLM_FAILURE: #{PROVIDERS[provider_name]} - #{error.message}"
  end

  # Calculate remaining cooldown time
  def calculate_cooldown_remaining(provider_name)
    breaker = @circuit_breakers[provider_name]
    return 0 unless breaker && breaker[:last_failure]

    elapsed = Time.now - breaker[:last_failure]
    remaining = 300 - elapsed # 5 minute cooldown
    [remaining, 0].max.round
  end

  # Calculate average response time
  def calculate_average_response_time
    successful_requests = @request_history.select { |r| r[:success] && r[:response_time] }
    return 0 if successful_requests.empty?

    total_time = successful_requests.sum { |r| r[:response_time] }
    (total_time / successful_requests.size).round(3)
  end

  # Calculate provider usage statistics
  def calculate_provider_usage
    usage = {}
    PROVIDERS.keys.each { |provider| usage[provider] = 0 }

    @request_history.each do |request|
      usage[request[:provider]] += 1 if usage.key?(request[:provider])
    end

    usage
  end

  # Keep request history manageable
  def cleanup_request_history
    @request_history = @request_history.last(100) if @request_history.size > 100
  end
end

# X.AI/Grok Provider
class XAIProvider
  def initialize(config)
    @api_key = config['xai_api_key'] || ENV.fetch('XAI_API_KEY', nil)
    @base_url = 'https://api.x.ai/v1'
    @client = setup_client
  end

  def query(prompt, max_tokens: 1000)
    raise 'X.AI API key not configured' unless @api_key

    response = @client.post('/chat/completions') do |req|
      req.headers['Authorization'] = "Bearer #{@api_key}"
      req.headers['Content-Type'] = 'application/json'
      req.body = {
        model: 'grok-beta',
        messages: [{ role: 'user', content: prompt }],
        max_tokens: max_tokens,
        temperature: 0.7
      }.to_json
    end

    raise "X.AI API error: #{response.status} - #{response.body}" unless response.success?

    result = JSON.parse(response.body)
    result.dig('choices', 0, 'message', 'content')
  end

  private

  def setup_client
    Faraday.new(url: @base_url) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end
end

# Anthropic/Claude Provider
class AnthropicProvider
  def initialize(config)
    @api_key = config['anthropic_api_key'] || ENV.fetch('ANTHROPIC_API_KEY', nil)
    @client = @api_key ? Anthropic::Client.new(access_token: @api_key) : nil
  end

  def query(prompt, max_tokens: 1000)
    raise 'Anthropic API key not configured' unless @client

    response = @client.messages(
      model: 'claude-3-sonnet-20240229',
      max_tokens: max_tokens,
      messages: [{ role: 'user', content: prompt }]
    )

    response.dig('content', 0, 'text')
  end
end

# OpenAI Provider
class OpenAIProvider
  def initialize(config)
    @api_key = config['openai_api_key'] || ENV.fetch('OPENAI_API_KEY', nil)
    @client = @api_key ? OpenAI::Client.new(access_token: @api_key) : nil
  end

  def query(prompt, max_tokens: 1000)
    raise 'OpenAI API key not configured' unless @client

    response = @client.chat(
      parameters: {
        model: 'gpt-3.5-turbo', # Will upgrade to o3-mini when available
        messages: [{ role: 'user', content: prompt }],
        max_tokens: max_tokens,
        temperature: 0.7
      }
    )

    response.dig('choices', 0, 'message', 'content')
  end
end

# Ollama Provider (Local)
class OllamaProvider
  def initialize(config)
    @base_url = config['ollama_url'] || 'http://localhost:11434'
    @model = config['ollama_model'] || 'deepseek-r1:1.5b'
    @client = setup_client
  end

  def query(prompt, max_tokens: 1000)
    response = @client.post('/api/generate') do |req|
      req.headers['Content-Type'] = 'application/json'
      req.body = {
        model: @model,
        prompt: prompt,
        options: {
          num_predict: max_tokens,
          temperature: 0.7
        },
        stream: false
      }.to_json
    end

    raise "Ollama error: #{response.status} - #{response.body}" unless response.success?

    result = JSON.parse(response.body)
    result['response']
  rescue Faraday::ConnectionFailed
    raise "Ollama not available at #{@base_url}. Is Ollama running?"
  end

  private

  def setup_client
    Faraday.new(url: @base_url) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end
end
