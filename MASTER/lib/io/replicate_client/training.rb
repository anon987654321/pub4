# frozen_string_literal: true

module Master
  module Io
    class ReplicateClient
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
          extra_input: {}
        )
          create_model(destination) unless model_exists?(destination)
          trainings_uri, body = build_training_request(
            photos_zip_url, destination, trigger_word:, steps:, lora_rank:, webhook:, webhook_events_filter:, extra_input:
          )
          training = post(trainings_uri, body)
          wait ? wait_for_training(training["id"], timeout: timeout) : training
        end

        def get_training(id)
          get(URI("#{BASE}/trainings/#{id}"))
        end

        # Download LoRA artifact from a completed training (output.weights URL).
        # Writes the tar (or whatever Replicate returns) to path.
        def download_training_weights(training, path)
          url = training_weights_url(training)
          raise "training has no output.weights URL" if url.to_s.empty?

          download_url(url, path)
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

        def build_training_request(photos_zip_url, destination, trigger_word:, steps:, lora_rank:, webhook:, webhook_events_filter:, extra_input:)
          trainer_owner, trainer_name = LORA_TRAINER.split("/")
          trainer_version = latest_version(LORA_TRAINER)
          trainings_uri = URI("#{BASE}/models/#{trainer_owner}/#{trainer_name}/versions/#{trainer_version}/trainings")

          input = {
            input_images: photos_zip_url,
            trigger_word: trigger_word,
          }
          input[:steps] = steps if steps
          input[:lora_rank] = lora_rank if lora_rank
          input.merge!(extra_input) if extra_input && !extra_input.empty?

          body = { destination: destination, input: input }
          body[:webhook] = webhook if webhook.to_s.strip != ""
          body[:webhook_events_filter] = Array(webhook_events_filter) if webhook_events_filter

          [trainings_uri, body]
        end
      end
    end
  end
end
