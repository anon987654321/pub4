# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "replicate_client/asset_transfer"

module Master
  module Reach
    # Thin Replicate predictions client — used by the replicate_kokoro TTS engine.
    class ReplicateClient
      include AssetTransfer

      # Raised for HTTP statuses worth a retry (rate limit, server-side fault).
      # A 4xx other than 429 means the request itself is wrong and retrying
      # retries repeat the same failure.
      TransientError = Class.new(StandardError)

      CONFIG_PATH = File.expand_path("~/.config/repligen/config.json").freeze
      BASE = "https://api.replicate.com/v1"
      LORA_TRAINER = "ostris/flux-dev-lora-trainer"
      TRANSIENT_STATUS = ((500..599).to_a << 429).freeze
      # replicate.delivery hosts prediction output blobs; replicate.com is the
      # API itself. Refuse to fetch a URL a compromised/odd response pointed
      # us at anywhere else.
      ALLOWED_DOWNLOAD_HOST = /\A([a-z0-9-]+\.)*replicate\.(com|delivery)\z/i.freeze

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

      # Bounded catalog read used by Repligen search/sync. Replicate returns a
      # cursor URL; only follow it until the caller's explicit limit is met.
      def models(limit: 100, query: nil)
        remaining = [[limit.to_i, 1].max, 1_000].min
        uri = URI("#{BASE}/models")
        rows = []
        while uri && rows.length < remaining
          page = get(uri)
          rows.concat(Array(page["results"]))
          uri = page["next"].to_s.empty? ? nil : URI(page["next"])
        end
        rows = rows.first(remaining)
        needle = query.to_s.strip.downcase
        return rows if needle.empty?

        rows.select do |model|
          [model["owner"], model["name"], model["description"]].compact.join(" ").downcase.include?(needle)
        end
      end

      # SHA-256 of a downloaded file, for provenance sidecars and the
      # content-addressed blob cache in repligen.rb.
      def self.checksum(path)
        require "digest"
        Digest::SHA256.file(path).hexdigest
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
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ReplicateClient.model_exists?")
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

      def request(req, uri, attempts: 3)
        last_error = nil
        attempts.times do |attempt|
          begin
            res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
              http.request(req)
            end
            code = res.code.to_i
            return JSON.parse(res.body) if code.between?(200, 299)
            raise TransientError, "Replicate API #{code}: #{res.body}" if TRANSIENT_STATUS.include?(code)

            raise "Replicate API #{code}: #{res.body}"
          rescue TransientError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT => e
            last_error = e.message
            sleep(2**attempt) if attempt < attempts - 1
          end
        end
        raise last_error
      end

      def cancel_prediction(id)
        post(URI("#{BASE}/predictions/#{id}/cancel"), {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ReplicateClient.cancel_prediction")
        nil
      end

      def cancel_training(id)
        post(URI("#{BASE}/trainings/#{id}/cancel"), {})
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ReplicateClient.cancel_training")
        nil
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
          if Time.now - start > timeout
            cancel_prediction(id)
            raise "prediction timeout after #{timeout}s (canceled)"
          end
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
          if Time.now - start > timeout
            cancel_training(id)
            raise "training timeout after #{timeout}s (canceled)"
          end
          sleep 5
        end
      end
    end
  end
end
