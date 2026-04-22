# frozen_string_literal: true

require "json"
require "socket"
require "rack/utils"
require_relative "server/handlers"
require_relative "server/websocket"

module MASTER
  # Server - Multimodal web UI with Falcon
  class Server
    include Handlers
    include WebSocket

    JSON_TYPE  = "application/json"
    HTML_TYPE  = "text/html"
    TEXT_TYPE  = "text/plain"
    CT_HEADER  = "content-type"
    AUTH_TOKEN = ENV["MASTER_TOKEN"] || SecureRandom.hex(16)
    VIEWS_DIR  = File.join(File.dirname(__FILE__), "views")
    DILLA_PATH = File.expand_path("../../dilla.html", File.dirname(__FILE__))

    # Security headers appended to every response
    SECURITY_HEADERS = {
      "x-frame-options"          => "DENY",
      "x-content-type-options"   => "nosniff",
      "content-security-policy"  =>
        "default-src 'self'; " \
        "script-src 'self' 'unsafe-inline'; " \
        "style-src 'self' 'unsafe-inline'; " \
        "media-src 'self' blob: data:; " \
        "connect-src 'self' ws: wss:;",
    }.freeze

    MAX_BODY_BYTES   = 65_536  # 64KB input cap
    RATE_LIMIT_RPM   = 60      # max requests per minute per IP
    RATE_WINDOW_SECS = 60

    attr_reader :port, :output_queue

    def initialize(pipeline: nil, port: nil)
      @pipeline = pipeline || Pipeline.new
      @port = port || find_port
      @output_queue = Thread::Queue.new
      @sessions = {}
      @sessions_lock = Mutex.new
      @rate_counts = Hash.new { |h, k| h[k] = [] }
      @rate_mutex = Mutex.new
      @running = false
    end

    def start
      return if @running

      kill_port_users(@port)
      require "falcon"
      require "async"
      require "async/http/endpoint"
      @running = true
      @app = build_app
      @server_thread = Thread.new { run_server }
      # Wait for Falcon to bind
      10.times do
        sleep 0.3
        break if port_open?(@port)
      end
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
      Async do |_task|
        endpoint = Async::HTTP::Endpoint.parse("http://0.0.0.0:#{@port}")
        server = Falcon::Server.new(Falcon::Server.middleware(@app), endpoint)
        server.run
      rescue StandardError => e
        warn "Falcon error: #{e.class}: #{e.message}"
      end
    end

    def kill_port_users(port)
      pids = openbsd_port_pids(port)
      pids.each do |pid|
        Process.kill("TERM", pid)
      rescue StandardError
        nil
      end
      sleep 0.3 unless pids.empty?
    rescue StandardError
      # best-effort
    end

    # OpenBSD-native port occupant detection.
    # Falls back to lsof for Linux/macOS development environments.
    def openbsd_port_pids(port)
      if File.exist?("/usr/bin/fstat")
        # OpenBSD: fstat lists open files; awk extracts PIDs listening on our port
        `fstat 2>/dev/null | awk '$NF == "#{port.to_i}" {print $3}'`
          .strip.split("\n").map(&:to_i).reject(&:zero?)
      else
        `lsof -ti:#{port} 2>/dev/null`.strip.split("\n").map(&:to_i).reject(&:zero?)
      end
    end

    def port_open?(port)
      s = TCPSocket.new("127.0.0.1", port)
      s.close
      true
    rescue StandardError
      false
    end

    def build_app
      pipeline    = @pipeline
      queue       = @output_queue
      sessions    = @sessions
      lock        = @sessions_lock
      rate_counts = @rate_counts
      rate_mutex  = @rate_mutex

      ->(env) {
        path   = env["PATH_INFO"]
        method = env["REQUEST_METHOD"]

        # Auth check — /health is public, all other routes require token
        unless path == "/health"
          token = env["HTTP_AUTHORIZATION"]&.delete_prefix("Bearer ")
          token ||= Rack::Utils.parse_query(env["QUERY_STRING"] || "")["token"]
          unless token == AUTH_TOKEN
            return with_security_headers([401, { CT_HEADER => TEXT_TYPE }, ["Unauthorized"]])
          end
        end

        # Rate limiting on /chat (per REMOTE_ADDR)
        if path == "/chat" && method == "POST"
          ip  = env["REMOTE_ADDR"] || "unknown"
          now = Time.now.to_f
          ok  = rate_mutex.synchronize do
            rate_counts[ip].reject! { |t| now - t > RATE_WINDOW_SECS }
            if rate_counts[ip].size >= RATE_LIMIT_RPM
              false
            else
              rate_counts[ip] << now
              true
            end
          end
          unless ok
            return with_security_headers([429, { CT_HEADER => TEXT_TYPE }, ["Too Many Requests"]])
          end
        end

        response = case [method, path]
                   when ["GET", "/"]
                     html = read_view("cli.html").sub("window.MASTER_TOKEN||''", "window.MASTER_TOKEN||'#{AUTH_TOKEN}'")
                     [200, { CT_HEADER => HTML_TYPE }, [html]]
                   when ["GET", "/health"]
                     [200, { CT_HEADER => JSON_TYPE }, [health_json]]
                   when ["GET", "/poll"]
                     handle_poll(queue)
                   when ["POST", "/chat"]
                     handle_chat(env, pipeline, queue, sessions, lock)
                   when ["GET", "/metrics"]
                     handle_metrics
                   when ["POST", "/tts"]
                     handle_tts(env)
                   when ["GET", "/tts/stream"]
                     handle_tts_stream(env)
                   when ["GET", "/ws"]
                     handle_websocket(env, pipeline, sessions, lock)
                   when ["GET", "/ws-test"]
                     [200, { CT_HEADER => HTML_TYPE }, [read_view("ws_test.html")]]
                   when ["GET", "/dilla"]
                     serve_dilla
                   when ["GET", %r{\A/assets/}]
                     serve_asset(path)
                   else
                     serve_static_file(path)
                   end

        with_security_headers(response)
      }
    end

    def with_security_headers(response)
      status, headers, body = response
      SECURITY_HEADERS.each { |k, v| headers[k] ||= v }
      [status, headers, body]
    end

    def serve_dilla
      if File.exist?(DILLA_PATH)
        [200, { CT_HEADER => HTML_TYPE }, [File.read(DILLA_PATH)]]
      else
        [404, { CT_HEADER => TEXT_TYPE }, ["dilla.html not found at #{DILLA_PATH}"]]
      end
    end

    def serve_asset(path)
      # Serve assets from pub4/assets/ directory (dilla deps: tone.js etc.)
      assets_dir = File.expand_path("../../assets", File.dirname(__FILE__))
      filename   = File.basename(path)
      asset_path = File.join(assets_dir, filename)

      # Path traversal guard
      unless File.expand_path(asset_path).start_with?(assets_dir)
        return [403, { CT_HEADER => TEXT_TYPE }, ["Forbidden"]]
      end

      if File.exist?(asset_path) && File.file?(asset_path)
        ext  = File.extname(filename)
        type = { ".js" => "application/javascript", ".css" => "text/css",
                 ".wasm" => "application/wasm" }[ext] || TEXT_TYPE
        [200, { CT_HEADER => type }, [File.read(asset_path)]]
      else
        [404, { CT_HEADER => TEXT_TYPE }, ["Asset not found: #{filename}"]]
      end
    end

    def health_json
      { status: "ok", version: VERSION }.to_json
    end

    def poll_json
      text = begin; @output_queue.pop(true) unless @output_queue.empty?; rescue ThreadError; nil; end
      { text: text, tier: LLM.tier, budget: "unlimited" }.to_json
    end

    def read_view(name)
      File.read(File.join(VIEWS_DIR, name))
    rescue StandardError
      "<!DOCTYPE html><html><body><h1>MASTER #{VERSION}</h1><p>View not found: #{name}</p></body></html>"
    end
  end
end
