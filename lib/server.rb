# frozen_string_literal: true

require 'json'
require 'socket'

module MASTER
  class Server
    PORT = ENV.fetch('PORT', 8080).to_i
    AUTH_TOKEN = ENV['MASTER_TOKEN'] || SecureRandom.hex(16)
    
    attr_reader :output_queue

    def initialize(cli)
      @cli = cli
      @port = find_port
      @output_queue = Queue.new
      @persona = 'default'
      @running = false
      @rate_limiter = RateLimiter.new(requests_per_minute: 30)
    end

    def start
      return if @running
      @running = true

      Thread.new { run_falcon }
      sleep 0.5 # Let server start
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
    rescue
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
          body = { text: text, persona: persona_ref.call, cost: cost_ref.call }.to_json
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
      }
    end

    def mount_routes(server)
      html_path = File.join(MASTER::ROOT, 'cli.html')

      server.mount_proc('/') do |req, res|
        res.content_type = 'text/html'
        res.body = File.read(html_path)
      end

      server.mount_proc('/poll') do |req, res|
        res.content_type = 'application/json'
        text = @output_queue.empty? ? nil : @output_queue.pop(true) rescue nil
        res.body = { text: text, persona: @persona }.to_json
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
end
