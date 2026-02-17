# frozen_string_literal: true

module MASTER
  class Server
    # WEBrick - WEBrick server implementation (fallback)
    module WEBrick
      def run_webrick
        require "webrick"

        server = ::WEBrick::HTTPServer.new(
          Port: @port,
          BindAddress: "0.0.0.0",
          Logger: ::WEBrick::Log.new("/dev/null"),
          AccessLog: [],
        )

        # Health endpoint - no auth required
        server.mount_proc("/health") { |_, res| res.body = health_json; res.content_type = JSON_TYPE }

        # Protected endpoints
        server.mount_proc("/") do |req, res|
          next unless webrick_check_auth(req, res)
          html = read_view("cli.html")
          html = html.sub("window.MASTER_TOKEN||''", "window.MASTER_TOKEN||'#{AUTH_TOKEN}'")
          res.body = html
          res.content_type = HTML_TYPE
        end

        server.mount_proc("/poll") do |req, res|
          next unless webrick_check_auth(req, res)
          res.body = poll_json
          res.content_type = JSON_TYPE
        end

        server.mount_proc("/chat") do |req, res|
          next unless webrick_check_auth(req, res)
          data = JSON.parse(req.body || "{}", symbolize_names: true) rescue {}
          message = data[:message].to_s.strip
          if message.empty?
            res.status = 400
            res.body = '{"error":"no message"}'
          else
            Thread.new do
              result = @pipeline.call({ text: message })
              output = result.ok? ? (result.value[:rendered] || result.value[:response] || result.value[:answer]) : "Error: #{result.error}"
              @output_queue.push(output)
            rescue StandardError => e
              @output_queue.push("Error: #{e.message}")
            end
            res.body = '{"status":"processing"}'
          end
          res.content_type = JSON_TYPE
        end

        # Serve shared JS
        server.mount_proc("/orb_shared.js") do |req, res|
          next unless webrick_check_auth(req, res)
          js_path = File.join(VIEWS_DIR, "orb_shared.js")
          res.body = File.exist?(js_path) ? File.read(js_path) : ""
          res.content_type = "application/javascript"
        end

        # Serve orb views - protected
        Dir.glob(File.join(VIEWS_DIR, "*.html")).each do |file|
          name = "/" + File.basename(file)
          server.mount_proc(name) do |req, res|
            next unless webrick_check_auth(req, res)
            res.body = File.read(file)
            res.content_type = HTML_TYPE
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
    end
  end
end
