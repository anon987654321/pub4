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

    JSON_TYPE = "application/json"
    HTML_TYPE = "text/html"
    TEXT_TYPE = "text/plain"
    CT_HEADER = "content-type"
    AUTH_TOKEN = ENV["MASTER_TOKEN"] || SecureRandom.hex(16)
    VIEWS_DIR = File.join(File.dirname(__FILE__), "views")

    PORT_WAIT_ATTEMPTS = 10
    PORT_WAIT_DELAY    = 0.3
    PID_FILE           = File.join(MASTER.root, "var", "web.pid").freeze

    attr_reader :port, :output_queue

    def initialize(pipeline: nil, port: nil)
      kill_ghost_servers
      @pipeline = pipeline || Pipeline.new
      @port = port || find_port
      @output_queue = Thread::Queue.new
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
      PORT_WAIT_ATTEMPTS.times do
        sleep PORT_WAIT_DELAY
        break if port_open?(@port)
      end
      write_pid_file
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
      rescue StandardError => err
        warn "Falcon error: #{err.class}: #{err.message}"
      end
    end

    def kill_ghost_servers
      return unless File.exist?(PID_FILE)

      old_pid = File.read(PID_FILE).strip.to_i
      return if old_pid.zero? || old_pid == Process.pid

      begin
        Process.kill("TERM", old_pid)
        sleep 0.3
        Process.kill("KILL", old_pid) rescue nil
      rescue Errno::ESRCH
        # already gone
      ensure
        FileUtils.rm_f(PID_FILE)
      end
    rescue StandardError
      nil
    end

    def write_pid_file
      FileUtils.mkdir_p(File.dirname(PID_FILE))
      File.write(PID_FILE, Process.pid.to_s)
    rescue StandardError
      nil
    end

    def kill_port_users(port)
      pids = `lsof -ti:#{port} 2>/dev/null`.strip.split("\n").map(&:to_i).reject(&:zero?)
      pids.each do |pid|
        Process.kill("TERM", pid)
      rescue StandardError
        nil
      end
      sleep PORT_WAIT_DELAY unless pids.empty?
    rescue StandardError
      # best-effort
    end

    def port_open?(port)
      s = TCPSocket.new("127.0.0.1", port)
      s.close
      true
    rescue StandardError
      false
    end

    def build_app
      pipeline = @pipeline
      queue = @output_queue

      ->(env) {
        begin
          path = env["PATH_INFO"]
          method = env["REQUEST_METHOD"]

          unless path == "/health" || (method == "GET" && path == "/")
            token = env["HTTP_AUTHORIZATION"]&.delete_prefix("Bearer ")
            token ||= Rack::Utils.parse_query(env["QUERY_STRING"] || "")["token"]
            return [401, {}, ["Unauthorized"]] unless token == AUTH_TOKEN
          end

          case [method, path]
          when ["GET", "/"]
            html = read_view("cli.html").sub("window.MASTER_TOKEN||''", "window.MASTER_TOKEN||'#{AUTH_TOKEN}'")
            [200, { CT_HEADER => HTML_TYPE }, [html]]
          when ["GET", "/health"]
            [200, { CT_HEADER => JSON_TYPE }, [health_json]]
          when ["GET", "/poll"]
            handle_poll(queue)
          when ["GET", "/sse"]
            handle_sse(queue)
          when ["POST", "/chat"]
            handle_chat(env, pipeline, queue)
          when ["GET", "/metrics"]
            handle_metrics
          when ["POST", "/tts"]
            handle_tts(env)
          when ["GET", "/tts/stream"]
            handle_tts_stream(env)
          when ["GET", "/ws"]
            handle_websocket(env, pipeline)
          when ["GET", "/ws-test"]
            [200, { CT_HEADER => HTML_TYPE }, [read_view("ws_test.html")]]
          else
            serve_static_file(path)
          end
        rescue Errno::EPIPE, IOError
          [0, {}, []]
        end
      }
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
