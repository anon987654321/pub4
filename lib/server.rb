# frozen_string_literal: true

require 'json'
require 'socket'

module MASTER
  class Server
    PORT = ENV.fetch('PORT', 8080).to_i
    
    attr_reader :output_queue

    def initialize(cli)
      @cli = cli
      @port = find_port
      @output_queue = Queue.new
      @persona = 'default'
      @running = false
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

      ->(env) {
        path = env['PATH_INFO']
        method = env['REQUEST_METHOD']

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
              result = cli.process_input(message)
              queue.push(result) if result
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

        when ['GET', '/health']
          [200, { 'content-type' => 'application/json' }, [{ status: 'ok', version: VERSION }.to_json]]

        else
          # Serve static files
          file_path = File.join(MASTER::ROOT, path)
          if File.exist?(file_path) && File.file?(file_path)
            ext = File.extname(path)
            type = { '.html' => 'text/html', '.js' => 'application/javascript', '.css' => 'text/css' }[ext] || 'application/octet-stream'
            [200, { 'content-type' => type }, [File.read(file_path)]]
          else
            [404, { 'content-type' => 'text/plain' }, ['Not found']]
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
end
