# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Io
    module Chat
      # One small JSON-over-HTTP client for the chat transports that speak a
      # REST API (Telegram, slskd). It owns two guarantees the callers lean on:
      # a response body is read up to a byte cap and no further, and no error
      # string it raises carries a secret -- a Telegram token lives in the URL
      # path, so a bare Net::HTTP message would print it.
      class Http
        class Error < StandardError; end

        Response = Struct.new(:status, :body, :json, keyword_init: true) do
          def ok? = status.between?(200, 299)
        end

        MAX_BYTES = 8_000_000

        # secrets: a callable returning the strings to scrub, read at error time
        # so a token set after construction is still covered.
        def initialize(base:, headers: -> { {} }, secrets: -> { [] }, open_timeout: 5, read_timeout: 20)
          @base = URI(base.to_s.chomp("/"))
          @headers = headers
          @secrets = secrets
          @open_timeout = open_timeout
          @read_timeout = read_timeout
        end

        attr_reader :base

        def get(path, query: nil, timeout: nil) = request(Net::HTTP::Get, path, query:, timeout:)
        def post(path, body = nil, timeout: nil) = request(Net::HTTP::Post, path, body:, timeout:)
        def put(path, body = nil, timeout: nil) = request(Net::HTTP::Put, path, body:, timeout:)
        def delete(path, query: nil) = request(Net::HTTP::Delete, path, query:)

        def redact(text)
          @secrets.call.compact.map(&:to_s).reject(&:empty?).reduce(text.to_s) do |out, secret|
            out.gsub(secret, "***").gsub(URI.encode_www_form_component(secret), "***")
          end
        end

        private

        def request(klass, path, query: nil, body: nil, timeout: nil)
          uri = target(path, query)
          req = klass.new(uri)
          @headers.call.each { |key, value| req[key] = value }
          req["Accept"] = "application/json"
          unless body.nil?
            req["Content-Type"] = "application/json"
            req.body = JSON.generate(body)
          end
          perform(uri, req, timeout)
        rescue Error
          raise
        rescue StandardError => e
          raise Error, redact("#{e.class}: #{e.message}")
        end

        def target(path, query)
          uri = @base.dup
          uri.path = "#{@base.path}#{path}"
          uri.query = URI.encode_www_form(query) if query && !query.empty?
          uri
        end

        def perform(uri, req, timeout)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @open_timeout
          http.read_timeout = timeout || @read_timeout
          http.start do |conn|
            conn.request(req) do |res|
              body = read_capped(res)
              return Response.new(status: res.code.to_i, body:, json: parse(body))
            end
          end
        end

        def read_capped(res)
          buffer = +""
          res.read_body do |chunk|
            buffer << chunk
            raise Error, "response over #{MAX_BYTES} bytes, dropped" if buffer.bytesize > MAX_BYTES
          end
          buffer
        end

        def parse(body)
          body.to_s.strip.empty? ? nil : JSON.parse(body)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
