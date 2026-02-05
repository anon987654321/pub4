# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module MASTER
  class LLM
    TIERS = {
      cheap:   { model: 'deepseek/deepseek-chat',         input: 0.00014, output: 0.00028 },
      fast:    { model: 'anthropic/claude-3.5-haiku',     input: 0.0008,  output: 0.004 },
      strong:  { model: 'anthropic/claude-sonnet-4',      input: 0.003,   output: 0.015 },
      premium: { model: 'anthropic/claude-opus-4',        input: 0.015,   output: 0.075 },
      reasoning: { model: 'deepseek/deepseek-r1',         input: 0.00055, output: 0.00219 }
    }.freeze

    DEFAULT_TIER = :strong
    MAX_RETRIES = 3
    RETRY_DELAYS = [1, 2, 4].freeze

    attr_reader :total_cost, :persona, :last_tokens, :last_cached,
                :total_tokens_in, :total_tokens_out, :request_count

    def initialize
      @api_key = ENV['OPENROUTER_API_KEY']
      @base_url = 'https://openrouter.ai/api/v1'
      @total_cost = 0.0
      @total_tokens_in = 0
      @total_tokens_out = 0
      @request_count = 0
      @cache = {}
      @history = []
      @persona = load_persona('generic')
      @principles = Principle.load_all
      @last_tokens = { input: 0, output: 0 }
      @last_cached = false
    end

    def chat(message, tier: DEFAULT_TIER)
      return Result.err('No API key') unless @api_key

      cache_key = "#{tier}:#{message}"
      if @cache[cache_key]
        @last_cached = true
        @last_tokens = { input: 0, output: 0 }
        return Result.ok(@cache[cache_key])
      end

      @last_cached = false
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

    def chat_with_model(model, prompt)
      return Result.err('No API key') unless @api_key

      @last_cached = false
      call_api_direct(model, prompt)
    end

    attr_reader :last_cost

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
        input_tokens = usage['prompt_tokens'] || 0
        output_tokens = usage['completion_tokens'] || 0
        @last_tokens = { input: input_tokens, output: output_tokens }
        @total_tokens_in += input_tokens
        @total_tokens_out += output_tokens
        @request_count += 1
        @total_cost += (input_tokens * config[:input] + output_tokens * config[:output]) / 1000.0

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

    def call_api_direct(model, prompt)
      @last_cost = 0.0

      begin
        uri = URI("#{@base_url}/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 10
        http.read_timeout = 90

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{@api_key}"
        request['Content-Type'] = 'application/json'
        request['HTTP-Referer'] = 'https://brgen.no'

        request.body = {
          model: model,
          messages: [{ role: 'user', content: prompt }],
          temperature: 0.5,
          max_tokens: 4096
        }.to_json

        response = http.request(request)
        data = JSON.parse(response.body)

        return Result.err(data['error']['message']) if data['error']

        content = data.dig('choices', 0, 'message', 'content')
        usage = data['usage'] || {}
        input_tokens = usage['prompt_tokens'] || 0
        output_tokens = usage['completion_tokens'] || 0

        # Estimate cost (average across models)
        @last_cost = (input_tokens * 0.002 + output_tokens * 0.008) / 1000.0
        @total_cost += @last_cost
        @total_tokens_in += input_tokens
        @total_tokens_out += output_tokens
        @request_count += 1

        Result.ok(content)
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
