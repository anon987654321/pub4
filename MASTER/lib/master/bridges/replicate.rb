# frozen_string_literal: true

require "net/http"
require "json"

module Master
  module Bridges
    # Replicate — native predictions API client.
    # Replicate is not OpenAI-compatible; it uses a polling-based predictions
    # API at /v1/models/{owner}/{name}/predictions. Tool calling is simulated
    # via prompt injection since Replicate models expose no unified tools schema.
    class Replicate
      BASE_URL      = "https://api.replicate.com/v1".freeze
      POLL_INTERVAL = 0.8
      MAX_WAIT      = 180

      # Map Replicate model → best input schema variant
      # :chat uses messages array in prompt, :instruct uses flat prompt
      MODEL_SCHEMAS = {
        "deepseek-ai/deepseek-r1"            => :instruct,
        "deepseek-ai/deepseek-v3"            => :instruct,
        "openai/gpt-4o"                      => :instruct,
        "openai/o4-mini"                     => :instruct,
        "mistralai/mistral-large-2"          => :instruct,
        "xai/grok-2"                         => :instruct,
        "meta/meta-llama-3.1-405b-instruct"  => :instruct,
        "meta/meta-llama-3-70b-instruct"     => :instruct,
      }.freeze

      DEFAULT_MAX_TOKENS = 4096
      DEFAULT_TEMPERATURE = 0.6

      def initialize(api_key: ENV["REPLICATE_API_KEY"])
        @api_key = api_key.to_s
        raise "REPLICATE_API_KEY not configured" if @api_key.length < 10
      end

      # Returns a duck-typed Message. Raises on API error.
      def chat(model:, messages:, system: nil, max_tokens: DEFAULT_MAX_TOKENS, temperature: DEFAULT_TEMPERATURE, stream: false, &blk)
        prompt = format_prompt(messages, system:)
        input  = build_input(model:, prompt:, max_tokens:, temperature:)

        return chat_stream(model:, input:, &blk) if stream && blk

        pred    = create_prediction(model:, input:)
        pred_id = pred["id"] or raise "no prediction id: #{pred.inspect}"

        result  = poll_until_done(pred_id)
        output  = result["output"]
        text    = output.is_a?(Array) ? output.join : output.to_s

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

      def build_input(model:, prompt:, max_tokens:, temperature:)
        {
          prompt:,
          max_tokens:,
          temperature:,
          top_p: 1.0,
        }
      end

      def chat_stream(model:, input:, &blk)
        owner, name = model.split("/", 2)
        uri  = URI("#{BASE_URL}/models/#{owner}/#{name}/predictions")
        req  = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{@api_key}"
        req["Content-Type"]  = "application/json"
        req.body = JSON.generate({ input:, stream: true })
        pred = JSON.parse(http(uri).request(req).body)
        stream_url = pred.dig("urls", "stream") or raise "no stream URL: #{pred.inspect}"

        full_text = +""
        suri = URI(stream_url)
        Net::HTTP.start(suri.host, suri.port, use_ssl: true, read_timeout: MAX_WAIT) do |http_client|
          sreq = Net::HTTP::Get.new(suri)
          sreq["Authorization"] = "Bearer #{@api_key}"
          sreq["Accept"]        = "text/event-stream"
          http_client.request(sreq) do |resp|
            buf = +""
            resp.read_body do |chunk|
              buf << chunk
              while (idx = buf.index("\n\n"))
                event     = buf.slice!(0..idx + 1)
                evt_lines = event.lines.map(&:chomp)
                evt_type  = evt_lines.find { |l| l.start_with?("event:") }&.then { |l| l[7..].strip }
                data      = evt_lines.find { |l| l.start_with?("data:") }&.then { |l| l[5..].strip }
                next unless evt_type == "output" && data && !data.empty?
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
        owner, name = model.split("/", 2)
        uri = URI("#{BASE_URL}/models/#{owner}/#{name}/predictions")
        post(uri, { input: })
      end

      def poll_until_done(pred_id)
        uri      = URI("#{BASE_URL}/predictions/#{pred_id}")
        deadline = Time.now + MAX_WAIT

        loop do
          result = get(uri)
          case result["status"]
          when "succeeded"          then return result
          when "failed", "canceled" then raise "prediction #{result["status"]}: #{result["error"]}"
          end
          raise "Timeout after #{MAX_WAIT}s. Consider increasing MAX_WAIT or checking network connectivity." if Time.now > deadline
          sleep POLL_INTERVAL
        end
      end

      def post(uri, body)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Bearer #{@api_key}"
        req["Content-Type"]  = "application/json"
        req.body = JSON.generate(body)
        JSON.parse(http(uri).request(req).body)
      end

      def get(uri)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@api_key}"
        JSON.parse(http(uri).request(req).body)
      end

      def http(uri)
        http_client = Net::HTTP.new(uri.host, uri.port)
        http_client.use_ssl = true
        http_client.read_timeout = 35
        http_client
      end

      # Duck-types as RubyLLM::Message so agent.rb extract_response works.
      class Message
        attr_reader :content
        def initialize(content) = @content = content.to_s
        def to_s = @content
        def respond_to_missing?(name, *) = name == :content || super
      end
    end
  end
end
