# frozen_string_literal: true

module MASTER
  class Server
    # WebRick - WebRick server implementation (fallback)
    module WebRick
      def run_webrick
        require "webrick"

        server = WEBrick::HTTPServer.new(
          Port: @port,
          BindAddress: "127.0.0.1",
          Logger: WEBrick::Log.new("/dev/null"),
          AccessLog: [],
        )

        # Health endpoint - no auth required
        server.mount_proc("/health") { |_, res| res.body = health_json; res.content_type = JSON_TYPE }

        # Protected endpoints
        server.mount_proc("/") do |req, res|
          next unless webrick_check_auth(req, res)
          res.body = read_view("cli.html")
          res.content_type = HTML_TYPE
        end

        server.mount_proc("/poll") do |req, res|
          next unless webrick_check_auth(req, res)
          res.body = poll_json
          res.content_type = JSON_TYPE
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
