# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "uri"

module Studio
  # Studio-owned provider client. MASTER has its own client and runtime policies.
  class ReplicateClient
      # File upload/download helpers — separate from ReplicateClient's own
      # prediction/training/model-catalog API.
      module AssetTransfer
        def upload_file(path)
          mime = case File.extname(path).downcase
                 when ".jpg", ".jpeg" then "image/jpeg"
                 when ".png" then "image/png"
                 when ".webp" then "image/webp"
                 when ".gif" then "image/gif"
                 else
                   raise ArgumentError, "unsupported image type #{File.extname(path)}"
                 end
          upload_binary(path, mime:)
        end

        def upload_zip(path)
          upload_binary(path, mime: "application/zip")
        end

        # Fetch a prediction output URL (e.g. synthesized audio) to a local path.
        # Streamed under a byte cap, so a response that misstates its size cannot
        # fill the disk; the default is the largest thing a run fetches, a trainer
        # tar. A failed fetch leaves no partial file.
        def download_url(url, path, max_bytes: MAX_DOWNLOAD_BYTES)
          uri = URI(url)
          raise "refusing non-https download url: #{url}" unless uri.scheme == "https"
          raise "refusing download from untrusted host: #{uri.host}" unless uri.host.to_s.match?(ALLOWED_DOWNLOAD_HOST)

          Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
            http.request_get(uri.request_uri) do |res|
              raise "download failed #{res.code}" unless res.code.to_i.between?(200, 299)
              raise "download over #{max_bytes} bytes" if res["content-length"].to_i > max_bytes

              write_capped(res, path, max_bytes)
            end
          end
          path
        rescue StandardError
          FileUtils.rm_f(path)
          raise
        end

        private

        def write_capped(res, path, max_bytes)
          written = 0
          File.open(path, "wb") do |file|
            res.read_body do |chunk|
              written += chunk.bytesize
              raise "download over #{max_bytes} bytes" if written > max_bytes

              file.write(chunk)
            end
          end
        end
      end
      # LoRA training lifecycle (ostris/flux-dev-lora-trainer): start, poll,
      # fetch weights. Grouped apart from prediction/model-management to keep
      # ReplicateClient itself under the NO_GOD_CLASS public-method ceiling --
      # same pattern as AssetTransfer. Methods run against the including
      # instance, so post/get/create_model/model_exists?/wait_for_training/
      # download_url (from AssetTransfer) all resolve normally.
      module Training
        # Start ostris/flux-dev-lora-trainer. photos_zip_url must be a public or
        # Replicate Files API URL. Returns the full training object when wait is
        # true; when wait is false (webhook / async), returns the create response.
        def train_lora(
          photos_zip_url,
          destination,
          trigger_word: "subjectxyz",
          timeout: 3600,
          steps: nil,
          lora_rank: nil,
          webhook: nil,
          webhook_events_filter: nil,
          wait: true,
          extra_input: {},
          version: nil
        )
          create_model(destination) unless model_exists?(destination)
          trainings_uri, body = build_training_request(
            photos_zip_url, destination, trigger_word:, steps:, lora_rank:, webhook:, webhook_events_filter:, extra_input:, version:
          )
          training = post(trainings_uri, body)
          wait ? wait_for_training(training["id"], timeout:) : training
        end

        def get_training(id)
          get(URI("#{BASE}/trainings/#{id}"))
        end

        # The trainer version a run will use, so a sidecar can name it. A moving
        # "latest" makes two trainings of one dataset incomparable.
        def trainer_version
          latest_version(LORA_TRAINER)
        end

        # Pick a training up by id after an --async start or an interrupted poll.
        def resume_training(id, timeout: 3600)
          training = get_training(id)
          training["status"] == "succeeded" ? training : wait_for_training(id, timeout:)
        end

        def stop_training(id)
          cancel_training(id)
        end

        def training_weights_url(training)
          training = get_training(training) if training.is_a?(String)
          output = training["output"]
          case output
          when Hash
            output["weights"] || output["version"]
          when String
            output
          end
        end

        private

        def build_training_request(photos_zip_url, destination, trigger_word:, steps:, lora_rank:, webhook:, webhook_events_filter:, extra_input:, version: nil)
          trainer_owner, trainer_name = LORA_TRAINER.split("/")
          trainings_uri = URI("#{BASE}/models/#{trainer_owner}/#{trainer_name}/versions/#{version || trainer_version}/trainings")

          input = {
            input_images: photos_zip_url,
            trigger_word:,
          }
          input[:steps] = steps if steps
          input[:lora_rank] = lora_rank if lora_rank
          input.merge!(extra_input) if extra_input && !extra_input.empty?

          body = { destination:, input: }
          body[:webhook] = webhook if webhook.to_s.strip != ""
          body[:webhook_events_filter] = Array(webhook_events_filter) if webhook_events_filter

          [trainings_uri, body]
        end
      end

      # One prediction with its metrics, and the schema check that guards it.
      # Grouped apart from ReplicateClient for the same reason as Training: the
      # class stays under the public-method ceiling.
      module Prediction
        # The whole prediction object: id and metrics ride with the output, so a
        # caller can log what a frame cost. Prefer: wait holds the request for a
        # sync answer, which suits models that take seconds; Cancel-After is the
        # server-side deadline, so a stuck run stops billing even if this process
        # dies.
        def run(model_id, input, timeout: 600)
          pinned = model_id.split(":", 2)[1]
          version = pinned || latest_version(model_id)
          headers = {
            "Prefer" => "wait=#{[timeout, MAX_SYNC_WAIT].min}",
            "Cancel-After" => "#{timeout.clamp(CANCEL_AFTER_RANGE)}s",
          }
          pred = post(URI("#{BASE}/predictions"), { version:, input: }, headers:)
          settle(pred, timeout:)
        end

        # The input names a model declares, for refusing a key it would ignore.
        def input_names(model_id)
          input_keys(model_id)
        end
      end

      include AssetTransfer
      include Training
      include Prediction

      # Raised for HTTP statuses worth a retry (rate limit, server-side fault).
      # A 4xx other than 429 means the request itself is wrong and retrying
      # retries repeat the same failure.
      TransientError = Class.new(StandardError)
      # A spend limit. The status codes alone could not tell this apart: a
      # 402 already fell through to the plain raise and was handled correctly
      # by accident, but Replicate also answers 429 when the account is out of
      # budget rather than merely too fast — and TRANSIENT_STATUS reads every
      # 429 as a throttle, so those were retried three times with backoff to
      # buy the same refusal three times. Named so the retry loop can tell a
      # wait that will help from one that cannot.
      ExhaustedError = Class.new(StandardError)

      CONFIG_PATH = File.expand_path("~/.config/replicate/config.json").freeze
      BASE = "https://api.replicate.com/v1"
      LORA_TRAINER = "ostris/flux-dev-lora-trainer"
      TRANSIENT_STATUS = ((500..599).to_a << 429).freeze
      MAX_DOWNLOAD_BYTES = 4 * 1024**3
      # Replicate holds a sync request 60 seconds at most; Cancel-After takes
      # 5 seconds to 24 hours.
      MAX_SYNC_WAIT = 60
      CANCEL_AFTER_RANGE = (5..86_400).freeze
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

        token_from_env_file
      rescue StandardError
        ""
      end

      def self.token_from_env_file
        path = File.expand_path("~/.config/master/env")
        return "" unless File.file?(path)

        File.foreach(path) do |line|
          key, value = line.strip.sub(/\Aexport\s+/, "").split("=", 2)
          return value.to_s.delete(%("')) if %w[REPLICATE_API_TOKEN REPLICATE_API_KEY].include?(key) && !value.to_s.empty?
        end
        ""
      rescue StandardError
        ""
      end

      # owner/name:version pins a version; a bare owner/name takes the latest. A
      # trained LoRA gains a version per training, and frames meant to compare
      # checkpoints have to name the one they came from.
      def predict(model_id, input, timeout: 600)
        run(model_id, input, timeout:)["output"]
      end

      # Bounded catalog read used by Replicate search/sync. Replicate returns a
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
      # content-addressed blob cache in replicate.rb.
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
        warn("replicate model lookup failed: #{e.class}: #{e.message}")
        false
      end

      # A LoRA destination serves FLUX.1-dev, and gpu-l40s is the smallest SKU
      # Replicate accepts that holds it; the API refuses names off its list.
      def create_model(model_id, hardware: "gpu-l40s", visibility: "private")
        owner, name = model_id.split("/", 2)
        raise ArgumentError, "destination must be owner/name" if owner.to_s.empty? || name.to_s.empty?

        post(URI("#{BASE}/models"), {
          owner:,
          name:,
          visibility:,
          hardware:,
        })
      end

      private

      def upload_binary(path, mime:)
        boundary = "ReplicateBoundary#{rand(1_000_000_000)}"
        req = Net::HTTP::Post.new(URI("#{BASE}/files"))
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.body = multipart_body(path, boundary, mime:)
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

      # The input parameter names the provider currently declares, from the same
      # GET latest_version already makes.
      #
      # replicate keeps its own MODEL_CAPABILITIES table so it can refuse an
      # unsupported option rather than let the API ignore it — which is the right
      # call, and is also a second source of truth. When Replicate changes a
      # schema the table goes stale, the tests stay green because they only check
      # the table against itself, and the drift shows up as a 422 in production
      # or, worse, as a setting silently dropped.
      def input_keys(model_id)
        owner, name = model_id.split("/")
        model = get(URI("#{BASE}/models/#{owner}/#{name}"))
        schema = model.dig("latest_version", "openapi_schema",
                           "components", "schemas", "Input", "properties")
        Array(schema&.keys)
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

      def post(uri, body, headers: {})
        req = Net::HTTP::Post.new(uri)
        req["Authorization"] = "Token #{@token}"
        req["Content-Type"] = "application/json"
        headers.each { |name, value| req[name] = value }
        req.body = body.to_json
        request(req, uri)
      end

      def request(req, uri, attempts: 3)
        last_error = nil
        attempts.times do |attempt|
          return attempt_request(req, uri)
        rescue ExhaustedError => e
          # Out of the retry loop entirely, and onto the gate: no wait inside
          # this run makes the account solvent, and the caller needs to know
          # the capability is gone rather than that one call failed.
          warn("replicate quota exhausted: #{e.message}")
          raise
        rescue TransientError, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ETIMEDOUT => e
          last_error = e.message
          sleep(retry_delay(last_error, attempt)) if attempt < attempts - 1
        end
        raise last_error
      end

      def attempt_request(req, uri)
        res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
          http.request(req)
        end
        code = res.code.to_i
        return JSON.parse(res.body) if code.between?(200, 299)

        message = "Replicate API #{code}: #{res.body}"
        raise ExhaustedError, message if exhausted?(code, res.body)
        raise TransientError, message if TRANSIENT_STATUS.include?(code)

        raise message
      end

      # Replicate says when a throttle clears ("resets in ~30s"); waiting that
      # long beats a blind exponential guess in both directions.
      def retry_delay(message, attempt)
        reset = message.to_s[/resets in ~?(\d+)s/, 1]
        [reset ? reset.to_i + 1 : 2**attempt, 60].min
      end

      # 402 is unambiguous. Beyond it, the body is the only thing that
      # separates "you are going too fast" from "you have no budget", and both
      # arrive as 429.
      def exhausted?(code, body)
        code == 402 || body.to_s.match?(/(?:insufficient|exhausted|no\s+credit|quota|billing|budget)/i)
      end

      def cancel_prediction(id)
        post(URI("#{BASE}/predictions/#{id}/cancel"), {})
      rescue StandardError => e
        warn("replicate cancel prediction failed: #{e.class}: #{e.message}")
        nil
      end

      def cancel_training(id)
        post(URI("#{BASE}/trainings/#{id}/cancel"), {})
      rescue StandardError => e
        warn("replicate cancel training failed: #{e.class}: #{e.message}")
        nil
      end

      # A create answered under Prefer: wait may already be finished; otherwise
      # poll the same prediction, easing off from 1s to 5s.
      def settle(pred, timeout:)
        start = Time.now
        delay = 1
        loop do
          case pred["status"]
          when "succeeded" then return pred
          when "failed" then raise "prediction failed: #{pred['error']}"
          when "canceled" then raise "prediction canceled"
          end
          if Time.now - start > timeout
            cancel_prediction(pred["id"])
            raise "prediction timeout after #{timeout}s (canceled)"
          end
          sleep delay
          delay = [delay + 1, 5].min
          pred = get(URI("#{BASE}/predictions/#{pred['id']}"))
        end
      end

      def wait_for_training(id, timeout: 3600)
        start = Time.now
        delay = 5
        loop do
          training = get(URI("#{BASE}/trainings/#{id}"))
          case training["status"]
          when "succeeded" then return training
          when "failed" then raise "training failed: #{training['error']}"
          when "canceled" then raise "training canceled"
          end
          if Time.now - start > timeout
            cancel_training(id)
            raise "training timeout after #{timeout}s (canceled)"
          end
          sleep delay
          delay = [delay + 2, 15].min
        end
      end
    end
  end
