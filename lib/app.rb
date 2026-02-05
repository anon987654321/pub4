# frozen_string_literal: true
require "json"
require "time"

module MASTER
  class App
    START_TIME = Time.now

    def initialize
      @principles = Principle.load_all
      @llm = LLM.new(principles: @principles)
      @engine = Engine.new(principles: @principles, llm: @llm)
    end

    def call(env)
      request = Rack::Request.new(env)
      path = request.path_info
      method = request.request_method

      case [method, path]
      when ["GET", "/health"]
        handle_health(request)
      when ["POST", "/analyze"]
        handle_analyze(request)
      when ["POST", "/chat"]
        handle_chat(request)
      when ["GET", "/principles"]
        handle_principles(request)
      when ["GET", "/"]
        handle_root(request)
      else
        # Try serving static files
        if method == "GET" && path.start_with?("/")
          serve_static(path)
        else
          json_response(404, { error: "Not found" })
        end
      end
    rescue => e
      json_response(500, { error: e.message, backtrace: e.backtrace.first(5) })
    end

    private

    def handle_health(_request)
      uptime_seconds = (Time.now - START_TIME).to_i
      json_response(200, {
        status: "ok",
        uptime: uptime_seconds,
        version: MASTER::VERSION,
        principles_loaded: @principles.size
      })
    end

    def handle_analyze(request)
      body = parse_json_body(request)
      return json_response(400, { error: "Invalid JSON" }) unless body

      code = body["code"]
      file = body["file"]
      profile = body["profile"] || "fast"

      return json_response(400, { error: "code is required" }) unless code

      # If streaming is requested, use SSE
      if request.env["HTTP_ACCEPT"]&.include?("text/event-stream")
        return stream_analyze(code, file, profile)
      end

      # Non-streaming analysis
      result = analyze_code(code, file, profile.to_sym)
      json_response(200, result)
    end

    def handle_chat(request)
      body = parse_json_body(request)
      return json_response(400, { error: "Invalid JSON" }) unless body

      prompt = body["prompt"]
      tier = (body["tier"] || "fast").to_sym

      return json_response(400, { error: "prompt is required" }) unless prompt

      # Chat endpoint always streams using SSE
      stream_chat(prompt, tier)
    end

    def handle_principles(_request)
      json_response(200, {
        principles: @principles.map(&:to_h)
      })
    end

    def handle_root(_request)
      # Serve index.html from public directory if exists
      public_dir = File.join(MASTER.root, "public")
      index_path = File.join(public_dir, "index.html")

      if File.exist?(index_path)
        [200, { "Content-Type" => "text/html" }, [File.read(index_path)]]
      else
        json_response(200, {
          name: "MASTER",
          version: MASTER::VERSION,
          description: "Constitutional AI Code Enforcer",
          endpoints: {
            health: "GET /health",
            analyze: "POST /analyze",
            chat: "POST /chat (SSE)",
            principles: "GET /principles"
          }
        })
      end
    end

    def serve_static(path)
      public_dir = File.join(MASTER.root, "public")
      file_path = File.join(public_dir, path == "/" ? "index.html" : path)

      # Security: prevent directory traversal
      return json_response(403, { error: "Forbidden" }) unless file_path.start_with?(public_dir)
      return json_response(404, { error: "Not found" }) unless File.exist?(file_path)
      return json_response(403, { error: "Not a file" }) unless File.file?(file_path)

      content_type = mime_type(file_path)
      [200, { "Content-Type" => content_type }, [File.read(file_path)]]
    rescue => e
      json_response(500, { error: e.message })
    end

    def stream_analyze(code, file, profile)
      [
        200,
        {
          "Content-Type" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "Connection" => "keep-alive"
        },
        EventStream.new do |stream|
          begin
            # Stream progress events
            stream.write({ event: "start", data: { status: "analyzing" } })

            result = analyze_code(code, file, profile.to_sym) do |event|
              stream.write(event)
            end

            stream.write({ event: "result", data: result })
            stream.write({ event: "done" })
          rescue => e
            stream.write({ event: "error", data: { error: e.message } })
          ensure
            stream.close
          end
        end
      ]
    end

    def stream_chat(prompt, tier)
      [
        200,
        {
          "Content-Type" => "text/event-stream",
          "Cache-Control" => "no-cache",
          "Connection" => "keep-alive"
        },
        EventStream.new do |stream|
          begin
            stream.write({ event: "start", data: { status: "thinking" } })

            result = @llm.ask(prompt, tier: tier)

            if result.ok?
              # Split response into chunks for streaming effect
              response_text = result.value
              words = response_text.split(/\s+/)
              
              words.each_slice(10) do |chunk|
                stream.write({ event: "message", data: { text: chunk.join(" ") + " " } })
                sleep 0.05  # Small delay for streaming effect
              end

              stream.write({ 
                event: "cost", 
                data: { 
                  total_cost: @llm.total_cost,
                  total_tokens: @llm.total_tokens,
                  summary: @llm.cost_summary
                } 
              })
            else
              stream.write({ event: "error", data: { error: result.error } })
            end

            stream.write({ event: "done" })
          rescue => e
            stream.write({ event: "error", data: { error: e.message } })
          ensure
            stream.close
          end
        end
      ]
    end

    def analyze_code(code, file, profile)
      violations = []
      
      # Check against principles
      @principles.each do |principle|
        # Simplified analysis - in real implementation would use LLM
        if principle.smells.any? { |smell| code.downcase.include?(smell.downcase) }
          violations << {
            principle: principle.name,
            severity: principle.priority > 7 ? "high" : "medium",
            message: "Potential #{principle.name} violation detected"
          }
          
          yield({ event: "violation", data: { principle: principle.name } }) if block_given?
        end
      end

      # Use LLM for deeper analysis if needed
      if profile != :fast && violations.any?
        prompt = <<~PROMPT
          Analyze this code for the following violations:
          #{violations.map { |v| "- #{v[:principle]}" }.join("\n")}

          Code:
          ```
          #{code[0..1000]}
          ```

          Provide specific line numbers and suggestions.
        PROMPT

        result = @llm.ask(prompt, tier: profile)
        llm_analysis = result.ok? ? result.value : nil
      end

      {
        file: file,
        violations: violations,
        analysis: llm_analysis,
        cost: @llm.cost_summary
      }
    end

    def parse_json_body(request)
      body = request.body.read
      return {} if body.empty?
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def json_response(status, data)
      [status, { "Content-Type" => "application/json" }, [data.to_json]]
    end

    def mime_type(path)
      ext = File.extname(path).downcase
      types = {
        ".html" => "text/html",
        ".css" => "text/css",
        ".js" => "application/javascript",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".svg" => "image/svg+xml",
        ".ico" => "image/x-icon",
        ".txt" => "text/plain"
      }
      types[ext] || "application/octet-stream"
    end

    # Helper class for Server-Sent Events streaming
    class EventStream
      def initialize(&block)
        @output = []
        @block = block
        @closed = false
      end

      def each(&block)
        @output_block = block
        @block.call(self)
      end

      def write(data)
        return if @closed
        
        if data.is_a?(Hash)
          event = data[:event] || "message"
          payload = data[:data] || data
          
          @output_block.call("event: #{event}\n") if @output_block
          @output_block.call("data: #{payload.to_json}\n\n") if @output_block
        else
          @output_block.call("data: #{data}\n\n") if @output_block
        end
      end

      def close
        @closed = true
      end
    end
  end
end
