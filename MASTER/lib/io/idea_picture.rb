# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "replicate_client"

module Master
  module Io
    # A spoken idea becomes a still of Ragnhild and a short film of that still.
    #
    # The still is her Flux LoRA, anon987654321/ragnhild-flux, the weights in
    # MASTER/tools/studio/lora/ragnhild/weights. The film is prunaai/p-video-2-pro. Before
    # the film, postpro draws one heavy random chain, wear included, so the
    # clip is the graded frame and not the raw render.
    class IdeaPicture
      FILM = "prunaai/p-video-2-pro"
      DIR = File.expand_path("~/ideas")
      ROOT = File.expand_path("../../..", __dir__)
      SUBJECT = File.join(ROOT, "MASTER/tools/studio/lora/ragnhild")

      def initialize(client: nil)
        @client = client
      end

      def write(words, film: true, duration: 5)
        FileUtils.mkdir_p(DIR)
        stamp = Time.now.strftime("%Y%m%d-%H%M%S")
        still = render_still(words, stamp)
        return { still: } unless film

        { still:, clip: render_film(words, still, stamp, duration) }
      end

      def render_still(words, stamp)
        path = File.join(DIR, "#{stamp}.jpg")
        client.download_url(first_url(client.predict(still_model, still_input(words), timeout: 600)), path)
        grade(path)
      end

      def render_film(words, still, stamp, duration)
        path = File.join(DIR, "#{stamp}.mp4")
        client.download_url(first_url(client.predict(FILM, film_input(words, still, duration), timeout: 600)), path)
        path
      end

      def still_input(words)
        { prompt: photographic(words), model: "dev", aspect_ratio: "2:3", num_outputs: 1,
          guidance_scale: 3.0, num_inference_steps: 28, output_format: "jpg",
          output_quality: 95, go_fast: false, lora_scale: 1.0 }
      end

      def film_input(words, still, duration)
        { prompt: "The same photograph, held, one slow motion. #{words}",
          image: client.upload_file(still), duration:, mode: "quality",
          aspect_ratio: "2:3", resolution: "768p" }
      end

      private

      def client
        @client ||= ReplicateClient.new
      end

      def photographic(words)
        env = subject_env
        [env["TRIGGER"], env["DESCRIPTOR"], words, "face readable, a real lens, no text in the frame"].compact.join(", ")
      end

      def subject_env
        path = File.join(SUBJECT, "subject.env")
        return {} unless File.file?(path)

        File.foreach(path).each_with_object({}) do |line, env|
          next if line.strip.empty? || line.strip.start_with?("#")

          key, value = line.strip.split("=", 2)
          next unless value

          text = value.strip
          text = text[1..-2] if text.length >= 2 && text.start_with?('"') && text.end_with?('"')
          env[key] = text
        end
      end

      def still_model
        path = File.join(SUBJECT, "weights/ragnhild/replicate_training.json")
        version = JSON.parse(File.read(path))["version"] if File.file?(path)
        raise "ragnhild has no trained version" if version.to_s.empty?

        version
      end

      # One heavy chain, wear included. The new file sits beside the raw still.
      def grade(path)
        before = Dir[File.join(File.dirname(path), "*.jpg")]
        script = File.join(ROOT, "MASTER/tools/studio/postpro/postpro.rb")
        ok = system(RbConfig.ruby, script, "--rough", "--count", "1", path, out: File::NULL, err: File::NULL)
        raise "postpro failed" unless ok

        (Dir[File.join(File.dirname(path), "*.jpg")] - before).max_by { |file| File.mtime(file) } || path
      end

      def first_url(output)
        case output
        when String then output
        when Array then output.compact.find { |item| item.is_a?(String) && item.start_with?("http") }
        when Hash then output["url"] || output["video"] || first_url(output.values)
        end || raise("prediction returned no file")
      end
    end
  end
end
