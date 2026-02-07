# frozen_string_literal: true

require "json"
require "socket"

module MASTER
  # Server - Multimodal web UI with Falcon
  class Server
    AUTH_TOKEN = ENV["MASTER_TOKEN"] || SecureRandom.hex(16)

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
      puts "web0 at http0: http://localhost:#{@port}"
    end

    def stop
      @running = false
    end

    def url
      "http://localhost:#{@port}"
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
        endpoint = Async::HTTP::Endpoint.parse("http://0.0.0.0:#{@port}")
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
        Logger: WEBrick::Log.new("/dev/null"),
        AccessLog: [],
      )

      server.mount_proc("/") { |_, res| res.body = index_html; res.content_type = "text/html" }
      server.mount_proc("/health") { |_, res| res.body = health_json; res.content_type = "application/json" }
      server.mount_proc("/poll") { |_, res| res.body = poll_json; res.content_type = "application/json" }

      server.start
    end

    def build_app
      pipeline = @pipeline
      queue = @output_queue

      ->(env) {
        path = env["PATH_INFO"]
        method = env["REQUEST_METHOD"]

        case [method, path]
        when ["GET", "/"]
          [200, { "content-type" => "text/html" }, [index_html]]

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
          }.to_json
          [200, { "content-type" => "application/json" }, [metrics]]

        else
          [404, { "content-type" => "text/plain" }, ["Not found"]]
        end
      }
    end

    def health_json
      { status: "ok", version: VERSION }.to_json
    end

    def poll_json
      text = @output_queue.empty? ? nil : (@output_queue.pop(true) rescue nil)
      { text: text, tier: LLM.tier, budget: LLM.budget_remaining }.to_json
    end

    def index_html
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>MASTER #{VERSION}</title>
          <style>
            :root { --bg: #0a0a0a; --fg: #e0e0e0; --accent: #4a9eff; --dim: #666; }
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body { font: 16px/1.5 system-ui, sans-serif; background: var(--bg); color: var(--fg); height: 100vh; display: flex; flex-direction: column; }
            header { padding: 1rem; border-bottom: 1px solid var(--dim); display: flex; justify-content: space-between; align-items: center; }
            header h1 { font-size: 1.2rem; font-weight: 500; }
            .status { font-size: 0.85rem; color: var(--dim); }
            main { flex: 1; overflow-y: auto; padding: 1rem; }
            .message { margin-bottom: 1rem; padding: 0.75rem 1rem; border-radius: 8px; max-width: 80%; }
            .message.user { background: var(--accent); color: #fff; margin-left: auto; }
            .message.assistant { background: #1a1a1a; }
            footer { padding: 1rem; border-top: 1px solid var(--dim); }
            form { display: flex; gap: 0.5rem; }
            input { flex: 1; padding: 0.75rem 1rem; border: 1px solid var(--dim); border-radius: 8px; background: #1a1a1a; color: var(--fg); font-size: 1rem; }
            input:focus { outline: none; border-color: var(--accent); }
            button { padding: 0.75rem 1.5rem; background: var(--accent); color: #fff; border: none; border-radius: 8px; cursor: pointer; font-size: 1rem; }
            button:hover { opacity: 0.9; }
            button:disabled { opacity: 0.5; cursor: not-allowed; }
            pre { background: #111; padding: 1rem; border-radius: 4px; overflow-x: auto; font-size: 0.9rem; }
            code { font-family: ui-monospace, monospace; }
          </style>
        </head>
        <body>
          <header>
            <h1>MASTER #{VERSION}</h1>
            <div class="status" id="status">Connecting...</div>
          </header>
          <main id="messages"></main>
          <footer>
            <form id="form">
              <input type="text" id="input" placeholder="Ask MASTER..." autocomplete="off" autofocus>
              <button type="submit">Send</button>
            </form>
          </footer>
          <script>
            const messages = document.getElementById('messages');
            const form = document.getElementById('form');
            const input = document.getElementById('input');
            const status = document.getElementById('status');

            function addMessage(text, role) {
              const div = document.createElement('div');
              div.className = 'message ' + role;
              div.innerHTML = text.replace(/```([\\s\\S]*?)```/g, '<pre><code>$1</code></pre>');
              messages.appendChild(div);
              messages.scrollTop = messages.scrollHeight;
            }

            form.onsubmit = async (e) => {
              e.preventDefault();
              const text = input.value.trim();
              if (!text) return;
              addMessage(text, 'user');
              input.value = '';
              input.disabled = true;

              try {
                await fetch('/chat', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({ message: text })
                });
              } catch (err) {
                addMessage('Error: ' + err.message, 'assistant');
              }
              input.disabled = false;
              input.focus();
            };

            async function poll() {
              try {
                const res = await fetch('/poll');
                const data = await res.json();
                status.textContent = data.tier + ' | $' + (data.budget || 0).toFixed(2);
                if (data.text) addMessage(data.text, 'assistant');
              } catch (err) {
                status.textContent = 'Disconnected';
              }
              setTimeout(poll, 1000);
            }
            poll();
          </script>
        </body>
        </html>
      HTML
    end
  end
end
