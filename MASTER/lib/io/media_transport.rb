# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "tempfile"
require "timeout"
require "uri"
require_relative "replicate_client"

module Master
  module Io
    # The wire half of Io::MediaLanes: one function per provider that turns a
    # prompt into bytes, and the parsers that read each provider's reply. Every
    # parser fails closed: a reply that is not the documented shape raises BadShape
    # naming what was missing, never a guessed image. A provider that declines on
    # policy raises Refused with its own words, which the selector reports as the
    # stage failure and never retries elsewhere.
    #
    # Gemini image (generateContent with inlineData) and Veo (predictLongRunning,
    # poll the operation, fetch the uri) follow Google's REST contract. The
    # OpenRouter reply (message.images[].image_url.url as a data URI) is the
    # documented chat-completions image output, UNVERIFIED against the live API:
    # the repo holds no recorded reply, so test_media_lanes.rb pins a fixture.
    module MediaTransport
      extend self

      Artifact = Data.define(:bytes, :mime, :cost)
      class HttpError < StandardError
        attr_reader :code, :body

        def initialize(code, body, lane: "provider")
          @code = code
          @body = body.to_s
          super("#{lane} HTTP #{code}: #{@body[0, 300]}")
        end
      end
      Refused = Class.new(StandardError)
      BadShape = Class.new(StandardError)
      TimedOut = Class.new(StandardError)

      GEMINI_STOPS = %w[SAFETY IMAGE_SAFETY IMAGE_PROHIBITED_CONTENT PROHIBITED_CONTENT BLOCKLIST SPII RECITATION].freeze
      REFUSAL_BODY_RE = /moderation|flagged|content[\s_-]?policy|safety|blocked|prohibited/i
      MAGIC = { "image/png" => "\x89PNG".b, "image/jpeg" => "\xFF\xD8\xFF".b, "image/webp" => "RIFF".b }.freeze
      VIDEO_HOST_RE = /(?:\A|\.)(?:googleapis|googleusercontent)\.com\z/
      MAX_BYTES = 200 * 1024 * 1024

      @http = nil
      @sleeper = ->(seconds) { sleep(seconds) }
      @clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @replicate = ->(token) { ReplicateClient.new(token:) }
      attr_writer :http, :sleeper, :clock, :replicate

      # lane: a MediaLanes::Lane. env/cfg/opts come from the selector.
      def call(lane, prompt, key:, cfg:, opts: {})
        timeouts = cfg.fetch("timeouts")
        base = cfg.dig("providers", lane.provider, "base")
        case [lane.provider, lane.kind]
        when ["gemini", :image] then gemini_image(base, lane.model, prompt, key:, opts:, timeout: timeouts["call_s"])
        when ["gemini", :video] then veo(base, lane.model, prompt, key:, opts:, timeouts:, seconds: opts[:seconds] || cfg["video_seconds"])
        when ["openrouter", :image] then openrouter_image(base, lane.model, prompt, key:, timeout: timeouts["call_s"])
        when ["replicate", :image], ["replicate", :video] then replicate(lane, prompt, key:, opts:, timeouts:)
        else raise BadShape, "no transport for #{lane.provider} #{lane.kind}"
        end
      end

      def gemini_image(base, model, prompt, key:, opts:, timeout:)
        config = { responseModalities: %w[TEXT IMAGE] }
        config[:imageConfig] = { aspectRatio: opts[:aspect_ratio] } if opts[:aspect_ratio]
        body = { contents: [{ parts: [{ text: prompt }] }], generationConfig: config }
        reply = json_reply(post("#{base}/models/#{model}:generateContent", body, { "x-goog-api-key" => key }, timeout), "gemini")
        parse_gemini_image(reply)
      end

      def parse_gemini_image(reply)
        raise BadShape, "gemini: reply is not an object" unless reply.is_a?(Hash)

        blocked = reply.dig("promptFeedback", "blockReason")
        raise Refused, "gemini blocked the prompt: #{blocked} #{reply.dig("promptFeedback", "blockReasonMessage")}".strip if blocked

        candidate = Array(reply["candidates"]).first
        raise BadShape, "gemini: no candidates in reply" unless candidate.is_a?(Hash)

        parts = Array(candidate.dig("content", "parts"))
        text = parts.filter_map { |part| part["text"] }.join(" ").strip
        stop = candidate["finishReason"].to_s
        raise Refused, ["gemini stopped: #{stop}", candidate["finishMessage"], text].reject { |part| part.to_s.empty? }.join(" ") if GEMINI_STOPS.include?(stop)

        inline = parts.filter_map { |part| part["inlineData"] || part["inline_data"] }.first
        return image_artifact(inline["data"], inline["mimeType"] || inline["mime_type"]) if inline.is_a?(Hash)
        raise Refused, "gemini returned text and no image: #{text}" unless text.empty?

        raise BadShape, "gemini: candidate has no inlineData image part"
      end

      def openrouter_image(base, model, prompt, key:, timeout:)
        body = { model:, messages: [{ role: "user", content: prompt }], modalities: %w[image text], stream: false }
        reply = json_reply(post("#{base}/chat/completions", body, { "Authorization" => "Bearer #{key}" }, timeout), "openrouter")
        parse_openrouter_image(reply)
      end

      def parse_openrouter_image(reply)
        raise BadShape, "openrouter: reply is not an object" unless reply.is_a?(Hash)
        raise HttpError.new(reply.dig("error", "code") || 500, reply["error"].to_json, lane: "openrouter") if reply["error"]

        choice = Array(reply["choices"]).first
        message = choice.is_a?(Hash) ? choice["message"] : nil
        raise BadShape, "openrouter: reply has no choices[0].message" unless message.is_a?(Hash)

        raise Refused, "openrouter refused: #{message["refusal"]}" unless message["refusal"].to_s.empty?
        raise Refused, "openrouter content_filter: #{message["content"]}".strip if choice["finish_reason"] == "content_filter"

        url = Array(message["images"]).filter_map { |image| image.dig("image_url", "url") if image.is_a?(Hash) }.first
        text = message["content"].to_s.strip
        raise Refused, "openrouter returned text and no image: #{text}" if url.nil? && !text.empty?
        raise BadShape, "openrouter: message.images[].image_url.url missing" if url.nil?

        match = url.match(%r{\Adata:(image/[a-z+.-]+);base64,(.+)\z}m)
        raise BadShape, "openrouter: image url is not a base64 data URI" unless match

        cost = reply.dig("usage", "cost")
        image_artifact(match[2], match[1], cost: cost.is_a?(Numeric) ? cost.to_f : nil)
      end

      # Submit, poll under a bounded count and a wall-clock deadline, fetch.
      def veo(base, model, prompt, key:, opts:, timeouts:, seconds:)
        headers = { "x-goog-api-key" => key }
        params = { durationSeconds: seconds }
        params[:aspectRatio] = opts[:aspect_ratio] if opts[:aspect_ratio]
        started = post("#{base}/models/#{model}:predictLongRunning", { instances: [{ prompt: }], parameters: params }, headers, timeouts["call_s"])
        name = json_reply(started, "veo")["name"]
        raise BadShape, "veo: submit reply has no operation name" if name.to_s.empty?

        operation = poll_operation("#{base}/#{name}", headers, timeouts)
        fetch_video(parse_veo(operation), headers, timeouts["call_s"])
      end

      def poll_operation(url, headers, timeouts)
        deadline = @clock.call + timeouts["video_total_s"]
        timeouts["max_polls"].times do
          operation = json_reply(get(url, headers, timeouts["call_s"]), "veo")
          return operation if operation["done"]
          raise TimedOut, "veo: operation not done after #{timeouts["video_total_s"]}s" if @clock.call >= deadline

          @sleeper.call(timeouts["poll_s"])
        end
        raise TimedOut, "veo: operation not done after #{timeouts["max_polls"]} polls"
      end

      def parse_veo(operation)
        if (error = operation["error"])
          raise HttpError.new(error["code"] || 500, error.to_json, lane: "veo") unless error.to_json.match?(REFUSAL_BODY_RE)

          raise Refused, "veo refused: #{error["message"]}"
        end
        response = operation.dig("response", "generateVideoResponse") || {}
        raise Refused, "veo filtered the video: #{Array(response["raiMediaFilteredReasons"]).join("; ")}" if response["raiMediaFilteredCount"].to_i.positive?

        uri = response.dig("generatedSamples", 0, "video", "uri")
        raise BadShape, "veo: done operation has no generatedSamples[0].video.uri" if uri.to_s.empty?

        uri
      end

      def fetch_video(uri, headers, timeout)
        3.times do
          target = URI(uri)
          raise BadShape, "veo: refusing video uri #{target.scheme}://#{target.host}" unless target.scheme == "https" && target.host.to_s.match?(VIDEO_HOST_RE)

          code, body, location = get(uri, headers, timeout)
          if (300..399).cover?(code) && location
            uri = location
            next
          end
          raise HttpError.new(code, body, lane: "veo download") unless code.between?(200, 299)
          raise BadShape, "veo: download is not an mp4" unless body.byteslice(4, 4) == "ftyp"

          return Artifact.new(body, "video/mp4", nil)
        end
        raise BadShape, "veo: too many redirects fetching the video"
      end

      def replicate(lane, prompt, key:, opts:, timeouts:)
        client = @replicate.call(key)
        input = { prompt: }.merge(opts.fetch(:input, {}))
        input[:aspect_ratio] = opts[:aspect_ratio] if opts[:aspect_ratio] && lane.kind == :image
        output = client.predict(lane.model, input, timeout: timeouts["video_total_s"])
        url = Array(output).first.to_s
        raise BadShape, "replicate: output has no url" unless url.start_with?("https://")

        Tempfile.create(["media", ".bin"]) do |file|
          client.download_url(url, file.path)
          lane.kind == :video ? Artifact.new(File.binread(file.path), "video/mp4", nil) : image_bytes(File.binread(file.path), nil)
        end
      rescue ReplicateClient::ExhaustedError => e
        raise HttpError.new(402, e.message, lane: "replicate")
      rescue RuntimeError => e
        code = e.message[/Replicate API (\d{3})/, 1]
        raise code ? HttpError.new(code.to_i, e.message, lane: "replicate") : e
      end

      # Magic bytes decide the type; a declared mime that disagrees is not trusted.
      def image_artifact(data, declared, cost: nil)
        image_bytes(Base64.strict_decode64(data.to_s.delete("\n")), declared, cost:)
      rescue ArgumentError
        raise BadShape, "image data is not valid base64"
      end

      def image_bytes(bytes, declared, cost: nil)
        mime = MAGIC.find { |_type, magic| bytes.start_with?(magic) }&.first
        raise BadShape, "image bytes are not png, jpeg or webp (declared #{declared.inspect})" unless mime
        raise BadShape, "image of #{bytes.bytesize} bytes is over the cap" if bytes.bytesize > MAX_BYTES

        Artifact.new(bytes, mime, cost)
      end

      def json_reply(reply, lane)
        code, body = reply
        refused = [400, 403].include?(code) && body.to_s.match?(REFUSAL_BODY_RE) && !body.to_s.match?(/api[\s_-]?key|permission/i)
        raise Refused, "#{lane} refused: #{body.to_s[0, 500]}" if refused
        raise HttpError.new(code, body, lane:) unless code.between?(200, 299)

        JSON.parse(body)
      rescue JSON::ParserError
        raise BadShape, "#{lane}: reply is not JSON"
      end

      def post(url, body, headers, timeout) = request(:post, url, headers, JSON.generate(body), timeout)

      def get(url, headers, timeout) = request(:get, url, headers, nil, timeout)

      # [code, body, location]; tests replace this with a recorded fixture.
      def request(verb, url, headers, body, timeout)
        return @http.call(verb, url, headers, body, timeout) if @http

        uri = URI(url)
        req = verb == :post ? Net::HTTP::Post.new(uri, headers.merge("Content-Type" => "application/json")) : Net::HTTP::Get.new(uri, headers)
        req.body = body if body
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: timeout) { |http| http.request(req) }
        [res.code.to_i, res.body.to_s, res["location"]]
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        raise TimedOut, "#{uri&.host} timed out: #{e.class}"
      end
    end
  end
end
