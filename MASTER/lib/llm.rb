# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'securerandom'
require 'fileutils'
require 'time'

begin
  require 'ruby_llm'
rescue LoadError
end

module MASTER
  # LLM routing with integrated cost tracking (Monitor)
  # NOTE: Cost tracking is inseparable from routing - every API call must be
  # metered for budget control, provider health monitoring, and usage analytics.
  # The Monitor functionality is embedded here rather than separated to ensure
  # atomic tracking of all LLM operations.
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
      @system_context = []  # Additional system context (e.g., self-awareness)
      @backend = resolve_backend(backend || ENV['MASTER_LLM_BACKEND'])
      configure_ruby_llm if @backend == :ruby_llm
      load_conversation_history
    end

    def add_system_context(context)
      @system_context << context unless @system_context.include?(context)
    end

    def chat(message, tier: nil)
      tier ||= @current_tier || DEFAULT_TIER
      return Result.err('No API key') unless @api_key

      # Autonomy: Check budget before proceeding
      estimated = Autonomy.estimate_cost(message) rescue 0.01
      unless Autonomy.within_budget?(estimated)
        return Result.err("Budget exceeded ($#{Autonomy.total_cost.round(2)}/$#{Autonomy.config[:budget_limit]})")
      end

      # Autonomy: Check circuit breaker
      provider = extract_provider(tier)
      if Autonomy.circuit_open?(provider)
        # Try fallback
        fallback_tier = find_fallback_tier(tier)
        tier = fallback_tier if fallback_tier
      end

      # Autonomy: Detect task type and adjust parameters
      @task_params = PromptAutonomy.task_parameters(message) rescue {}

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

      # Autonomy: Record result for circuit breaker
      Autonomy.record_provider_result(provider, result.ok?) rescue nil

      # Autonomy: Track cost
      if result.ok?
        Autonomy.track_cost(@last_cost || 0) rescue nil
        @cache[cache_key] = result.value
        @history << { role: 'assistant', content: result.value } if @backend != :ruby_llm
        save_conversation_history

        # Autonomy: Track for prompt learning
        PromptAutonomy.track_execution("chat:#{tier}", success: true, tokens: @last_tokens[:output]) rescue nil
      else
        PromptAutonomy.track_execution("chat:#{tier}", success: false) rescue nil
      end

      result
    end

    def extract_provider(tier)
      model = TIERS.dig(tier, :model) || 'unknown'
      model.split('/').first
    end

    def find_fallback_tier(current_tier)
      # Fallback chain: strong -> code -> fast -> cheap
      chain = [:strong, :code, :fast, :cheap, :gemini]
      idx = chain.index(current_tier)
      return nil unless idx

      chain[(idx + 1)..-1].find { |t| !Autonomy.circuit_open?(extract_provider(t)) }
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

      # Autonomy: Prune context if approaching limits
      messages = build_messages
      if messages.size > 50
        messages = Autonomy.prune_context(messages, token_limit: 100000, current_tokens: estimate_message_tokens(messages)) rescue messages
      end

      # Autonomy: Get task-specific parameters
      temp = @task_params[:temperature] || 0.7
      top_p = @task_params[:top_p] || 0.95

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

        # Autonomy: Add prompt caching headers if applicable
        cache_headers = PromptAutonomy.cache_headers(messages.first&.dig(:content)) rescue {}
        cache_headers.each { |k, v| request[k] = v }

        request.body = {
          model: config[:model],
          messages: messages,
          temperature: temp,
          top_p: top_p,
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
        @last_cost = estimate_cost(input_tokens, output_tokens, tier)
        @total_cost += @last_cost

        # Dmesg trace
        Dmesg.llm(tier, config[:model], tokens_in: input_tokens, tokens_out: output_tokens, cost: @last_cost) rescue nil

        Result.ok(content)
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED => e
        retries += 1
        Dmesg.retry_event(retries, MAX_RETRIES, e.class.name) rescue nil
        if retries <= MAX_RETRIES
          # Autonomy: On timeout, try with reduced context
          if retries == 2 && Autonomy.config[:timeout_recovery]
            @history = Autonomy.timeout_recovery_context(@history) rescue @history
            Dmesg.prune(@history.size + 10, @history.size) rescue nil
          end
          sleep RETRY_DELAYS[retries - 1]
          retry
        end
        Dmesg.llm_error(tier, e.message) rescue nil
        Result.err("Network error: #{e.message}")
      rescue => e
        Dmesg.llm_error(tier, e.message) rescue nil
        Result.err(e.message)
      end
    end

    def estimate_message_tokens(messages)
      messages.sum { |m| (m[:content].to_s.length / 4.0).ceil }
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

      parts << "\n## Bias Toward Action"
      parts << "- NEVER ask for permission. NEVER ask clarifying questions. JUST DO IT."
      parts << "- If a task seems incomplete, complete it. Don't stop halfway."
      parts << "- If something fails, try another approach immediately. Don't report failure and wait."
      parts << "- If you need info, get it yourself (run commands, read files). Don't ask the user."
      parts << "- Prefer doing 5 things and getting 1 wrong over doing nothing and being 'safe'."
      parts << "- When given a goal, break it into steps and execute ALL of them. No pausing."
      parts << "- The user is busy. Every question you ask wastes their time. Figure it out."

      # Inject self-awareness and additional system context
      if @system_context&.any?
        parts << "\n## Self-Knowledge"
        @system_context.each { |ctx| parts << ctx }
      end

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

    # Conversation persistence - crash-safe with atomic writes
    CONVERSATION_DIR = Paths.var
    CONVERSATION_FILE = File.join(CONVERSATION_DIR, 'conversation.json')
    SESSION_FILE = File.join(CONVERSATION_DIR, 'session.json')
    MAX_HISTORY = 100
    COMPRESS_THRESHOLD = 50

    def load_conversation_history
      FileUtils.mkdir_p(CONVERSATION_DIR)
      
      # Load session ID or create new one
      if File.exist?(SESSION_FILE)
        session_data = JSON.parse(File.read(SESSION_FILE), symbolize_names: true) rescue {}
        @session_id = session_data[:id]
        @session_name = session_data[:name]
        @session_started = session_data[:started]
      end
      @session_id ||= generate_session_id
      @session_name ||= random_session_name
      @session_started ||= Time.now.to_i
      
      # Load conversation
      return unless File.exist?(CONVERSATION_FILE)

      data = JSON.parse(File.read(CONVERSATION_FILE), symbolize_names: true)
      @history = data[:messages] || []
      @conversation_summary = data[:summary]
      @total_cost = data[:total_cost] || 0.0
      @request_count = data[:request_count] || 0
      
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
        session_id: @session_id,
        session_name: @session_name,
        messages: @history.last(MAX_HISTORY),
        summary: @conversation_summary,
        total_cost: @total_cost,
        request_count: @request_count,
        saved_at: Time.now.to_i
      }
      
      FileUtils.mkdir_p(CONVERSATION_DIR)
      
      # Atomic write - write to temp file then rename
      tmp_file = "#{CONVERSATION_FILE}.tmp"
      File.write(tmp_file, JSON.pretty_generate(data))
      File.rename(tmp_file, CONVERSATION_FILE)
      
      # Save session info separately
      save_session_info
    rescue => e
      # Silent fail but try to cleanup tmp
      File.delete(tmp_file) if tmp_file && File.exist?(tmp_file)
    end

    def save_session_info
      data = {
        id: @session_id,
        name: @session_name,
        started: @session_started,
        last_active: Time.now.to_i,
        message_count: @history.size,
        total_cost: @total_cost
      }
      File.write(SESSION_FILE, JSON.pretty_generate(data))
    rescue
      # Ignore
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

    def generate_session_id
      "#{Time.now.strftime('%Y%m%d')}-#{SecureRandom.hex(4)}"
    end

    def random_session_name
      adjectives = %w[iron steel cobalt neon cyber quantum plasma silicon carbon crystal]
      nouns = %w[wolf falcon hawk phoenix dragon serpent tiger panther raven bear]
      "#{adjectives.sample}-#{nouns.sample}"
    end

    def new_session!
      @session_id = generate_session_id
      @session_name = random_session_name
      @session_started = Time.now.to_i
      @history = []
      @conversation_summary = nil
      save_conversation_history
      save_session_info
    end

    def session_info
      {
        id: @session_id,
        name: @session_name,
        started: @session_started ? Time.at(@session_started) : nil,
        messages: @history.size,
        summary: @conversation_summary
      }
    end
  end

  # Cost and token monitoring for LLM usage
  # Tracks metrics like tokscale and crabwalk
  class Monitor
    CHARS_PER_TOKEN = 4 # simple estimation
    
    # Model pricing (per 1M tokens)
    PRICING = {
      'deepseek/deepseek-chat' => { input: 0.14, output: 0.28 },
      'x-ai/grok-4-fast' => { input: 0.20, output: 0.50 },
      'anthropic/claude-3.5-sonnet' => { input: 3.0, output: 15.0 },
      'anthropic/claude-opus-4' => { input: 15.0, output: 75.0 },
      'mistral/codestral-latest' => { input: 0.30, output: 0.90 }
    }.freeze
    
    attr_reader :entries, :current_session
    
    def initialize(log_path: nil)
      @log_path = log_path || default_log_path
      @entries = []
      @current_session = {
        started_at: Time.now,
        total_tokens: 0,
        total_cost: 0.0,
        task_count: 0
      }
      
      ensure_log_directory
    end
    
    # Track an LLM operation
    # @param task_name [String] Name of the task
    # @param model [String] Model identifier or tier
    # @yield Block to execute and measure
    # @return Result of the block
    def track(task_name, model: 'strong', &block)
      start_time = Time.now
      
      # Execute the block
      result = block.call if block_given?
      
      duration = Time.now - start_time
      
      # Estimate tokens from result if it's a string
      tokens = estimate_tokens(result)
      
      # Create entry
      entry = create_entry(
        task: task_name,
        model: resolve_model(model),
        duration: duration,
        tokens_in: tokens[:input] || 0,
        tokens_out: tokens[:output] || 0
      )
      
      # Log immediately
      log_entry(entry)
      
      result
    end
    
    # Track with explicit token counts
    def track_tokens(task_name, model:, tokens_in:, tokens_out:, duration: 0)
      entry = create_entry(
        task: task_name,
        model: resolve_model(model),
        duration: duration,
        tokens_in: tokens_in,
        tokens_out: tokens_out
      )
      
      log_entry(entry)
    end
    
    # Generate usage report
    # @return [Hash] Summary statistics
    def report
      reload_entries
      
      return empty_report if @entries.empty?
      
      # Calculate totals
      total_tokens_in = @entries.sum { |e| e[:tokens_in] || 0 }
      total_tokens_out = @entries.sum { |e| e[:tokens_out] || 0 }
      total_cost = @entries.sum { |e| e[:cost] || 0 }
      
      # By model breakdown
      by_model = @entries.group_by { |e| e[:model] }
      model_stats = by_model.transform_values do |entries|
        {
          calls: entries.size,
          tokens_in: entries.sum { |e| e[:tokens_in] || 0 },
          tokens_out: entries.sum { |e| e[:tokens_out] || 0 },
          cost: entries.sum { |e| e[:cost] || 0 }
        }
      end
      
      # Recent activity
      recent = @entries.last(10)
      
      {
        summary: {
          total_calls: @entries.size,
          total_tokens: total_tokens_in + total_tokens_out,
          tokens_in: total_tokens_in,
          tokens_out: total_tokens_out,
          total_cost: total_cost.round(4),
          period: {
            from: @entries.first[:timestamp],
            to: @entries.last[:timestamp]
          }
        },
        by_model: model_stats,
        recent_activity: recent,
        efficiency: calculate_efficiency(total_tokens_in, total_tokens_out, total_cost)
      }
    end
    
    # Print formatted report
    def print_report
      data = report
      
      puts "\n" + "=" * 60
      puts "  MASTER Monitoring Report"
      puts "=" * 60
      
      if data[:summary][:total_calls].zero?
        puts "\n  No usage data recorded yet."
        puts
        return
      end
      
      puts "\n📊 Summary:"
      puts "  Total Calls:    #{data[:summary][:total_calls]}"
      puts "  Total Tokens:   #{format_number(data[:summary][:total_tokens])}"
      puts "    Input:        #{format_number(data[:summary][:tokens_in])}"
      puts "    Output:       #{format_number(data[:summary][:tokens_out])}"
      puts "  Total Cost:     $#{data[:summary][:total_cost].round(4)}"
      
      puts "\n🤖 By Model:"
      data[:by_model].each do |model, stats|
        puts "  #{model}:"
        puts "    Calls:  #{stats[:calls]}"
        puts "    Cost:   $#{stats[:cost].round(4)}"
      end
      
      puts "\n⚡ Efficiency:"
      puts "  Cost per 1K tokens: $#{data[:efficiency][:cost_per_1k].round(4)}"
      puts "  Avg tokens/call:    #{data[:efficiency][:avg_tokens_per_call]}"
      
      puts "\n" + "=" * 60
      puts
    end
    
    # Clear all logged data (use with caution)
    def clear_logs
      File.write(@log_path, '')
      @entries = []
    end
    
    private
    
    def default_log_path
      File.join(Paths.root, 'data', 'monitoring', 'usage.jsonl')
    end
    
    def ensure_log_directory
      FileUtils.mkdir_p(File.dirname(@log_path))
    end
    
    def create_entry(task:, model:, duration:, tokens_in:, tokens_out:)
      total_tokens = tokens_in + tokens_out
      cost = calculate_cost(model, tokens_in, tokens_out)
      
      entry = {
        timestamp: Time.now.iso8601,
        task: task,
        model: model,
        duration: duration.round(3),
        tokens_in: tokens_in,
        tokens_out: tokens_out,
        total_tokens: total_tokens,
        cost: cost.round(6)
      }
      
      @entries << entry
      @current_session[:total_tokens] += total_tokens
      @current_session[:total_cost] += cost
      @current_session[:task_count] += 1
      
      entry
    end
    
    def log_entry(entry)
      File.open(@log_path, 'a') do |f|
        f.puts JSON.generate(entry)
      end
    end
    
    def reload_entries
      return unless File.exist?(@log_path)
      
      @entries = File.readlines(@log_path).map do |line|
        JSON.parse(line.strip, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end.compact
    end
    
    def resolve_model(tier_or_model)
      # If it's a tier, resolve to model name
      tiers = {
        'cheap' => 'deepseek/deepseek-chat',
        'fast' => 'x-ai/grok-4-fast',
        'strong' => 'anthropic/claude-3.5-sonnet',
        'frontier' => 'anthropic/claude-opus-4',
        'code' => 'mistral/codestral-latest'
      }
      
      tiers[tier_or_model] || tier_or_model
    end
    
    def calculate_cost(model, tokens_in, tokens_out)
      pricing = PRICING[model]
      return 0.0 unless pricing
      
      # Cost per million tokens
      input_cost = (tokens_in / 1_000_000.0) * pricing[:input]
      output_cost = (tokens_out / 1_000_000.0) * pricing[:output]
      
      input_cost + output_cost
    end
    
    def estimate_tokens(text)
      return { input: 0, output: 0 } unless text.is_a?(String)
      
      # Simple character-based estimation
      tokens = text.length / CHARS_PER_TOKEN
      
      # Assume most is output
      {
        input: (tokens * 0.3).to_i,
        output: (tokens * 0.7).to_i
      }
    end
    
    def calculate_efficiency(tokens_in, tokens_out, total_cost)
      total_tokens = tokens_in + tokens_out
      
      {
        cost_per_1k: total_tokens.zero? ? 0 : (total_cost / total_tokens * 1000),
        avg_tokens_per_call: @entries.empty? ? 0 : total_tokens / @entries.size,
        input_output_ratio: tokens_in.zero? ? 0 : (tokens_out.to_f / tokens_in).round(2)
      }
    end
    
    def empty_report
      {
        summary: {
          total_calls: 0,
          total_tokens: 0,
          tokens_in: 0,
          tokens_out: 0,
          total_cost: 0.0
        },
        by_model: {},
        recent_activity: [],
        efficiency: {
          cost_per_1k: 0,
          avg_tokens_per_call: 0,
          input_output_ratio: 0
        }
      }
    end
    
    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
  end
end
