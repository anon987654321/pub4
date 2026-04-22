# frozen_string_literal: true

module MASTER
  module Replicate
    # Narration - Text-to-speech via Replicate API
    # Uses internal Client — no external replicate gem required.
    module Narration
      DEFAULT_MODEL  = "minimax/speech-02-hd"
      DEFAULT_VOICE  = "male"
      DEFAULT_FORMAT = "mp3"

      module_function

      def generate(text:, voice: DEFAULT_VOICE, model: DEFAULT_MODEL, format: DEFAULT_FORMAT)
        return Result.err("text required") if text.nil? || text.strip.empty?

        input  = { text: text, voice: voice, format: format }
        result = Client.create_prediction(model: model, input: input)
        return Result.err("Narration prediction failed: #{result[:error]}") if result[:error]

        completion = Client.wait_for_completion(result[:id])
        return Result.err("Narration completion failed: #{completion[:error]}") if completion[:error]

        audio_url = extract_audio_url(completion[:output])
        return Result.err("No audio URL in narration output") unless audio_url

        Result.ok(url: audio_url, model: model, voice: voice)
      rescue StandardError => e
        Result.err("Narration error: #{e.message}")
      end

      private

      def extract_audio_url(output)
        case output
        when Hash  then output["audio"] || output[:audio] || output["output"] || output[:output]
        when Array then output.first
        else            output
        end
      end
    end
  end
end
