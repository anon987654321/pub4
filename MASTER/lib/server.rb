# frozen_string_literal: true

require 'json'
require 'socket'

# This file consolidates three networking concerns:
# 1. Server - HTTP/WebSocket server with Falcon/WEBrick support
# 2. Web - Browser automation and web scraping utilities
# 3. BotManager - Multi-platform bot orchestration and message routing

module MASTER
  class Server
    PORT = ENV.fetch('PORT', 8080).to_i
    AUTH_TOKEN = ENV['MASTER_TOKEN'] || SecureRandom.hex(16)
    STARTUP_DELAY = 0.5
    
    attr_reader :output_queue
    attr_accessor :bot_manager

    def initialize(cli)
      @cli = cli
      @port = find_port
      @output_queue = Queue.new
      @persona = 'default'
      @running = false
      @rate_limiter = RateLimiter.new(requests_per_minute: 30)
      @bot_manager = nil
    end

    def start
      return if @running
      @running = true

      Thread.new { run_falcon }
      sleep STARTUP_DELAY
      puts "web0 at http0: port #{@port}"
    end

    def stop
      @running = false
    end

    def push(text)
      @output_queue.push(text) if text && !text.empty?
    end

    def url
      "http://#{ENV['HOST'] || 'localhost'}:#{@port}"
    end

    private

    def find_port
      # Reuse port on reload
      return ENV['MASTER_PORT'].to_i if ENV['MASTER_PORT']
      
      server = TCPServer.new('127.0.0.1', 0)
      port = server.addr[1]
      server.close
      port
    rescue StandardError
      PORT
    end

    def run_falcon
      require 'falcon'
      require 'async'
      require 'async/http/endpoint'

      app = build_app

      Async do
        endpoint = Async::HTTP::Endpoint.parse("http://0.0.0.0:#{@port}")
        server = Falcon::Server.new(Falcon::Server.middleware(app), endpoint)
        server.run
      end
    rescue LoadError
      # Fallback to simple socket server if Falcon unavailable
      run_simple_server
    end

    def run_simple_server
      require 'webrick'
      
      server = WEBrick::HTTPServer.new(
        Port: @port,
        Logger: WEBrick::Log.new('/dev/null'),
        AccessLog: []
      )

      mount_routes(server)
      server.start
    end

    def build_app
      cli = @cli
      queue = @output_queue
      persona_ref = -> { @persona }
      persona_set = ->(p) { @persona = p }
      cost_ref = -> { cli.llm.total_cost rescue 0.0 }
      rate_limiter = @rate_limiter

      ->(env) {
        path = env['PATH_INFO']
        method = env['REQUEST_METHOD']

        # Auth check (skip for static files and health)
        unless ['/', '/health'].include?(path) || path.match?(/\.\w+$/)
          token = env['HTTP_AUTHORIZATION']&.sub(/^Bearer\s+/, '') ||
                  env['HTTP_X_MASTER_TOKEN'] ||
                  Rack::Utils.parse_query(env['QUERY_STRING'])['token']
          unless token == AUTH_TOKEN
            next [401, { 'content-type' => 'application/json' }, ['{"error":"unauthorized"}']]
          end
        end

        # Rate limiting for chat/LLM endpoints
        if path == '/chat' && !rate_limiter.allow?
          next [429, { 'content-type' => 'application/json' }, 
                ['{"error":"rate limit exceeded, try again in 60s"}']]
        end

        case [method, path]
        when ['GET', '/']
          html = File.read(File.join(MASTER::LIB, 'views', 'cli.html'))
          [200, { 'content-type' => 'text/html' }, [html]]

        when ['GET', '/poll']
          text = queue.empty? ? nil : queue.pop(true) rescue nil
          llm_status = cli.llm.status rescue {}
          body = {
            text: text,
            persona: persona_ref.call,
            cost: cost_ref.call,
            model: llm_status[:model],
            tier: llm_status[:tier],
            last_tokens: llm_status[:last_tokens],
            last_cached: llm_status[:last_cached],
            connected: llm_status[:connected],
            requests: llm_status[:request_count]
          }.to_json
          [200, { 'content-type' => 'application/json' }, [body]]

        # Server-Sent Events endpoint for real-time updates
        when ['GET', '/events']
          begin
            require_relative 'sse_endpoint'
            sse = SSEEndpoint.new(cli.method(:broadcast))
            sse.handle(env)
          rescue LoadError => e
            [500, { 'content-type' => 'text/plain' }, ["SSE not available: #{e.message}"]]
          rescue => e
            [500, { 'content-type' => 'text/plain' }, ["SSE error: #{e.message}"]]
          end

        when ['POST', '/chat']
          body = env['rack.input'].read
          data = JSON.parse(body) rescue {}
          message = data['message'].to_s.strip

          if message.empty?
            [400, { 'content-type' => 'application/json' }, ['{"error":"no message"}']]
          else
            Thread.new do
              begin
                result = cli.process_input(message)
                queue.push(result) if result
              rescue => e
                queue.push("Error: #{e.message}")
              end
            end
            [200, { 'content-type' => 'application/json' }, ['{"status":"processing"}']]
          end

        when ['POST', '/persona']
          body = env['rack.input'].read
          data = JSON.parse(body) rescue {}
          if data['name']
            persona_set.call(data['name'])
            cli.llm.switch_persona(data['name'])
          end
          [200, { 'content-type' => 'application/json' }, [{ persona: persona_ref.call }.to_json]]

        when ['GET', '/token']
          # Display auth token (local access only)
          [200, { 'content-type' => 'application/json' }, [{ token: AUTH_TOKEN }.to_json]]

        when ['GET', '/health']
          [200, { 'content-type' => 'application/json' }, [{ status: 'ok', version: VERSION }.to_json]]

        when ['GET', '/metrics']
          metrics = {
            version: VERSION,
            uptime: (Time.now - BOOT_TIME).to_i,
            requests: rate_limiter.request_count,
            cost: cost_ref.call,
            audit_entries: (Audit.tail(1).size rescue 0),
            memory_mb: (`ps -o rss= -p #{Process.pid}`.to_i / 1024 rescue 0)
          }
          [200, { 'content-type' => 'application/json' }, [metrics.to_json]]

        when ['GET', '/ws']
          # WebSocket upgrade for Falcon
          if env['rack.hijack']
            begin
              require 'async/websocket/adapters/rack'
              
              Async::WebSocket::Adapters::Rack.open(env) do |connection|
                @ws_clients ||= []
                @ws_clients << connection
                
                while message = connection.read
                  # Handle incoming WebSocket messages if needed
                  data = JSON.parse(message.to_s) rescue {}
                  if data['message']
                    result = cli.process_input(data['message'])
                    connection.write({ text: result }.to_json) if result
                  end
                end
              ensure
                @ws_clients&.delete(connection)
              end
            rescue LoadError
              [501, { 'content-type' => 'text/plain' }, ['WebSocket not available']]
            end
          else
            [501, { 'content-type' => 'text/plain' }, ['WebSocket upgrade not supported']]
          end

        else
          # Check for webhook endpoints
          if method == 'POST' && path =~ %r{^/webhook/(\w+)$}
            platform = $1
            bot_manager = @bot_manager
            
            unless bot_manager
              next [503, { 'content-type' => 'application/json' }, 
                    ['{"error":"bot manager not initialized"}']]
            end
            
            # Rate limiting for webhooks
            unless rate_limiter.allow?
              next [429, { 'content-type' => 'application/json' }, 
                    ['{"error":"rate limit exceeded"}']]
            end
            
            body = env['rack.input'].read
            
            # Get signature from headers (platform-specific)
            signature = case platform
            when 'discord'
              {
                timestamp: env['HTTP_X_SIGNATURE_TIMESTAMP'],
                signature: env['HTTP_X_SIGNATURE_ED25519']
              }
            when 'telegram'
              env['HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN']
            when 'slack'
              {
                timestamp: env['HTTP_X_SLACK_REQUEST_TIMESTAMP'],
                signature: env['HTTP_X_SLACK_SIGNATURE']
              }
            when 'twitter'
              env['HTTP_X_TWITTER_WEBHOOKS_SIGNATURE']
            else
              nil
            end
            
            # Verify webhook signature
            adapter = bot_manager.platforms[platform.to_sym]
            if adapter && !adapter.verify_webhook(signature, body)
              Audit.log(
                command: "webhook_verification_failed #{platform}",
                type: :webhook,
                status: :error,
                output_length: 0,
                session_id: 'webhook'
              )
              next [401, { 'content-type' => 'application/json' }, 
                    ['{"error":"invalid signature"}']]
            end
            
            # Parse webhook data
            data = JSON.parse(body) rescue {}
            
            # Publish to event bus for async processing
            Thread.new do
              begin
                cli.llm.event_bus.publish(:webhook_received, {
                  platform: platform,
                  data: data,
                  timestamp: Time.now.to_i
                })
                
                Audit.log(
                  command: "webhook #{platform}",
                  type: :webhook,
                  status: :success,
                  output_length: body.length,
                  session_id: 'webhook'
                )
              rescue => e
                Audit.log(
                  command: "webhook_error #{platform}",
                  type: :webhook,
                  status: :error,
                  output_length: 0,
                  session_id: 'webhook'
                )
              end
            end
            
            # Return 200 OK immediately (async processing)
            [200, { 'content-type' => 'application/json' }, ['{"status":"ok"}']]
          else
            # Serve static files - check lib/views/ first, then root
            clean_path = path.delete_prefix('/')
            views_path = File.join(MASTER::LIB, 'views', clean_path)
            root_path = File.join(MASTER::ROOT, clean_path)
            
            file_path = if File.exist?(views_path) && File.file?(views_path)
              views_path
            elsif File.exist?(root_path) && File.file?(root_path)
              root_path
            else
              nil
            end
            
            if file_path
              ext = File.extname(path)
              type = { '.html' => 'text/html', '.js' => 'application/javascript', '.css' => 'text/css', '.ico' => 'image/x-icon', '.png' => 'image/png' }[ext] || 'application/octet-stream'
              [200, { 'content-type' => type }, [File.read(file_path)]]
            else
              [404, { 'content-type' => 'text/plain' }, ["Not found: #{path}"]]
            end
          end
        end
      }
    end

    def mount_routes(server)
      html_path = File.join(MASTER::LIB, 'views', 'cli.html')

      server.mount_proc('/') do |req, res|
        res.content_type = 'text/html'
        res.body = File.read(html_path)
      end

      server.mount_proc('/poll') do |req, res|
        res.content_type = 'application/json'
        text = @output_queue.empty? ? nil : @output_queue.pop(true) rescue nil
        llm_status = @cli.llm.status rescue {}
        res.body = {
          text: text,
          persona: @persona,
          cost: (@cli.llm.total_cost rescue 0.0),
          model: llm_status[:model],
          tier: llm_status[:tier],
          last_tokens: llm_status[:last_tokens],
          last_cached: llm_status[:last_cached],
          connected: llm_status[:connected],
          requests: llm_status[:request_count]
        }.to_json
      end

      server.mount_proc('/chat') do |req, res|
        res.content_type = 'application/json'
        data = JSON.parse(req.body) rescue {}
        message = data['message'].to_s.strip

        if message.empty?
          res.body = '{"error":"no message"}'
        else
          Thread.new do
            result = @cli.process_input(message)
            @output_queue.push(result) if result
          end
          res.body = '{"status":"processing"}'
        end
      end

      server.mount_proc('/health') do |req, res|
        res.content_type = 'application/json'
        res.body = { status: 'ok', version: VERSION }.to_json
      end
    end
  end

  # Simple sliding window rate limiter
  class RateLimiter
    def initialize(requests_per_minute: 30)
      @limit = requests_per_minute
      @window = 60.0
      @requests = []
      @mutex = Mutex.new
      @total = 0
    end

    def allow?
      @mutex.synchronize do
        now = Time.now.to_f
        @requests.reject! { |t| t < now - @window }
        return false if @requests.size >= @limit
        @requests << now
        @total += 1
        true
      end
    end

    def request_count
      @total
    end
  end

  # Web browsing and automation utilities
  module Web
    MAX_PREVIEW_LENGTH = 2000
    BROWSER_LOAD_DELAY = 2
    CURL_TIMEOUT = 10
    MAX_HTML_FOR_DISCOVERY = 5000

    class << self
      def browse(url)
        return "Error: empty URL" if url.nil? || url.strip.empty?
        
        # Try Ferrum first, fall back to curl
        ferrum_browse(url)
      rescue LoadError
        curl_browse(url)
      rescue => e
        "Error: #{e.message}"
      end

      # Dynamic CSS selector discovery using LLM + vision
      # Instead of hardcoding selectors that break, ask LLM to find them
      def discover_selector(url, action, llm = nil)
        require 'ferrum'
        
        browser = Ferrum::Browser.new(headless: true)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        html_snippet = page.body[0..MAX_HTML_FOR_DISCOVERY]
        screenshot_b64 = page.screenshot(format: :png, encoding: :base64)
        
        browser.quit

        prompt = <<~PROMPT
          Analyze this webpage to find the CSS selector for: #{action}
          
          HTML (truncated):
          #{html_snippet}
          
          Return ONLY the CSS selector, nothing else.
          Example: button.submit-btn, input#search, div.login-form
        PROMPT

        # Use vision if available, otherwise just HTML
        if llm&.respond_to?(:chat_with_image)
          result = llm.chat_with_image(prompt, screenshot_b64)
        elsif llm
          result = llm.chat(prompt)
          result = result.value if result.respond_to?(:value)
        else
          result = MASTER::LLM.new.chat(prompt)
          result = result.value if result.respond_to?(:value)
        end

        # Clean up response - extract just the selector
        selector = result.to_s.strip.split("\n").first.to_s.strip
        selector.gsub(/^['"`]|['"`]$/, '') # Remove quotes
      rescue => e
        nil
      end

      # Click an element discovered dynamically
      def click_discovered(url, action, llm = nil)
        require 'ferrum'

        selector = discover_selector(url, action, llm)
        return { success: false, error: "Could not find selector for: #{action}" } unless selector

        browser = Ferrum::Browser.new(headless: true)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        element = page.at_css(selector)
        return { success: false, error: "Element not found: #{selector}" } unless element

        element.click
        sleep 1
        
        result_html = page.body[0..MAX_PREVIEW_LENGTH]
        browser.quit

        { success: true, selector: selector, result: result_html }
      rescue => e
        { success: false, error: e.message }
      end

      # Fill a form field discovered dynamically  
      def fill_discovered(url, action, value, llm = nil)
        require 'ferrum'

        selector = discover_selector(url, action, llm)
        return { success: false, error: "Could not find selector for: #{action}" } unless selector

        browser = Ferrum::Browser.new(headless: true)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        element = page.at_css(selector)
        return { success: false, error: "Element not found: #{selector}" } unless element

        element.focus.type(value)
        sleep 0.5

        browser.quit
        { success: true, selector: selector, filled: value }
      rescue => e
        { success: false, error: e.message }
      end

      private

      def ferrum_browse(url)
        require 'ferrum'

        browser = Ferrum::Browser.new(headless: true)
        page = browser.create_page
        page.go_to(url)
        sleep BROWSER_LOAD_DELAY

        text = page.body_text
        screenshot_path = File.join(MASTER::ROOT, 'var', 'screenshots', "#{Time.now.to_i}.png")
        FileUtils.mkdir_p(File.dirname(screenshot_path))
        page.screenshot(path: screenshot_path)

        browser.quit

        "#{url}\n\n#{text[0..MAX_PREVIEW_LENGTH]}"
      end

      def curl_browse(url)
        # Try ftp first on OpenBSD (native, better TLS), fallback to curl
        html = if RUBY_PLATFORM.include?('openbsd')
          `ftp -o - "#{url}" 2>/dev/null`
        else
          `curl -sL --max-time #{CURL_TIMEOUT} "#{url}" 2>/dev/null`
        end
        
        # Fallback if first method fails
        if html.empty?
          html = `curl -sLk --max-time #{CURL_TIMEOUT} "#{url}" 2>/dev/null`
        end
        
        return "Failed to fetch: #{url}" if html.empty?

        # Strip HTML tags for plain text
        text = html.gsub(/<script[^>]*>.*?<\/script>/mi, '')
                   .gsub(/<style[^>]*>.*?<\/style>/mi, '')
                   .gsub(/<[^>]+>/, ' ')
                   .gsub(/\s+/, ' ')
                   .strip

        "#{url}\n\n#{text[0..MAX_PREVIEW_LENGTH]}"
      end
    end

    # GitHub search helper
    module GitHub
      SEARCH_URL = 'https://github.com/search'

      class << self
        def search_repos(query, sort: 'stars', limit: 10)
          require 'ferrum'
          require 'uri'

          url = "#{SEARCH_URL}?q=#{URI.encode_www_form_component(query)}&type=repositories&s=#{sort}&o=desc"
          
          browser = Ferrum::Browser.new(headless: true)
          page = browser.create_page
          page.go_to(url)
          sleep 3  # GitHub is slow

          # Extract repo links
          repos = page.css('a[href*="/"][data-testid="results-list"] a, .repo-list-item a, div[data-testid] a').map do |link|
            href = link.attribute('href')
            next unless href&.match?(%r{^/[^/]+/[^/]+$})
            "https://github.com#{href}"
          end.compact.uniq.first(limit)

          # If CSS selectors don't work, try text extraction
          if repos.empty?
            text = page.body_text
            repos = text.scan(%r{github\.com/([a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+)}).flatten.uniq.first(limit).map { |r| "https://github.com/#{r}" }
          end

          browser.quit
          repos
        rescue => e
          ["Error: #{e.message}"]
        end

        def trending(language: nil, since: 'daily')
          require 'ferrum'

          url = "https://github.com/trending"
          url += "/#{language}" if language
          url += "?since=#{since}"

          browser = Ferrum::Browser.new(headless: true)
          page = browser.create_page
          page.go_to(url)
          sleep 2

          text = page.body_text
          repos = text.scan(%r{([a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+)\s+\d+}).flatten.uniq.first(20)
          
          browser.quit
          repos.map { |r| "https://github.com/#{r}" }
        rescue => e
          ["Error: #{e.message}"]
        end
      end
    end
  end

  # BotManager orchestrates multiple platform adapters
  # Routes messages between platforms and CLI
  class BotManager
    attr_reader :platforms, :event_bus, :cli

    def initialize(cli, event_bus, config = {})
      @cli = cli
      @event_bus = event_bus
      @config = config
      @platforms = {}
      @running = false
      @message_queue = Queue.new
      @mutex = Mutex.new
      
      setup_event_handlers
    end

    # Register a platform adapter
    def register_platform(name, adapter)
      @mutex.synchronize do
        @platforms[name] = adapter
      end
    end

    # Start all enabled platforms
    def start_all
      return if @running
      @running = true

      @platforms.each do |name, adapter|
        begin
          adapter.start
          puts "#{MASTER::CLI::ICON_OK} #{name} started"
        rescue => e
          puts "#{MASTER::CLI::ICON_ERR} #{name} failed: #{e.message}"
          MASTER::Audit.log(
            command: "start #{name}",
            type: :bot_startup,
            status: :error,
            output_length: 0,
            session_id: 'bot_manager'
          )
        end
      end

      # Start message processor thread
      start_message_processor
      
      emit(:bot_manager_started, { platforms: @platforms.keys })
    end

    # Stop all platforms
    def stop_all
      @running = false
      
      @platforms.each do |name, adapter|
        begin
          adapter.stop
          puts "#{MASTER::CLI::ICON_OK} #{name} stopped"
        rescue => e
          puts "#{MASTER::CLI::ICON_WARN} #{name} stop error: #{e.message}"
        end
      end
      
      emit(:bot_manager_stopped, {})
    end

    # Send message to specific platform
    def send_to_platform(platform_name, channel_id, text)
      adapter = @platforms[platform_name.to_sym]
      raise "Platform #{platform_name} not found" unless adapter
      
      adapter.handle_outgoing(channel_id, text)
    end

    # Broadcast message to all platforms
    def broadcast(text, exclude: [])
      @platforms.each do |name, adapter|
        next if exclude.include?(name)
        
        # Get default channel from config
        channels = @config.dig(name, :default_channels) || []
        channels.each do |channel_id|
          begin
            send_to_platform(name, channel_id, text)
          rescue => e
            emit(:broadcast_error, {
              platform: name,
              channel: channel_id,
              error: e.message
            })
          end
        end
      end
    end

    # Get platform statistics
    def stats
      {
        platforms: @platforms.keys,
        running: @running,
        message_queue_size: @message_queue.size,
        event_count: @event_bus.event_count
      }
    end

    private

    def setup_event_handlers
      # Subscribe to platform events
      @event_bus.subscribe(:message_received) do |event|
        handle_incoming_message(event)
      end

      @event_bus.subscribe(:platform_error) do |event|
        handle_platform_error(event)
      end

      @event_bus.subscribe(:message_failed) do |event|
        handle_message_failure(event)
      end

      @event_bus.subscribe(:rate_limited) do |event|
        handle_rate_limit(event)
      end
    end

    def handle_incoming_message(event)
      data = event.data
      
      # Log the incoming message
      MASTER::Audit.log(
        command: "incoming from #{data[:platform]}/#{data[:channel_id]}",
        type: :bot_incoming,
        status: :success,
        output_length: data[:text].length,
        session_id: 'bot_manager'
      )
      
      # Queue message for processing
      @message_queue.push({
        platform: data[:platform],
        channel_id: data[:channel_id],
        user_id: data[:user_id],
        text: data[:text],
        timestamp: data[:timestamp]
      })
    end

    def handle_platform_error(event)
      data = event.data
      puts "#{MASTER::CLI::ICON_ERR} #{data[:platform]} error: #{data[:error]}"
      
      MASTER::Audit.log(
        command: "platform_error #{data[:platform]}",
        type: :bot_error,
        status: :error,
        output_length: 0,
        session_id: 'bot_manager'
      )
    end

    def handle_message_failure(event)
      data = event.data
      
      # Implement dead letter queue for failed messages
      dead_letter_file = File.join(MASTER::Paths.var, 'bot_dead_letter.log')
      File.open(dead_letter_file, 'a') do |f|
        f.puts({
          timestamp: Time.now.to_i,
          platform: data[:platform],
          channel: data[:channel_id],
          error: data[:error]
        }.to_json)
      end
    end

    def handle_rate_limit(event)
      data = event.data
      puts "#{MASTER::CLI::ICON_WARN} #{data[:platform]} rate limited, reset at #{data[:reset_at]}"
    end

    def start_message_processor
      Thread.new do
        while @running
          begin
            # Wait for message with timeout (non-blocking pop)
            message = @message_queue.pop(true) # true = non-blocking
            process_message(message)
          rescue ThreadError
            # Queue empty, sleep briefly
            sleep 0.1
          rescue => e
            puts "#{MASTER::CLI::ICON_ERR} Message processor error: #{e.message}"
          end
        end
      end
    end

    def process_message(message)
      # Format input for CLI
      input = message[:text]
      
      # Process through CLI
      result = @cli.process_input(input)
      
      return unless result
      
      # Send response back to the originating platform
      response_text = format_response(result)
      
      send_to_platform(
        message[:platform],
        message[:channel_id],
        response_text
      )
    rescue => e
      # Send error message back
      error_text = "#{MASTER::CLI::ICON_ERR} Error: #{e.message}"
      
      begin
        send_to_platform(
          message[:platform],
          message[:channel_id],
          error_text
        )
      rescue
        # Give up if we can't send error
      end
    end

    def format_response(result)
      # Format CLI response for social media platforms
      # Remove excessive whitespace and ANSI codes
      text = result.to_s
      text = text.gsub(/\e\[[0-9;]*m/, '') # Remove ANSI codes
      text = text.strip
      
      # Truncate if too long (most platforms have limits)
      max_length = @config.dig(:limits, :max_message_length) || 2000
      if text.length > max_length
        text = text[0...max_length - 3] + '...'
      end
      
      text
    end

    def emit(event_type, data)
      @event_bus.publish(event_type, data)
    end
  end
end
