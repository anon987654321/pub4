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
    JSON_TYPE = "application/json".freeze
    HTML_TYPE = "text/html".freeze
    TEXT_TYPE = "text/plain".freeze
    CT_HEADER = "content-type".freeze
    AUTH_TOKEN = ENV["MASTER_TOKEN"] || SecureRandom.hex(16)
    VIEWS_DIR = File.join(File.dirname(__FILE__), "views")

    attr_reader :port, :output_queue

    def initialize(pipeline: nil, port: nil)
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
    rescue StandardError => e
      8080
    end

    def run_server
      Async do |task|
        endpoint = Async::HTTP::Endpoint.parse("http://0.0.0.0:#{@port}")
        server = Falcon::Server.new(Falcon::Server.middleware(@app), endpoint)
        server.run
      rescue => e
        $stderr.puts "Falcon error: #{e.class}: #{e.message}"
      end
    end

    def kill_port_users(port)
      pids = `lsof -ti:#{port} 2>/dev/null`.strip.split("\n").map(&:to_i).reject(&:zero?)
      pids.each { |pid| Process.kill("TERM", pid) rescue nil }
      sleep 0.3 unless pids.empty?
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
        path = env["PATH_INFO"]
        method = env["REQUEST_METHOD"]

        unless path == "/health"
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
      }
    end

    def health_json
      { status: "ok", version: VERSION }.to_json
    end

    def poll_json
      text = begin; @output_queue.pop(true) unless @output_queue.empty?; rescue ThreadError; nil; end
      { text: text, tier: LLM.tier, budget: LLM.budget_remaining }.to_json
    end

    def read_view(name)
      File.read(File.join(VIEWS_DIR, name))
    rescue StandardError => e
      "<!DOCTYPE html><html><body><h1>MASTER #{VERSION}</h1><p>View not found: #{name}</p></body></html>"
    end
  end
end
