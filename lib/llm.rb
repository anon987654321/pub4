# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module MASTER
  class LLM
    TIERS = {
      cheap:     { model: 'deepseek/deepseek-chat',        input: 0.00014, output: 0.00028 },
      fast:      { model: 'x-ai/grok-4-fast',              input: 0.0002,  output: 0.0005 },
      code:      { model: 'x-ai/grok-code-fast-1',         input: 0.0002,  output: 0.0015 },
      strong:    { model: 'anthropic/claude-sonnet-4',     input: 0.003,   output: 0.015 },
      reasoning: { model: 'deepseek/deepseek-r1',          input: 0.00055, output: 0.00219 },
      gemini:    { model: 'google/gemini-3-flash-preview', input: 0.0001,  output: 0.0004 },
      glm:       { model: 'z-ai/glm-4.7',                  input: 0.00035, output: 0.0014 },
      kimi:      { model: 'moonshotai/kimi-k2.5',          input: 0.0002,  output: 0.001 },
      auto:      { model: 'openrouter/auto',               input: 0.003,   output: 0.015 }
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

      # Identity and context
      parts << "You are MASTER v#{VERSION}, a constitutional AI running on #{platform_context}."
      parts << "Your host is a #{runtime_context}."
      parts << "You embody clarity, efficiency, and correctness. No bloat. No ceremony."

      if @persona
        parts << "\n## Persona: #{@persona[:name]}"
        parts << @persona[:prompt] if @persona[:prompt]
      end

      parts << "\n## Principles"
      @principles.first(10).each do |p|
        parts << "- #{p[:name]}: #{p[:description]}"
      end

      parts << "\n## Style"
      parts << "- Concise. Direct. No filler."
      parts << "- Code over prose. Show, don't tell."
      parts << "- Admit uncertainty. Never fabricate."
      parts << "- One right way. Find it."

      parts.join("\n")
    end

    def platform_context
      case RUBY_PLATFORM
      when /openbsd/
        "OpenBSD—the world's most secure Unix"
      when /darwin/
        "macOS"
      when /linux.*android/, /aarch64.*linux/
        "Termux on Android"
      when /linux/
        "Linux"
      else
        "a Unix-like system"
      end
    end

    def runtime_context
      mem = begin
        case RUBY_PLATFORM
        when /linux/
          File.read('/proc/meminfo')[/MemTotal:\s+(\d+)/, 1].to_i / 1024
        when /openbsd/, /darwin/
          512
        else
          512
        end
      rescue
        512
      end

      "pure Ruby CLI (#{RUBY_VERSION}, #{mem}MB RAM, no npm, no electron, no bloat)"
    end
  end
end
