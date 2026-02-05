# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

begin
  require 'ruby_llm'
rescue LoadError
end

module MASTER
  class LLM
    MAX_TOKENS = 4096
    
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
    BACKENDS = %i[http ruby_llm].freeze

    DEFAULT_TIER = :strong
    MAX_RETRIES = 3
    RETRY_DELAYS = [1, 2, 4].freeze

    attr_reader :total_cost, :persona, :last_tokens, :last_cached,
                :total_tokens_in, :total_tokens_out, :request_count, :backend,
                :context_files

    def initialize(backend: nil)
      @api_key = ENV['OPENROUTER_API_KEY']
      @base_url = ENV['OPENROUTER_BASE_URL'] || ENV['OPENROUTER_API_BASE'] || 'https://openrouter.ai/api/v1'
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
      @current_tier = DEFAULT_TIER
      @context_files = []
      @backend = resolve_backend(backend || ENV['MASTER_LLM_BACKEND'])
      configure_ruby_llm if @backend == :ruby_llm
      load_conversation_history
    end

    def chat(message, tier: nil)
      tier ||= @current_tier || DEFAULT_TIER
      return Result.err('No API key') unless @api_key

      @current_tier = tier
      cache_key = "#{tier}:#{message}"
      if @cache[cache_key]
        @last_cached = true
        @last_tokens = { input: 0, output: 0 }
        return Result.ok(@cache[cache_key])
      end

      @last_cached = false
      result = if @backend == :ruby_llm
                 ruby_llm_chat(message, tier)
               else
                 @history << { role: 'user', content: message }
                 call_api(tier)
               end

      if result.ok?
        @cache[cache_key] = result.value
        @history << { role: 'assistant', content: result.value } if @backend != :ruby_llm
        save_conversation_history
      end

      result
    end

    def set_tier(tier)
      return false unless TIERS.key?(tier)
      @current_tier = tier
      true
    end

    def status
      {
        tier: @current_tier,
        model: current_model_name,
        last_tokens: @last_tokens&.dup || {},
        last_cached: @last_cached,
        total_cost: @total_cost,
        request_count: @request_count,
        connected: !!@api_key
      }
    end

    def switch_persona(name)
      persona = load_persona(name)
      return Result.err("Unknown persona: #{name}") unless persona

      @persona = persona
      Result.ok(persona)
    end

    def clear_history
      @history.clear
      save_conversation_history
    end

    def chat_with_model(model, prompt)
      return Result.err('No API key') unless @api_key

      @last_cached = false
      if @backend == :ruby_llm
        ruby_llm_chat_with_model(model, prompt)
      else
        call_api_direct(model, prompt)
      end
    end

    # Streaming support: yields tokens as they arrive
    def stream_ask(message, tier: nil, &block)
      tier ||= @current_tier || DEFAULT_TIER
      return Result.err('No API key') unless @api_key
      return Result.err('No block given') unless block_given?

      return ruby_llm_stream(message, tier, &block) if @backend == :ruby_llm

      begin
        require_relative 'token_streamer'
        @current_tier = tier
        @last_cached = false
        @history << { role: 'user', content: message }

        streamer = TokenStreamer.new(@api_key, @base_url)
        config = TIERS[tier] || TIERS[DEFAULT_TIER]
        
        result = streamer.stream(config[:model], build_messages) do |token|
          block.call(token)
        end

        if result.ok?
          @history << { role: 'assistant', content: result.value }
          usage = result.metadata[:usage] || {}
          input_tokens = usage[:input] || 0
          output_tokens = usage[:output] || 0
          @last_tokens = { input: input_tokens, output: output_tokens }
          @total_tokens_in += input_tokens
          @total_tokens_out += output_tokens
          @request_count += 1
          @total_cost += estimate_cost(input_tokens, output_tokens, tier)
        end

        result
      rescue LoadError => e
        Result.err("Streaming not available: #{e.message}")
      rescue => e
        Result.err("Streaming error: #{e.message}")
      end
    end

    attr_reader :last_cost

    def add_context_file(path)
      return Result.err('Path required') unless path
      return Result.err("Not found: #{path}") unless File.exist?(path)

      full = File.expand_path(path)
      @context_files << full unless @context_files.include?(full)
      Result.ok(full)
    end

    def drop_context_file(path)
      return Result.err('Path required') unless path
      full = File.expand_path(path)
      return Result.err("Not found: #{path}") unless @context_files.include?(full)

      @context_files.delete(full)
      Result.ok(full)
    end

    def clear_context_files
      @context_files.clear
    end

    def set_backend(name)
      return Result.err('Backend required') unless name
      key = name.to_s.downcase.to_sym
      return Result.err('Unknown backend') unless BACKENDS.include?(key)
      return Result.err('ruby_llm unavailable') if key == :ruby_llm && !ruby_llm_available?

      @backend = key
      configure_ruby_llm if @backend == :ruby_llm
      Result.ok(@backend)
    end

    private

    def resolve_backend(value)
      return :http if value.nil? || value.to_s.strip.empty?
      key = value.to_s.strip.downcase.to_sym
      return :ruby_llm if key == :ruby_llm && ruby_llm_available?
      :http
    end

    def ruby_llm_available?
      defined?(RubyLLM)
    end

    def configure_ruby_llm
      return unless ruby_llm_available? && @api_key
      RubyLLM.configure do |config|
        config.openrouter_api_key = @api_key
      end
    rescue StandardError
      nil
    end

    def ruby_llm_chat(message, tier)
      chat = ruby_llm_session(tier)
      response = chat.ask(message, with: resolved_context_files)
      content = response.content
      @history << { role: 'user', content: message }
      @history << { role: 'assistant', content: content }
      update_usage_from_response(response, tier)
      Result.ok(content)
    rescue StandardError => e
      Result.err(e.message)
    end

    def ruby_llm_chat_with_model(model, prompt)
      chat = ruby_llm_session(DEFAULT_TIER, model: model)
      response = chat.ask(prompt, with: resolved_context_files)
      update_usage_from_response(response, DEFAULT_TIER)
      Result.ok(response.content)
    rescue StandardError => e
      Result.err(e.message)
    end

    def ruby_llm_stream(message, tier, &block)
      chat = ruby_llm_session(tier)
      response = chat.ask(message, with: resolved_context_files) do |chunk|
        block.call(chunk.content.to_s)
      end
      @history << { role: 'user', content: message }
      @history << { role: 'assistant', content: response.content }
      update_usage_from_response(response, tier)
      Result.ok(response.content)
    rescue StandardError => e
      Result.err("Streaming error: #{e.message}")
    end

    def ruby_llm_session(tier, model: nil)
      config = TIERS[tier] || TIERS[DEFAULT_TIER]
      model_name = model || config[:model]
      raise ArgumentError, 'Model required' if model_name.to_s.strip.empty?
      raise ArgumentError, "Invalid model: #{model_name}" unless model_name.match?(/\A(?!.*\.\.)[\w.\-]+(?:\/[\w.\-]+)*\z/)

      chat = RubyLLM.chat(provider: :openrouter, model: model_name, assume_model_exists: true)
      chat.with_instructions(build_system_prompt, replace: true)
      @history.each do |entry|
        chat.add_message(role: entry[:role].to_sym, content: entry[:content])
      end
      chat
    end

    def resolved_context_files
      @context_files.select { |path| File.exist?(path) }
    end

    def update_usage_from_response(response, tier)
      tokens = extract_tokens(response)
      input_tokens = tokens[:input]
      output_tokens = tokens[:output]
      @last_tokens = { input: input_tokens, output: output_tokens }
      @total_tokens_in += input_tokens
      @total_tokens_out += output_tokens
      @request_count += 1
      cost = safe_float(response.respond_to?(:cost) ? response.cost : nil)
      @total_cost += cost || estimate_cost(input_tokens, output_tokens, tier)
      @last_cost = cost if cost
    end

    def estimate_cost(input_tokens, output_tokens, tier)
      config = TIERS[tier] || TIERS[DEFAULT_TIER]
      (input_tokens * config[:input] + output_tokens * config[:output]) / 1000.0
    end

    def extract_tokens(response)
      {
        input: response.respond_to?(:input_tokens) ? response.input_tokens.to_i : 0,
        output: response.respond_to?(:output_tokens) ? response.output_tokens.to_i : 0
      }
    end

    def safe_float(value)
      return nil if value.nil?
      Float(value)
    rescue StandardError
      nil
    end

    def load_persona(name)
      Persona.load(name)
    rescue StandardError
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
        request['HTTP-Referer'] = ENV['OPENROUTER_REFERER'] || ENV['MASTER_ORIGIN'] || 'https://brgen.no'
        request['X-Title'] = ENV['OPENROUTER_TITLE'] || 'MASTER'

        request.body = {
          model: config[:model],
          messages: build_messages,
          temperature: 0.7,
          max_tokens: MAX_TOKENS
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
        @total_cost += estimate_cost(input_tokens, output_tokens, tier)

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
        request['HTTP-Referer'] = ENV['OPENROUTER_REFERER'] || ENV['MASTER_ORIGIN'] || 'https://brgen.no'
        request['X-Title'] = ENV['OPENROUTER_TITLE'] || 'MASTER'

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
      model_name = current_model_name
      parts << "You are #{CODENAME} version #{VERSION} (#{model_name} via OpenRouter)."
      parts << "You are running on #{platform_context}."
      parts << "Your host is a #{runtime_context}."
      parts << "You embody clarity, efficiency, and correctness. No bloat. No ceremony."

      # Tool capabilities - platform specific
      parts << "\n## Tools - YOU HAVE REAL EXECUTION"
      parts << "You run on #{RUBY_PLATFORM.include?('openbsd') ? 'OpenBSD' : RUBY_PLATFORM}. Code blocks execute AUTOMATICALLY."
      parts << ""
      
      if RUBY_PLATFORM.include?('openbsd')
        parts << "Shell (OpenBSD): ```sh"
        parts << "ftp -o - https://example.com | head -20   # OpenBSD native HTTPS"
        parts << "ls -la /path && cat file.txt"
        parts << "doas pkg_add -u"
        parts << "```"
      else
        parts << "Shell: ```sh"
        parts << "curl -s https://example.com | head -20"
        parts << "ls -la /path && cat file.txt"
        parts << "```"
      end
      
      parts << ""
      parts << "Ruby: ```ruby"
      parts << "require 'net/http'; puts Net::HTTP.get(URI('https://api.github.com'))"
      parts << "MASTER::Web.browse('https://github.com')  # built-in web fetcher"
      parts << "```"
      parts << ""
      parts << "You CAN: fetch URLs (ftp/curl), run any shell command, execute Ruby, scrape web, use doas."
      parts << "NEVER say 'I cannot' - JUST DO IT with a code block. You'll see the output."

      if @persona
        parts << "\n## Persona: #{@persona[:name]}"
        parts << @persona[:prompt] if @persona[:prompt]
      end

      parts << "\n## Principles"
      @principles.first(10).each do |p|
        parts << "- #{p[:name]}: #{p[:description]}"
      end

      parts << "\n## Output Style"
      parts << "- Unix philosophy: terse, no fluff."
      parts << "- One line when one will do."
      parts << "- No markdown formatting in responses."
      parts << "- No bullet points or headers."
      parts << "- Plain text only. Like a shell."
      parts << "- Admit uncertainty. Never fabricate."

      parts.join("\n")
    end

    def current_model_name
      config = TIERS[@current_tier] || TIERS[DEFAULT_TIER]
      config[:model].split('/').last.gsub('-', ' ').gsub(/(\d)/, ' \1').strip
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
      rescue StandardError
        512
      end

      "pure Ruby CLI (#{RUBY_VERSION}, #{mem}MB RAM, no npm, no electron, no bloat)"
    end

    # Conversation persistence
    CONVERSATION_FILE = File.join(Paths.var, 'conversation.json')
    MAX_HISTORY = 100
    COMPRESS_THRESHOLD = 50

    def load_conversation_history
      return unless File.exist?(CONVERSATION_FILE)

      data = JSON.parse(File.read(CONVERSATION_FILE), symbolize_names: true)
      @history = data[:messages] || []
      @conversation_summary = data[:summary]
      
      # Inject summary as system context if exists
      if @conversation_summary && @history.empty?
        @history << { role: 'system', content: "Previous conversation summary: #{@conversation_summary}" }
      end
    rescue => e
      @history = []
    end

    def save_conversation_history
      compress_history if @history.size > COMPRESS_THRESHOLD

      data = {
        messages: @history.last(MAX_HISTORY),
        summary: @conversation_summary,
        saved_at: Time.now.to_i
      }
      
      FileUtils.mkdir_p(File.dirname(CONVERSATION_FILE))
      File.write(CONVERSATION_FILE, JSON.pretty_generate(data))
    rescue => e
      # Silent fail
    end

    def compress_history
      return if @history.size <= 20

      # Keep last 20, summarize the rest
      to_summarize = @history[0...-20]
      old_summary = @conversation_summary
      
      context = to_summarize.map { |m| "#{m[:role]}: #{m[:content][0..200]}" }.join("\n")
      prompt = old_summary ? 
        "Previous: #{old_summary}\n\nNew:\n#{context}\n\nUpdate summary (50 words max):" :
        "Summarize:\n#{context}\n\n50 words max:"
      
      result = quick_ask(prompt, tier: :fast)
      @conversation_summary = result if result
      @history = @history.last(20)
    end
  end
end
