# frozen_string_literal: true
require "net/http"
require "json"
require "uri"
require "digest"
require "fileutils"

module Master
  class LLM
    TIERS = {
      fast:    { model: "deepseek/deepseek-chat", cost_per_1k: 0.00014 },
      code:    { model: "deepseek/deepseek-coder", cost_per_1k: 0.00014 },
      medium:  { model: "deepseek/deepseek-chat", cost_per_1k: 0.00014 },
      strong:  { model: "anthropic/claude-sonnet-4-5-20250514", cost_per_1k: 0.003 },
      premium: { model: "anthropic/claude-opus-4", cost_per_1k: 0.015 }
    }.freeze
    DEFAULT_TIER = :medium
    MAX_RETRIES = 3
    RETRY_DELAYS = [1, 2, 4].freeze  # Exponential backoff

    attr_reader :total_cost, :total_tokens
    attr_accessor :persona

    def initialize(principles: [], persona: nil)
      @api_key = ENV["OPENROUTER_API_KEY"]
      @base_uri = URI("https://openrouter.ai/api/v1/chat/completions")
      @total_cost = 0.0
      @total_tokens = 0
      @cache_dir = File.join(Master::ROOT, "var", "cache")
      @principles = principles
      @persona = persona || Persona.load("default")
      @system_prompt = build_system_prompt
      FileUtils.mkdir_p(@cache_dir) rescue nil
    end

    def build_system_prompt
      prompt = ""
      
      if @persona
        prompt = @persona.to_prompt + "\n"
      else
        prompt = "PERSONA: default\nTRAITS: direct, concise, clear\n"
      end
      
      prompt += <<~RULES
        
        RESPONSE RULES:
        - Greetings/small talk: 1-2 sentences, no research needed
        - Questions needing facts: search the web, cite sources
        - Technical questions: be thorough but concise
        - No bullet points unless the answer has multiple items
        - Omit preamble, get to the point
      RULES
      
      if @principles.any?
        prompt += "\nPRINCIPLES:\n"
        @principles.first(10).each_with_index do |p, i|
          prompt += "#{i+1}. #{p.name}\n"
        end
      end
      
      prompt
    end

    def switch_persona(name)
      new_persona = Persona.load(name)
      return Result.err("Persona not found: #{name}") unless new_persona
      @persona = new_persona
      @system_prompt = build_system_prompt
      Result.ok("Switched to #{name}")
    end

    def ask(prompt, tier: DEFAULT_TIER, max_tokens: 2048, cache: true)
      return Result.err("No API key") unless @api_key
      
      tier_config = TIERS[tier] || TIERS[DEFAULT_TIER]
      model = tier_config[:model]
      
      # Check cache first
      if cache
        cached = cache_get(prompt, model)
        return Result.ok(cached) if cached
      end
      
      # Retry with exponential backoff
      last_error = nil
      MAX_RETRIES.times do |attempt|
        result = do_request(prompt, model, max_tokens, tier_config)
        return result if result.ok?
        
        last_error = result.error
        
        # Don't retry on auth errors
        break if last_error.include?("auth") || last_error.include?("key")
        
        # Wait before retry
        sleep(RETRY_DELAYS[attempt] || 4) if attempt < MAX_RETRIES - 1
      end
      
      Result.err(last_error || "Max retries exceeded")
    end

    def cost_summary
      "$#{'%.4f' % @total_cost} (#{@total_tokens} tokens)"
    end

    private

    def do_request(prompt, model, max_tokens, tier_config)
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
        cache_set(prompt, model, content)
        
        Result.ok(content)
      else
        Result.err(data["error"]&.dig("message") || "Unknown error")
      end
    rescue => e
      Result.err(e.message)
    end

    def cache_key(prompt, model)
      Digest::SHA256.hexdigest("#{model}:#{prompt}")[0..15]
    end

    def cache_get(prompt, model)
      path = File.join(@cache_dir, cache_key(prompt, model))
      return nil unless File.exist?(path)
      data = JSON.parse(File.read(path))
      return nil if Time.now.to_i - data["ts"] > 86400
      data["response"]
    rescue
      nil
    end

    def cache_set(prompt, model, response)
      path = File.join(@cache_dir, cache_key(prompt, model))
      File.write(path, { ts: Time.now.to_i, response: response }.to_json)
    rescue
      nil
    end
  end
end
