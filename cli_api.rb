#!/usr/bin/env ruby
# frozen_string_literal: true

# CONVERGENCE CLI - API Client Component
# Multi-provider API client with OpenAI-compatible interface

require "json"
require "net/http"
require "uri"

module Convergence
  class APIClient
    PROVIDERS = {
      openrouter: {
        name: "OpenRouter",
        base_url: "https://openrouter.ai/api/v1",
        models: {
          "deepseek-r1" => "deepseek/deepseek-r1",
          "claude-3.5" => "anthropic/claude-3.5-sonnet",
          "gpt-4o" => "openai/gpt-4o",
          "gemini-pro" => "google/gemini-pro"
        },
        default_model: "deepseek/deepseek-r1",
        headers: ->(key) {
          {
            "Authorization" => "Bearer #{key}",
            "HTTP-Referer" => "https://github.com/anon987654321/pub4",
            "X-Title" => "Convergence CLI",
            "Content-Type" => "application/json"
          }
        }
      },
      openai: {
        name: "OpenAI",
        base_url: "https://api.openai.com/v1",
        models: {
          "gpt-4o" => "gpt-4o",
          "gpt-4o-mini" => "gpt-4o-mini",
          "gpt-4-turbo" => "gpt-4-turbo-preview"
        },
        default_model: "gpt-4o",
        headers: ->(key) {
          {
            "Authorization" => "Bearer #{key}",
            "Content-Type" => "application/json"
          }
        }
      },
      anthropic: {
        name: "Anthropic",
        base_url: "https://api.anthropic.com/v1",
        models: {
          "claude-opus-4" => "claude-opus-4-20250514",
          "claude-sonnet-4" => "claude-sonnet-4-20250514",
          "claude-3.5" => "claude-3-5-sonnet-20241022"
        },
        default_model: "claude-sonnet-4-20250514",
        headers: ->(key) {
          {
            "x-api-key" => key,
            "anthropic-version" => "2023-06-01",
            "Content-Type" => "application/json"
          }
        },
        format: :anthropic  # Uses different API format
      },
      gemini: {
        name: "Google Gemini",
        base_url: "https://generativelanguage.googleapis.com/v1beta",
        models: {
          "gemini-pro" => "gemini-pro",
          "gemini-2.0" => "gemini-2.0-flash-exp"
        },
        default_model: "gemini-2.0-flash-exp",
        headers: ->(key) {
          {
            "Content-Type" => "application/json"
          }
        },
        format: :gemini  # Uses different API format
      },
      deepseek: {
        name: "DeepSeek",
        base_url: "https://api.deepseek.com/v1",
        models: {
          "deepseek-chat" => "deepseek-chat",
          "deepseek-reasoner" => "deepseek-reasoner"
        },
        default_model: "deepseek-chat",
        headers: ->(key) {
          {
            "Authorization" => "Bearer #{key}",
            "Content-Type" => "application/json"
          }
        }
      }
    }.freeze

    attr_reader :provider, :model, :usage_stats

    def initialize(provider:, api_key:, model: nil)
      @provider = provider.to_sym
      @api_key = api_key
      @config = PROVIDERS[@provider] or raise "Unknown provider: #{provider}"
      @model = model || @config[:default_model]
      @messages = []
      @usage_stats = { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
    end

    def send(message, &block)
      @messages << { role: "user", content: message }
      
      case @config[:format]
      when :anthropic
        send_anthropic(&block)
      when :gemini
        send_gemini(&block)
      else
        send_openai_compatible(&block)
      end
    end

    def clear_history
      @messages = []
    end

    def models
      @config[:models]
    end

    def switch_model(new_model)
      if @config[:models].values.include?(new_model) || @config[:models].key?(new_model)
        @model = @config[:models][new_model] || new_model
        true
      else
        false
      end
    end

    private

    def send_openai_compatible(&block)
      uri = URI("#{@config[:base_url]}/chat/completions")
      headers = @config[:headers].call(@api_key)
      
      body = {
        model: @model,
        messages: @messages,
        stream: block_given?
      }
      
      if block_given?
        send_streaming_request(uri, headers, body, &block)
      else
        send_non_streaming_request(uri, headers, body)
      end
    end

    def send_anthropic(&block)
      uri = URI("#{@config[:base_url]}/messages")
      headers = @config[:headers].call(@api_key)
      
      body = {
        model: @model,
        messages: @messages,
        max_tokens: 8192,
        stream: block_given?
      }
      
      if block_given?
        send_streaming_request(uri, headers, body, format: :anthropic, &block)
      else
        send_non_streaming_request(uri, headers, body, format: :anthropic)
      end
    end

    def send_gemini(&block)
      # Gemini uses API key in URL and different message format
      uri = URI("#{@config[:base_url]}/models/#{@model}:generateContent?key=#{@api_key}")
      headers = @config[:headers].call(@api_key)
      
      # Convert messages to Gemini format with explicit role handling
      contents = @messages.map do |m|
        role = case m[:role]
        when "user" then "user"
        when "assistant" then "model"
        else "user"  # fallback
        end
        { role: role, parts: [{ text: m[:content] }] }
      end
      
      body = { contents: contents }
      
      # Gemini doesn't support streaming in the same way
      response = send_non_streaming_request(uri, headers, body, format: :gemini)
      
      if block_given?
        block.call(response)
      end
      
      response
    end

    def send_streaming_request(uri, headers, body, format: :openai)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Post.new(uri)
        headers.each { |k, v| request[k] = v }
        request.body = JSON.generate(body)
        
        accumulated = ""
        
        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            error_body = response.body
            raise "API error (#{response.code}): #{error_body}"
          end
          
          response.read_body do |chunk|
            chunk.each_line do |line|
              next if line.strip.empty?
              next unless line.start_with?("data: ")
              
              data = line[6..-1].strip
              next if data == "[DONE]"
              
              begin
                json = JSON.parse(data)
                
                delta = case format
                when :anthropic
                  # Anthropic streaming format
                  if json["type"] == "content_block_delta" && json.dig("delta", "text")
                    json.dig("delta", "text")
                  end
                else
                  # OpenAI-compatible streaming format
                  json.dig("choices", 0, "delta", "content")
                end
                
                if delta
                  accumulated << delta
                  yield delta if block_given?
                end
              rescue JSON::ParserError
                # Skip invalid JSON
              end
            end
          end
        end
        
        @messages << { role: "assistant", content: accumulated }
        accumulated
      end
    rescue => e
      handle_error(e)
    end

    def send_non_streaming_request(uri, headers, body, format: :openai)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 60
      
      request = Net::HTTP::Post.new(uri)
      headers.each { |k, v| request[k] = v }
      request.body = JSON.generate(body)
      
      response = http.request(request)
      
      unless response.is_a?(Net::HTTPSuccess)
        # Sanitize error message to avoid exposing sensitive data
        error_code = response.code
        error_msg = case error_code
        when "401" then "Authentication failed"
        when "403" then "Access forbidden"
        when "429" then "Rate limit exceeded"
        when "500", "502", "503" then "Server error"
        else "Request failed"
        end
        raise "API error (#{error_code}): #{error_msg}"
      end
      
      json = JSON.parse(response.body)
      
      content = case format
      when :anthropic
        # Anthropic response format
        update_usage(json["usage"]) if json["usage"]
        json.dig("content", 0, "text")
      when :gemini
        # Gemini response format
        json.dig("candidates", 0, "content", "parts", 0, "text")
      else
        # OpenAI-compatible response format
        update_usage(json["usage"]) if json["usage"]
        json.dig("choices", 0, "message", "content")
      end
      
      @messages << { role: "assistant", content: content }
      content
    rescue => e
      handle_error(e)
    end

    def update_usage(usage)
      @usage_stats[:prompt_tokens] += usage["prompt_tokens"] || 0
      @usage_stats[:completion_tokens] += usage["completion_tokens"] || 0
      @usage_stats[:total_tokens] += usage["total_tokens"] || 0
    end

    def handle_error(error)
      case error.message
      when /401/
        "API Error: Invalid API key. Use /key to update."
      when /429/
        "API Error: Rate limit exceeded. Please try again later."
      when /timeout/i
        "API Error: Request timeout. Please try again."
      else
        "API Error: #{error.message}"
      end
    end
  end
end
