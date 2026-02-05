# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module MASTER
  class LLM
    TIERS = {
      fast:    { model: 'deepseek/deepseek-chat', cost: 0.00014 },
      code:    { model: 'deepseek/deepseek-chat', cost: 0.00014 },
      medium:  { model: 'deepseek/deepseek-chat', cost: 0.00014 },
      strong:  { model: 'anthropic/claude-sonnet-4-20250514', cost: 0.015 },
      premium: { model: 'anthropic/claude-opus-4-20250514', cost: 0.075 }
    }.freeze

    DEFAULT_TIER = :medium
    MAX_RETRIES = 3
    RETRY_DELAYS = [1, 2, 4].freeze

    attr_reader :total_cost, :persona

    def initialize
      @api_key = ENV['OPENROUTER_API_KEY']
      @base_url = 'https://openrouter.ai/api/v1'
      @total_cost = 0.0
      @cache = {}
      @history = []
      @persona = load_persona('default')
      @principles = Principle.load_all
    end

    def chat(message, tier: DEFAULT_TIER)
      return Result.err('No API key') unless @api_key

      cache_key = "#{tier}:#{message}"
      return Result.ok(@cache[cache_key]) if @cache[cache_key]

      @history << { role: 'user', content: message }
      result = call_api(tier)

      if result.ok?
        @cache[cache_key] = result.value
        @history << { role: 'assistant', content: result.value }
      end

      result
    end

    def switch_persona(name)
      persona = load_persona(name)
      return Result.err("Unknown persona: #{name}") unless persona

      @persona = persona
      Result.ok(persona)
    end

    def clear_history
      @history.clear
    end

    private

    def load_persona(name)
      Persona.load(name)
    rescue
      nil
    end

    def call_api(tier)
      config = TIERS[tier] || TIERS[DEFAULT_TIER]
      retries = 0

      begin
        uri = URI("#{@base_url}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 60

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{@api_key}"
        request['Content-Type'] = 'application/json'
        request['HTTP-Referer'] = 'https://brgen.no'

        request.body = {
          model: config[:model],
          messages: build_messages,
          temperature: 0.7,
          max_tokens: 4096
        }.to_json

        response = http.request(request)
        data = JSON.parse(response.body)

        if data['error']
          return Result.err(data['error']['message'])
        end

        content = data.dig('choices', 0, 'message', 'content')
        usage = data['usage'] || {}
        @total_cost += (usage['total_tokens'] || 0) * config[:cost] / 1000.0

        Result.ok(content)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
        retries += 1
        if retries <= MAX_RETRIES
          sleep RETRY_DELAYS[retries - 1]
          retry
        end
        Result.err("Network error: #{e.message}")
      rescue => e
        Result.err(e.message)
      end
    end

    def build_messages
      system_prompt = build_system_prompt
      [{ role: 'system', content: system_prompt }] + @history
    end

    def build_system_prompt
      parts = []
      parts << "You are MASTER v#{VERSION}, a constitutional AI assistant."

      if @persona
        parts << "\n## Persona: #{@persona[:name]}"
        parts << @persona[:prompt] if @persona[:prompt]
      end

      parts << "\n## Principles"
      @principles.first(10).each do |p|
        parts << "- #{p[:name]}: #{p[:description]}"
      end

      parts << "\n## Rules"
      parts << "- Be concise and direct"
      parts << "- Show code, not explanations"
      parts << "- Admit uncertainty"

      parts.join("\n")
    end
  end
end
