# frozen_string_literal: true

require "json"
require_relative "host"

module Master
  module Mobile
    # The HTTP side of the phone face: a Rack app on Falcon, bound to
    # loopback because it has no authentication, beside the Unix face socket.
    # Falcon is a gem the phone installs (bin/master-mobile-install); the
    # desktop bundle does not carry it.
    class FaceBridgeHttp
      WEB = File.expand_path("web", __dir__)
      ASSETS = { "/face" => ["face.html", "text/html; charset=utf-8"],
                 "/face_bridge.js" => ["face_bridge.js", "application/javascript"] }.freeze

      def initialize(root:, config: Mobile.config, host: nil)
        bridge = config.fetch("bridge", {})
        @bind = bridge["bind"] || "127.0.0.1"
        @port = Integer(ENV["MASTER_MOBILE_BRIDGE_PORT"] || bridge["port"] || 8765)
        @host = host || Host.new(root:, config:)
      end

      def start!
        require "async"
        require "falcon"
        require "async/http/endpoint"
        @host.start!
        Thread.new { loop { @host.face.serve_once } }
        warn "mobile0: face at http://#{@bind}:#{@port}/face, socket #{@host.face.socket_path}"
        Sync { Falcon::Server.new(Falcon::Server.middleware(method(:call)), endpoint).run.wait }
      end

      def call(env)
        method, path = env["REQUEST_METHOD"], env["PATH_INFO"]
        return asset(*ASSETS.fetch(path)) if method == "GET" && ASSETS.key?(path)
        return json(200, health) if [method, path] == ["GET", "/health"]
        return utterance(env) if [method, path] == ["POST", "/utterance"]
        return listen if [method, path] == ["POST", "/listen"]
        return speak(env) if [method, path] == ["POST", "/speak"]

        json(404, "ok" => false, "error" => "not found")
      end

      private

      def endpoint = Async::HTTP::Endpoint.parse("http://#{@bind}:#{@port}")

      def health = { "status" => "ok", "session" => @host.session.id, "socket" => @host.face.socket_path }

      def utterance(env)
        body = request_body(env)
        json(200, "ok" => true, "reply" => @host.handle_utterance(body["text"].to_s, "http"))
      rescue JSON::ParserError
        json(400, "ok" => false, "error" => "body is not JSON")
      end

      def listen
        heard = @host.ambient.listen_once
        return json(503, "ok" => false, "error" => heard.error || "speech input unavailable") unless heard.ok?

        text = heard.text.to_s.strip
        return json(422, "ok" => false, "error" => "heard nothing") if text.empty?

        json(200, "ok" => true, "heard" => text)
      rescue StandardError => e
        json(503, "ok" => false, "error" => "speech input failed: #{e.class}: #{e.message}")
      end

      def speak(env)
        body = request_body(env)
        result = @host.ambient.speak!(body["text"].to_s)
        json(200, "ok" => true, "spoken" => result.ok?, "error" => result.error)
      rescue JSON::ParserError
        json(400, "ok" => false, "error" => "body is not JSON")
      rescue StandardError => e
        json(200, "ok" => true, "spoken" => false, "error" => "speech output failed: #{e.class}: #{e.message}")
      end

      def request_body(env)
        raw = env["rack.input"].read.to_s
        parsed = JSON.parse(raw.empty? ? "{}" : raw)
        raise JSON::ParserError, "body must be an object" unless parsed.is_a?(Hash)

        parsed
      end

      def asset(name, type)
        body = File.read(File.join(WEB, name))
        [200, { "content-type" => type, "content-length" => body.bytesize.to_s }, [body]]
      end

      def json(status, payload)
        body = JSON.generate(payload)
        [status, { "content-type" => "application/json", "content-length" => body.bytesize.to_s }, [body]]
      end
    end
  end
end
