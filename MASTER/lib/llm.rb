# frozen_string_literal: true
require "net/http"
require "json"
require "uri"
require "digest"
require "fileutils"

module Master
  class LLM
    TIERS = {
      fast:   { model: "google/gemini-2.0-flash-001", cost_per_1k: 0.0001 },
      code:   { model: "x-ai/grok-3-mini-beta", cost_per_1k: 0.0005 },
      medium: { model: "anthropic/claude-sonnet-4", cost_per_1k: 0.003 },
      strong: { model: "anthropic/claude-opus-4", cost_per_1k: 0.015 }
    }.freeze

    attr_reader :total_cost, :total_tokens

    def initialize(principles: [])
      @api_key = ENV["OPENROUTER_API_KEY"]
      @base_uri = URI("https://openrouter.ai/api/v1/chat/completions")
      @total_cost = 0.0
      @total_tokens = 0
      @cache_dir = File.join(Master::ROOT, "var", "cache")
      @principles = principles
      @system_prompt = build_system_prompt
      FileUtils.mkdir_p(@cache_dir) rescue nil
    end

    def build_system_prompt
      persona = Master::PERSONA
      
      prompt = <<~PROMPT
        You are #{persona[:name]}.
        
        PERSONALITY: #{persona[:traits].join(', ')}
        
        RESPONSE RULES:
        - Greetings/small talk: 1-2 sentences, no research needed
        - Questions needing facts: search the web, cite sources
        - Technical questions: be thorough but concise
        - No bullet points unless the answer has multiple items
        - Omit preamble, get to the point
        
        STYLE: #{persona[:rules].join('. ')}.
      PROMPT
      
      if @principles.any?
        prompt += "\nPRINCIPLES:\n"
        @principles.first(10).each_with_index do |p, i|
          prompt += "#{i+1}. #{p.name}\n"
        end
      end
      
      prompt
    end

    def ask(prompt, tier: :fast, max_tokens: 2048, cache: true)
      return Result.err("No API key") unless @api_key
      
      tier_config = TIERS[tier] || TIERS[:fast]
      model = tier_config[:model]
      
      # Check cache first
      if cache
        cached = cache_get(prompt, model)
        return Result.ok(cached) if cached
      end
      
      messages = []
      messages << { role: "system", content: @system_prompt } if @system_prompt
      messages << { role: "user", content: prompt }
      
      body = {
        model: model,
        messages: messages,
        max_tokens: max_tokens
      }
      http = Net::HTTP.new(@base_uri.host, @base_uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      req = Net::HTTP::Post.new(@base_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Content-Type"] = "application/json"
      req.body = body.to_json
      resp = http.request(req)
      data = JSON.parse(resp.body)
      
      if data["choices"]&.first
        content = data["choices"].first.dig("message", "content")
        
        # Track cost
        usage = data["usage"] || {}
        tokens = (usage["total_tokens"] || 0)
        cost = (tokens / 1000.0) * tier_config[:cost_per_1k]
        @total_tokens += tokens
        @total_cost += cost
        
        # Cache response
        cache_set(prompt, model, content) if cache
        
        Result.ok(content)
      else
        Result.err(data["error"]&.dig("message") || "Unknown error")
      end
    rescue => e
      Result.err(e.message)
    end

    def cost_summary
      "$#{'%.4f' % @total_cost} (#{@total_tokens} tokens)"
    end

    private

    def cache_key(prompt, model)
      Digest::SHA256.hexdigest("#{model}:#{prompt}")[0..15]
    end

    def cache_get(prompt, model)
      path = File.join(@cache_dir, cache_key(prompt, model))
      return nil unless File.exist?(path)
      data = JSON.parse(File.read(path))
      # Cache valid for 24 hours
      return nil if Time.now.to_i - data["ts"] > 86400
      data["response"]
    rescue
      nil
    end

    def cache_set(prompt, model, response)
      path = File.join(@cache_dir, cache_key(prompt, model))
      File.write(path, { ts: Time.now.to_i, response: response }.to_json)
    rescue
      # Ignore cache write failures
    end
  end
end
