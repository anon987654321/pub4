# frozen_string_literal: true

require "replicate"

module Replicate
  module Narration
    DEFAULT_MODEL = "minimax/speech-02-hd"
    DEFAULT_VOICE = "male"
    DEFAULT_FORMAT = "mp3"

    def generate_narration(text:, voice: DEFAULT_VOICE, model: DEFAULT_MODEL, format: DEFAULT_FORMAT)
      return if text.nil? || text.strip.empty?

      output = replicate_run(model, build_input(text, voice, format))
      extract_audio_url(output)
    end

    private

    def build_input(text, voice, format)
      { text: text, voice: voice, format: format }
    end

    def replicate_run(model, input)
      Replicate.run(model, input: input)
    rescue StandardError
      nil
    end

    def extract_audio_url(output)
      case output
      when Hash
        output["audio"] || output[:audio] || output["output"] || output[:output]
      when Array
        output.first
      else
        output
      end
    end
  end
end