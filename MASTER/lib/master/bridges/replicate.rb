# frozen_string_literal: true

require "net/http"
require "json"

module Master
  module Bridges
    # Replicate — native predictions API client.
    class Replicate
      BASE_URL      = "https://api.replicate.com/v1".freeze
      POLL_INTERVAL = 0.8
      MAX_WAIT      = 180

      DEFAULT_MAX_TOKENS  = 4_096
      DEFAULT_TEMPERATURE = 0.6

      def initialize(api_key: ENV["REPLICATE_API_KEY"])
        @api_key = (api_key || "").to_s
        raise "REPLICATE_API_KEY not configured" if @api_key.length < 20
      end

      # Returns a duck‑typed Message. Raises on API error.
      def chat(model:, messages:, system: nil, max_tokens: DEFAULT_MAX_TOKENS,
               temperature: DEFAULT_TEMPERATURE, stream: false, &blk)
        prompt = format_prompt(messages, system:)
        input  = build_input(prompt:, max_tokens:, temperature:)

        return chat_stream(model:, input:, &blk) if stream && blk

        pred     = create_prediction(model:, input:)
        pred_id  = pred["id"] or raise "no prediction id: #{pred.inspect}"
        result   = poll_until_done(pred_id)
        text     = (result["output"].is_a?(Array) ? result["output"].join : result["output"]).to_s

        Message.new(text)
      rescue StandardError => e
        raise "Replicate(#{model}): #{e.message}"
      end

      private

      def format_prompt(messages, system:)
        parts = []
        parts << "<<SYS>>\n#{system}\n<</SYS>>\n\n" if system
        messages.each do |m|
          role    = (m[:role] || m["role"]).to_s.downcase
          content = (m[:content] || m["content"]).to_s
          tag     = role == "assistant" ? "Assistant" : "Human"
          parts << "#{tag}: #{content}\n"
        end
        parts << "Assistant:"
        parts.join
      end

      def build_input(prompt:, max_tokens:, temperature:)
        { prompt:, max_tokens:, temperature:, top_p: 1.0 }
      end

      def chat_stream(model:, input:, &blk)
        uri = model_uri(model)
        pred = post(uri, { input:, stream: true })
        stream_url = pred.dig("urls", "stream") or raise "no stream URL: #{pred.inspect}"

        full_text = +""
        s_uri = URI(stream_url)

        Net::HTTP.start(s_uri.host, s_uri.port, use_ssl: true, read_timeout: MAX_WAIT) do |http_client|
          request = Net::HTTP::Get.new(s_uri)
          auth_headers.each { |k, v| request[k] = v }
          request["Accept"] = "text/event-stream"

          http_client.request(request) do |resp|
            buffer = +""
            resp.read_body do |chunk|
              buffer << chunk
              while (idx = buffer.index("\n\n"))
                event = buffer.slice!(0..idx + 1)
                lines = event.lines.map(&:chomp)
                type  = lines.find { |l| l.start_with?("event:") }&.then { |l| l[7..].strip }
                data  = lines.find { |l| l.start_with?("data:") }&.then { |l| l[5..].strip }
                next unless type == "output" && data && !data.empty?

                blk.call(data)
                full_text << data
              end
            end
          end
        end

        Message.new(full_text)
      rescue StandardError => e
        raise "Replicate stream(#{model}): #{e.message}"
      end

      def create_prediction(model:, input:)
        post(model_uri(model), { input: })
      end

      def poll_until_done(pred_id)
        uri      = URI("#{BASE_URL}/predictions/#{pred_id}")
        deadline = Time.now + MAX_WAIT

        loop do
          result = get(uri)
          case result["status"]
          when "succeeded"
            return result
          when "failed", "canceled"
            raise "prediction #{result["status"]}: #{result["error"]}"
          end
          raise "Timeout after #{MAX_WAIT}s." if Time.now > deadline

          sleep POLL_INTERVAL
        end
      end

      def post(uri, body)
        request = Net::HTTP::Post.new(uri)
        auth_headers.each { |k, v| request[k] = v }
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
        JSON.parse(http(uri).request(request).body)
      end

      def get(uri)
        request = Net::HTTP::Get.new(uri)
        auth_headers.each { |k, v| request[k] = v }
        JSON.parse(http(uri).request(request).body)
      end

      def http(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |client|
          client.use_ssl = true
          client.read_timeout = 35
        end
      end

      def auth_headers
        { "Authorization" => "Bearer #{@api_key}" }
      end

      def model_uri(model)
        owner, name = model.split("/", 2)
        URI("#{BASE_URL}/models/#{owner}/#{name}/predictions")
      end

      # Duck‑types as RubyLLM::Message so Agent extract_response works.
      class Message
        attr_reader :content

        def initialize(content)
          @content = content.to_s
        end

        def to_s = @content

        def respond_to_missing?(name, *) = name == :content || super
      end
    end
  end
end