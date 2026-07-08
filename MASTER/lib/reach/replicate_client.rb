# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Master
  module Reach
    # Thin Replicate predictions client — used by the replicate_kokoro TTS engine.
    class ReplicateClient
      CONFIG_PATH = File.expand_path("~/.config/repligen/config.json").freeze
      BASE = "https://api.replicate.com/v1"
      LORA_TRAINER = "ostris/flux-dev-lora-trainer"

      def initialize(token: nil)
        @token = token || self.class.load_token
        raise ArgumentError, "missing REPLICATE_API_TOKEN" if @token.to_s.strip.empty?
      end

      def self.load_token
        token = ENV["REPLICATE_API_TOKEN"].to_s.strip
        return token unless token.empty?

        token = ENV["REPLICATE_API_KEY"].to_s.strip
        return token unless token.empty?

        return JSON.parse(File.read(CONFIG_PATH))["api_token"].to_s.strip if File.exist?(CONFIG_PATH)

        ""
      rescue StandardError
        ""
      end

      def predict(model_id, input, timeout: 600)
        version = latest_version(model_id)
        pred = post(URI("#{BASE}/predictions"), { version: version, input: input })
        wait_for(pred["id"], timeout: timeout)
      end

      def predict_vision(model_id, prompt:, image_urls:, timeout: 600)
        input = { prompt: prompt, images: Array(image_urls) }
        predict(model_id, input, timeout: timeout)
      end

      # Fetch a prediction output URL (e.g. synthesized audio) to a local path.
      def download_url(url, path)
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 120) do |http|
          res = http.get(uri.request_uri)
          raise "download failed #{res.code}" unless res.code.to_i.between?(200, 299)

          File.binwrite(path, res.body)
        end
        path
      end

      def upload_file(path)
        mime = path.end_with?(".png") ? "image/png" : "image/jpeg"
        upload_binary(path, mime: mime)
      end

      def upload_zip(path)
        upload_binary(path, mime: "application/zip")
      end

      def account_username
        account = get(URI("#{BASE}/account"))
        account["username"].to_s.strip
      rescue StandardError
        ENV["REPLICATE_USERNAME"].to_s.strip
      end

      def model_exists?(model_id)
        owner, name = model_id.split("/")
        get(URI("#{BASE}/models/#{owner}/#{name}"))
        true
      rescue StandardError
        false
      end

      def create_model(model_id, hardware: "cpu")
        owner, name = model_id.split("/")
        post(URI("#{BASE}/models"), { owner: owner, name: name, visibility: "private", hardware: hardware })
      end

      def train_lora(photos_zip_url, destination, trigger_word: "subjectxyz", timeout: 1800)
        create_model(destination) unless model_exists?(destination)

        trainer_owner, trainer_name = LORA_TRAINER.split("/")
        trainer_version = latest_version(LORA_TRAINER)
        trainings_uri = URI("#{BASE}/models/#{trainer_owner}/#{trainer_name}/versions/#{trainer_version}/trainings")
        training = post(trainings_uri, {
          destination: destination,
          input: { input_images: photos_zip_url, trigger_word: trigger_word },
        })
        wait_for_training(training["id"], timeout: timeout)
      end

      private

      def upload_binary(path, mime:)
        boundary = "ReplicateBoundary#{rand(1_000_000_000)}"
        req = Net::HTTP::Post.new(URI("#{BASE}/files"))
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = multipart_body(path, boundary, mime: mime)
        data = request(req, URI("#{BASE}/files"))
        data.dig("urls", "get") || data["serving_url"] || data["url"] || raise("upload missing URL")
      end

      def multipart_body(path, boundary, mime: "application/octet-stream")
        filename = File.basename(path)
        "--#{boundary}\r\n".b +
          "Content-Disposition: form-data; name=\"content\"; filename=\"#{filename}\"\r\n".b +
          "Content-Type: #{mime}\r\n\r\n".b +
          File.binread(path) +
          "\r\n--#{boundary}--\r\n".b
      end

      def latest_version(model_id)
        owner, name = model_id.split("/")
        model = get(URI("#{BASE}/models/#{owner}/#{name}"))
        model.dig("latest_version", "id") || raise("no version for #{model_id}")
      end

      def get(uri)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Token #{@token}"
        request(req, uri)
      end

      def post(uri, body)
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "application/json"
        req.body = body.to_json
        request(req, uri)
      end

      def request(req, uri)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
          http.request(req)
        end
        raise "Replicate API #{res.code}: #{res.body}" unless res.code.to_i.between?(200, 299)

        JSON.parse(res.body)
      end

      def wait_for(id, timeout:)
        start = Time.now
        loop do
          pred = get(URI("#{BASE}/predictions/#{id}"))
          case pred["status"]
          when "succeeded" then return pred["output"]
          when "failed" then raise "prediction failed: #{pred['error']}"
          when "canceled" then raise "prediction canceled"
          end
          raise "prediction timeout after #{timeout}s" if Time.now - start > timeout
          sleep 3
        end
      end

      def wait_for_training(id, timeout: 1800)
        start = Time.now
        loop do
          training = get(URI("#{BASE}/trainings/#{id}"))
          case training["status"]
          when "succeeded" then return training.dig("output", "version") || training["output"]
          when "failed" then raise "training failed: #{training['error']}"
          when "canceled" then raise "training canceled"
          end
          raise "training timeout after #{timeout}s" if Time.now - start > timeout
          sleep 5
        end
      end
    end
  end
end
