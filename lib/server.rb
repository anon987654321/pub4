# frozen_string_literal: true
require "json"

module Master
  class Server
    PORT = ENV.fetch("MASTER_PORT", 8080).to_i
    HOST = ENV.fetch("MASTER_HOST", "127.0.0.1")

    def initialize
      @principles = Principle.load_all
      @llm = LLM.new
      @engine = Engine.new(principles: @principles, llm: @llm)
    end

    def call(env)
      request = Rack::Request.new(env)
      path = request.path_info
      method = request.request_method

      case [method, path]
      when ["GET", "/"]
        json_response(200, { name: "MASTER", version: VERSION, status: "ok" })
      when ["GET", "/health"]
        json_response(200, { status: "ok", principles: @principles.size })
      when ["GET", "/principles"]
        json_response(200, { principles: @principles.map(&:to_h) })
      when ["POST", "/scan"]
        handle_scan(request)
      when ["POST", "/ask"]
        handle_ask(request)
      else
        json_response(404, { error: "Not found" })
      end
    rescue => e
      json_response(500, { error: e.message })
    end

    private

    def handle_scan(request)
      body = JSON.parse(request.body.read)
      path = body["path"]
      return json_response(400, { error: "path required" }) unless path
      return json_response(404, { error: "file not found" }) unless File.exist?(path)

      result = @engine.scan(path)
      if result.ok?
        json_response(200, result.value)
      else
        json_response(400, { error: result.error })
      end
    end

    def handle_ask(request)
      body = JSON.parse(request.body.read)
      prompt = body["prompt"]
      tier = (body["tier"] || "fast").to_sym
      return json_response(400, { error: "prompt required" }) unless prompt

      result = @llm.ask(prompt, tier: tier)
      if result.ok?
        json_response(200, { response: result.value })
      else
        json_response(400, { error: result.error })
      end
    end

    def json_response(status, data)
      [status, { "Content-Type" => "application/json" }, [data.to_json]]
    end

    def self.start
      puts ">> master #{VERSION} (server)"
      puts "boot> http://#{HOST}:#{PORT}"
      
      # Check for Falcon, fall back to WEBrick
      begin
        require "falcon"
        run_falcon
      rescue LoadError
        run_webrick
      end
    end

    def self.run_falcon
      require "falcon/command/serve"
      require "async"
      
      app = Rack::Builder.new { run Master::Server.new }
      
      Async do
        endpoint = Async::HTTP::Endpoint.parse("http://#{HOST}:#{PORT}")
        server = Falcon::Server.new(Falcon::Server.middleware(app), endpoint)
        server.run
      end
    end

    def self.run_webrick
      require "webrick"
      require "rack"
      
      Rack::Handler::WEBrick.run(
        new,
        Host: HOST,
        Port: PORT,
        Logger: WEBrick::Log.new("/dev/null"),
        AccessLog: []
      )
    end
  end
end
