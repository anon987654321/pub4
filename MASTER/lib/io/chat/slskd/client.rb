# frozen_string_literal: true

require "securerandom"
require_relative "../transport"
require_relative "../http"

module Master
  module Io
    module Chat
      class Slskd < Transport
        # REST wrapper for ONE slskd instance the operator runs. Endpoint paths
        # come from slskd's controllers (src/slskd/*/API/Controllers, read
        # 2026-10-12). Request/response field names marked UNVERIFIED were not
        # visible in those files and are read defensively (case-insensitive,
        # missing fields tolerated).
        class Client
          class Refused < RuntimeError; end

          LOCAL = %w[localhost 127.0.0.1 ::1 [::1]].freeze
          DEFAULT_URL = "http://localhost:5030"

          # Localhost always; anything else only with MASTER_SLSKD_ALLOW_REMOTE=1 and https.
          def self.check_url!(raw, env: ENV)
            uri = URI(raw.to_s)
            raise Refused, "slskd url must be http(s)" unless uri.is_a?(URI::HTTP) && uri.host
            return uri if LOCAL.include?(uri.host.downcase)
            raise Refused, "slskd is not on localhost; set MASTER_SLSKD_ALLOW_REMOTE=1 and use https" unless env["MASTER_SLSKD_ALLOW_REMOTE"] == "1"
            raise Refused, "remote slskd needs https" unless uri.scheme == "https"

            uri
          rescue URI::InvalidURIError
            raise Refused, "slskd url is not a url"
          end

          def initialize(env: ENV, http: nil)
            @env = env
            uri = self.class.check_url!(env["MASTER_SLSKD_URL"] || DEFAULT_URL, env:)
            @key = env["MASTER_SLSKD_API_KEY"].to_s
            @user = env["MASTER_SLSKD_USERNAME"].to_s
            @pass = env["MASTER_SLSKD_PASSWORD"].to_s
            @jwt = nil
            @http = http || Http.new(base: "#{uri.scheme}://#{uri.host}:#{uri.port}/api/v0",
                                     headers: method(:auth_headers), secrets: -> { [@key, @pass, @jwt] })
          end

          def redact(text) = @http.redact(text)
          def authenticated? = !@key.empty? || (!@user.empty? && !@pass.empty?)
          def auth_mode = @key.empty? ? (@jwt || !@user.empty? ? "session" : "none") : "api-key"

          def application = fetch(:get, "/application")

          def create_search(text, timeout_ms: 15_000, response_limit: 100, file_limit: 2000)
            id = SecureRandom.uuid
            # searchTimeout/responseLimit/fileLimit option names: UNVERIFIED.
            fetch(:post, "/searches", { id:, searchText: text, searchTimeout: timeout_ms,
                                        responseLimit: response_limit, fileLimit: file_limit })
            id
          end

          def search(id) = fetch(:get, "/searches/#{enc(id)}")
          def search_responses(id) = fetch(:get, "/searches/#{enc(id)}/responses")
          def browse(user) = fetch(:get, "/users/#{enc(user)}/browse", timeout: 60)

          def rooms_joined = fetch(:get, "/rooms/joined")
          def room_messages(room) = fetch(:get, "/rooms/joined/#{enc(room)}/messages")
          def room_join(room) = fetch(:post, "/rooms/joined", room.to_s)
          def room_leave(room) = fetch(:delete, "/rooms/joined/#{enc(room)}")
          def room_say(room, text) = fetch(:post, "/rooms/joined/#{enc(room)}/messages", text.to_s)

          def conversations = fetch(:get, "/conversations")
          def conversation_messages(user) = fetch(:get, "/conversations/#{enc(user)}/messages")
          def conversation_say(user, text) = fetch(:post, "/conversations/#{enc(user)}", text.to_s)

          def downloads = fetch(:get, "/transfers/downloads")

          # One file, one call. Body casing and the batches shape: UNVERIFIED.
          def enqueue(user, filename, size)
            fetch(:post, "/transfers/downloads/batches", { username: user, files: [{ filename:, size: }] })
          end

          private

          def enc(part) = URI.encode_www_form_component(part.to_s).gsub("+", "%20")

          def auth_headers
            return { "X-API-Key" => @key } unless @key.empty?

            @jwt ? { "Authorization" => "Bearer #{@jwt}" } : {}
          end

          def send_request(verb, path, body, timeout)
            case verb
            when :get then @http.get(path, timeout:)
            when :delete then @http.delete(path)
            else @http.public_send(verb, path, body, timeout:)
            end
          end

          def login
            return if !@key.empty? || @jwt || @user.empty? || @pass.empty?

            res = @http.post("/session", { username: @user, password: @pass })
            raise Http::Error, "slskd login failed (http #{res.status})" unless res.ok? && res.json.is_a?(Hash)

            @jwt = res.json.find { |k, _| k.to_s.casecmp("token").zero? }&.last
            raise Http::Error, "slskd login returned no token" unless @jwt
          end

          def fetch(verb, path, body = nil, timeout: nil)
            raise Refused, "no slskd credentials: set MASTER_SLSKD_API_KEY" unless authenticated?

            login
            res = send_request(verb, path, body, timeout)
            raise Http::Error, redact("slskd #{verb} #{path.split("/")[1]} http #{res.status}") unless res.ok?

            res.json
          end
        end
      end
    end
  end
end
