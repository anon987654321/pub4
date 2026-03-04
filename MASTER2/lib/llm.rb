# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LLM
  DEFAULT_TEMPERATURE = 0.2
  DEFAULT_MAX_TOKENS = 800
  DEFAULT_TIMEOUT_SECONDS = 60
  DEFAULT_RETRIES = 2
  RETRY_BACKOFF_SECONDS = 1.0
  TRANSIENT_HTTP_STATUSES = [408, 429, 500, 502, 503, 504].freeze

  class Error < StandardError; end
  class RequestError < Error; end
  class ResponseError < Error; end

  Result = Struct.new(:text, :raw, :model, :usage, keyword_init: true) do
    def ok?
      text.to_s.strip != ""
    end
  end

  class Client
    def initialize(base_url:, api_key:, default_model:, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
      @base_url = base_url
      @api_key = api_key
      @default_model = default_model
      @timeout_seconds = timeout_seconds
    end

    attr_reader :base_url, :timeout_seconds

    def current_model(model: nil)
      model || @default_model
    end

    def tier(model: nil)
      resolved = current_model(model: model)
      resolved.to_s.include?("gpt-4") ? :pro : :standard
    end

    def ask(prompt:,
            system: nil,
            model: nil,
            temperature: DEFAULT_TEMPERATURE,
            max_tokens: DEFAULT_MAX_TOKENS,
            retries: DEFAULT_RETRIES,
            stream: false,
            request_id: nil)
      raise ArgumentError, "prompt is required" if prompt.to_s.strip == ""

      resolved_model = current_model(model: model)
      payload = build_payload(
        prompt: prompt,
        system: system,
        model: resolved_model,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: stream
      )

      raw = with_retry(retries: retries) do
        execute_request(payload: payload, request_id: request_id)
      end

      process_response(raw: raw, model: resolved_model)
    end

    private

    def build_payload(prompt:, system:, model:, temperature:, max_tokens:, stream:)
      messages = []
      messages << { role: "system", content: system } if system && system.to_s.strip != ""
      messages << { role: "user", content: prompt }

      {
        model: model,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: stream,
        messages: messages
      }
    end

    def with_retry(retries:)
      attempts = 0

      begin
        attempts += 1
        yield
      rescue RequestError => e
        raise if attempts > retries
        sleep(RETRY_BACKOFF_SECONDS * attempts)
        retry
      end
    end

    def execute_request(payload:, request_id:)
      uri = URI.join(base_url.to_s.end_with?("/") ? base_url : "#{base_url}/", "v1/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = timeout_seconds
      http.open_timeout = timeout_seconds

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      request["X-Request-Id"] = request_id if request_id
      request.body = JSON.generate(payload)

      response = http.request(request)

      code = response.code.to_i
      body = response.body.to_s

      raise RequestError, "HTTP #{code}" if TRANSIENT_HTTP_STATUSES.include?(code)
      raise ResponseError, "HTTP #{code}: #{truncate(body)}" unless code.between?(200, 299)

      parse_json(body)
    rescue Timeout::Error, Errno::ECONNRESET, Errno::ETIMEDOUT, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      raise RequestError, e.message
    end

    def process_response(raw:, model:)
      choices = raw.fetch("choices", [])
      first = choices.is_a?(Array) ? choices.first : nil
      message = first.is_a?(Hash) ? first.fetch("message", {}) : {}
      content = message.is_a?(Hash) ? message.fetch("content", "") : ""

      Result.new(
        text: content.to_s,
        raw: raw,
        model: model,
        usage: raw.fetch("usage", {})
      )
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise ResponseError, "Invalid JSON response: #{e.message}"
    end

    def truncate(text, limit = 600)
      str = text.to_s
      return str unless str.length > limit

      "#{str[0, limit]}..."
    end
  end
end