#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module MASTER
  # LLM API client for OpenRouter, DeepSeek, etc.
  class LLMClient
    attr_reader :api_key, :base_url, :model

    def initialize(api_key: ENV['OPENROUTER_API_KEY'], base_url: 'https://openrouter.ai/api/v1', model: 'deepseek/deepseek-chat')
      @api_key = api_key
      @base_url = base_url
      @model = model
    end

    # Send chat completion request
    # Returns hash with response, tokens, cost
    def chat(messages, model: @model, temperature: 0.7, max_tokens: 2000, stream: false)
      uri = URI("#{@base_url}/chat/completions")
      
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request['HTTP-Referer'] = 'https://github.com/anon987654321/pub4'
      request['X-Title'] = 'MASTER'
      
      body = {
        model: model,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: stream
      }
      
      request.body = body.to_json
      
      if stream
        stream_request(uri, request)
      else
        execute_request(uri, request)
      end
    end

    # Execute non-streaming request
    def execute_request(uri, request)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      
      if response.code.to_i >= 400
        return {
          error: "HTTP #{response.code}",
          message: response.body,
          success: false
        }
      end
      
      data = JSON.parse(response.body, symbolize_names: true)
      
      {
        response: data.dig(:choices, 0, :message, :content) || '',
        model: data[:model],
        tokens_in: data.dig(:usage, :prompt_tokens) || 0,
        tokens_out: data.dig(:usage, :completion_tokens) || 0,
        cost: calculate_cost(data),
        success: true
      }
    rescue JSON::ParserError => e
      { error: "JSON parse error: #{e.message}", success: false }
    rescue StandardError => e
      { error: e.message, success: false }
    end

    # Stream response with Server-Sent Events
    def stream_request(uri, request)
      chunks = []
      
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request) do |response|
          buffer = ''
          
          response.read_body do |chunk|
            buffer += chunk
            
            # Process complete lines
            while (line_end = buffer.index("\n"))
              line = buffer[0...line_end]
              buffer = buffer[(line_end + 1)..-1]
              
              next if line.strip.empty? || line.strip == 'data: [DONE]'
              
              if line.start_with?('data: ')
                json_str = line[6..-1]
                begin
                  data = JSON.parse(json_str, symbolize_names: true)
                  content = data.dig(:choices, 0, :delta, :content)
                  
                  if content
                    chunks << content
                    yield content if block_given?
                  end
                rescue JSON::ParserError
                  # Skip malformed JSON
                end
              end
            end
          end
        end
      end
      
      {
        response: chunks.join,
        success: true,
        streamed: true
      }
    rescue StandardError => e
      { error: e.message, success: false }
    end

    # Calculate cost based on usage
    # This is a simplified calculation - real costs vary by model
    def calculate_cost(data)
      tokens_in = data.dig(:usage, :prompt_tokens) || 0
      tokens_out = data.dig(:usage, :completion_tokens) || 0
      
      # Rough estimates per 1M tokens
      # DeepSeek: $0.27 input, $1.1 output
      # GPT-4: $10 input, $30 output
      model_name = data[:model] || @model
      
      if model_name.include?('deepseek')
        (tokens_in * 0.27 + tokens_out * 1.1) / 1_000_000.0
      elsif model_name.include?('gpt-4')
        (tokens_in * 10.0 + tokens_out * 30.0) / 1_000_000.0
      elsif model_name.include?('claude')
        (tokens_in * 3.0 + tokens_out * 15.0) / 1_000_000.0
      else
        # Default estimate
        (tokens_in * 1.0 + tokens_out * 3.0) / 1_000_000.0
      end
    end

    # Get available models
    def models
      uri = URI("#{@base_url}/models")
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end
      
      JSON.parse(response.body, symbolize_names: true)
    rescue StandardError => e
      { error: e.message }
    end
  end
end
