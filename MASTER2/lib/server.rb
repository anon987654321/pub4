# frozen_string_literal: true

require "json"
require "socket"

module MASTER
  # Server - Multimodal web UI with Falcon
  class Server
    AUTH_TOKEN = ENV["MASTER_TOKEN"] || SecureRandom.hex(16)
    VIEWS_DIR = File.join(File.dirname(__FILE__), "views")

    attr_reader :port, :output_queue

    def initialize(pipeline: nil)
      @pipeline = pipeline || Pipeline.new
      @port = find_port
      @output_queue = Queue.new
      @running = false
    end

    def start
      return if @running

      @running = true
      Thread.new { run_server }
      sleep 0.3
      Dmesg.log("web0", message: "http://localhost:#{@port}") rescue nil
    end

    def stop
      @running = false
    end

    def url
      "http://localhost:#{@port}"
    end

    def running?
      @running
    end

    private

    def find_port
      return ENV["MASTER_PORT"].to_i if ENV["MASTER_PORT"]

      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close
      port
    rescue StandardError
      8080
    end

    def run_server
      require "falcon"
      require "async"
      require "async/http/endpoint"

      app = build_app

      Async do
        endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{@port}")
        server = Falcon::Server.new(Falcon::Server.middleware(app), endpoint)
        server.run
      end
    rescue LoadError
      run_webrick
    end

    def run_webrick
      require "webrick"

      server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: "127.0.0.1",
        Logger: WEBrick::Log.new("/dev/null"),
        AccessLog: [],
      )

      # Health endpoint - no auth required
      server.mount_proc("/health") { |_, res| res.body = health_json; res.content_type = "application/json" }

      # Protected endpoints
      server.mount_proc("/") do |req, res|
        next unless webrick_check_auth(req, res)
        res.body = read_view("cli.html")
        res.content_type = "text/html"
      end

      server.mount_proc("/poll") do |req, res|
        next unless webrick_check_auth(req, res)
        res.body = poll_json
        res.content_type = "application/json"
      end

      # Serve orb views - protected
      Dir.glob(File.join(VIEWS_DIR, "*.html")).each do |file|
        name = "/" + File.basename(file)
        server.mount_proc(name) do |req, res|
          next unless webrick_check_auth(req, res)
          res.body = File.read(file)
          res.content_type = "text/html"
        end
      end

      server.start
    end

    def webrick_check_auth(req, res)
      token = req["Authorization"]&.delete_prefix("Bearer ")
      unless token == AUTH_TOKEN
        res.status = 401
        res.body = "Unauthorized"
        return false
      end
      true
    end

    def build_app
      pipeline = @pipeline
      queue = @output_queue

      ->(env) {
        path = env["PATH_INFO"]
        method = env["REQUEST_METHOD"]

        # Auth check for all endpoints except /health
        unless path == "/health"
          token = env["HTTP_AUTHORIZATION"]&.delete_prefix("Bearer ")
          return [401, {}, ["Unauthorized"]] unless token == AUTH_TOKEN
        end

        case [method, path]
        when ["GET", "/"]
          [200, { "content-type" => "text/html" }, [read_view("cli.html")]]

        when ["GET", "/health"]
          [200, { "content-type" => "application/json" }, [health_json]]

        when ["GET", "/poll"]
          text = queue.empty? ? nil : (queue.pop(true) rescue nil)
          body = {
            text: text,
            tier: LLM.tier,
            budget: LLM.budget_remaining,
            version: VERSION,
          }.to_json
          [200, { "content-type" => "application/json" }, [body]]

        when ["POST", "/chat"]
          body = env["rack.input"].read
          data = JSON.parse(body) rescue {}
          message = data["message"].to_s.strip

          if message.empty?
            [400, { "content-type" => "application/json" }, ['{"error":"no message"}']]
          else
            Thread.new do
              result = pipeline.call({ text: message })
              output = result.ok? ? result.value[:rendered] : "Error: #{result.error}"
              queue.push(output)
            rescue StandardError => e
              queue.push("Error: #{e.message}")
            end
            [200, { "content-type" => "application/json" }, ['{"status":"processing"}']]
          end

        when ["GET", "/metrics"]
          metrics = {
            version: VERSION,
            tier: LLM.tier,
            budget_remaining: LLM.budget_remaining,
            models: LLM.models.size,
            tts: defined?(Audio) ? Audio.engine_status : "unavailable",
            self: defined?(SelfAwareness) ? SelfAwareness.summary : "unavailable",
          }.to_json
          [200, { "content-type" => "application/json" }, [metrics]]

        when ["POST", "/tts"]
          # Simple TTS endpoint - accepts JSON with text, returns audio
          body = env["rack.input"].read
          data = JSON.parse(body) rescue {}
          text = data["text"].to_s.strip

          return [400, { "content-type" => "application/json" }, ['{"error":"no text provided"}']] if text.empty?

          unless defined?(Speech) && Speech.respond_to?(:synthesize)
            return [501, { "content-type" => "application/json" }, ['{"error":"TTS not available"}']]
          end

          result = Speech.synthesize(text)
          if result.respond_to?(:ok?) && result.ok?
            audio_data = result.value[:audio] || result.value[:data]
            [200, { "content-type" => "audio/mpeg" }, [audio_data]]
          else
            error = result.respond_to?(:error) ? result.error : "TTS failed"
            [500, { "content-type" => "application/json" }, [{ error: error }.to_json]]
          end

        when ["GET", "/tts/stream"]
          # SSE endpoint for TTS streaming
          text = Rack::Utils.parse_query(env["QUERY_STRING"])["text"]
          return [400, {}, ["Missing text"]] unless text

          unless defined?(Web::OrbTTS)
            return [501, { "content-type" => "text/plain" }, ["TTS not available"]]
          end

          headers = {
            "Content-Type" => "text/event-stream",
            "Cache-Control" => "no-cache",
            "Connection" => "keep-alive",
          }
          body = Web::OrbTTS.stream(text)
          [200, headers, body]

        when ["GET", "/ws"]
          # WebSocket endpoint for real-time streaming
          handle_websocket(env, pipeline)

        when ["GET", "/ws-test"]
          # Test page for WebSocket functionality
          [200, { "content-type" => "text/html" }, [read_view("ws_test.html")]]

        else
          # Serve orb views and static files
          clean_path = path.delete_prefix("/")
          view_path = File.join(VIEWS_DIR, clean_path)

          if File.exist?(view_path) && File.file?(view_path)
            ext = File.extname(path)
            type = { ".html" => "text/html", ".js" => "application/javascript", ".css" => "text/css" }[ext] || "text/plain"
            [200, { "content-type" => type }, [File.read(view_path)]]
          else
            [404, { "content-type" => "text/plain" }, ["Not found"]]
          end
        end
      }
    end

    def handle_websocket(env, pipeline)
      # Try to load async-websocket, return 501 if not available
      begin
        require "async"
        require "async/websocket/adapters/rack"
      rescue LoadError
        Logging.warn("WebSocket", "async-websocket not available") rescue nil
        return [501, { "content-type" => "text/plain" }, ["WebSocket not available"]]
      end

      Async::WebSocket::Adapters::Rack.open(env, protocols: ["chat"]) do |connection|
        # WebSocket connection established
        while (message = connection.read)
          begin
            data = JSON.parse(message)
            
            if data["type"] == "chat"
              user_message = data["message"].to_s.strip
              
              if user_message.empty?
                connection.write({ type: "error", message: "Empty message" }.to_json)
                connection.flush
                next
              end

              # Process message through pipeline
              result = pipeline.call({ text: user_message })
              
              if result.ok?
                response_text = result.value[:rendered] || result.value[:text] || ""
                
                # Stream response in chunks (simulate streaming by sending full response)
                # In a real implementation, you'd hook into the LLM's streaming API
                connection.write({ type: "chunk", text: response_text }.to_json)
                connection.flush
                
                # Send done message with metadata
                meta = {
                  tier: LLM.tier,
                  budget: LLM.budget_remaining,
                  tokens: result.value[:tokens] || 0,
                  cost: result.value[:cost] || 0.0,
                }
                connection.write({ type: "done", meta: meta }.to_json)
                connection.flush
              else
                connection.write({ type: "error", message: result.error }.to_json)
                connection.flush
              end
            else
              connection.write({ type: "error", message: "Unknown message type" }.to_json)
              connection.flush
            end
          rescue JSON::ParserError
            connection.write({ type: "error", message: "Invalid JSON" }.to_json)
            connection.flush
          rescue StandardError => e
            Logging.warn("WebSocket", "Error: #{e.message}") rescue nil
            connection.write({ type: "error", message: e.message }.to_json)
            connection.flush
          end
        end
      rescue StandardError => e
        Logging.warn("WebSocket", "Connection error: #{e.message}") rescue nil
      end
      
      # Return nil to indicate WebSocket handled the request
      nil
    end

    def health_json
      { status: "ok", version: VERSION }.to_json
    end

    def poll_json
      text = @output_queue.empty? ? nil : (@output_queue.pop(true) rescue nil)
      { text: text, tier: LLM.tier, budget: LLM.budget_remaining }.to_json
    end

    def read_view(name)
      File.read(File.join(VIEWS_DIR, name))
    rescue StandardError
      "<!DOCTYPE html><html><body><h1>MASTER #{VERSION}</h1><p>View not found: #{name}</p></body></html>"
    end
  end
end
