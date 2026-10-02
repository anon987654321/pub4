# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../../replicate/client"

module Studio
  module Visual
    class IdeaPicture
      FILM = "prunaai/p-video-2-pro"
      ROOT = File.expand_path("../..", __dir__)
      SUBJECT = File.join(ROOT, "lora", "ragnhild")

      def initialize(client: nil, directory: File.expand_path("~/ideas"))
        @client = client
        @directory = directory
      end

      def write(words, film: true, duration: 5)
        FileUtils.mkdir_p(@directory)
        stamp = Time.now.strftime("%Y%m%d-%H%M%S")
        still = render_still(words, stamp)
        return { "still" => still } unless film

        { "still" => still, "clip" => render_film(words, still, stamp, duration) }
      end

      private

      def client
        @client ||= Studio::ReplicateClient.new
      end

      def render_still(words, stamp)
        path = File.join(@directory, "#{stamp}.jpg")
        output = client.predict(still_model, still_input(words), timeout: 600)
        client.download_url(first_url(output), path)
        grade(path)
      end

      def render_film(words, still, stamp, duration)
        path = File.join(@directory, "#{stamp}.mp4")
        output = client.predict(FILM, film_input(words, still, duration), timeout: 600)
        client.download_url(first_url(output), path)
        path
      end

      def still_input(words)
        {
          prompt: photographic(words),
          model: "dev",
          aspect_ratio: "2:3",
          num_outputs: 1,
          guidance_scale: 3.0,
          num_inference_steps: 28,
          output_format: "jpg",
          output_quality: 95,
          go_fast: false,
          lora_scale: 1.0
        }
      end

      def film_input(words, still, duration)
        {
          prompt: "The same photograph, held, one slow motion. #{words}",
          image: client.upload_file(still),
          duration:,
          mode: "quality",
          aspect_ratio: "2:3",
          resolution: "768p"
        }
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

          value = value.strip
          value = value[1..-2] if value.length >= 2 && value.start_with?('"') && value.end_with?('"')
          env[key] = value
        end
      end

      def still_model
        path = File.join(SUBJECT, "weights", "ragnhild", "replicate_training.json")
        version = JSON.parse(File.read(path))["version"] if File.file?(path)
        raise "ragnhild has no trained version" if version.to_s.empty?

        version
      end

      def grade(path)
        script = File.join(ROOT, "postpro", "postpro.rb")
        stdout, status = Open3.capture2e(RbConfig.ruby, script, "--rough", "--count", "1", path)
        raise "postpro failed: #{stdout.lines.last.to_s.strip}" unless status.success?

        generated = Dir[File.join(File.dirname(path), "*.jpg")].sort_by { |file| File.mtime(file) }.reverse
        generated.find { |file| file != path } || path
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
