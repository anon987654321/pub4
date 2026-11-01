# frozen_string_literal: true

require "json"
require "fileutils"
require "rbconfig"
require_relative "../../output_paths"
require_relative "../../replicate/client"
require_relative "../../subprocess"

module Studio
  module Visual
    class IdeaPicture
      FILM = "prunaai/p-video-2-pro"
      ROOT = File.expand_path("../..", __dir__)
      SUBJECTS = File.join(ROOT, "replicate", "lora").freeze

      def initialize(
        client: nil,
        directory: File.expand_path("~/ideas"),
        subject: ENV.fetch("STUDIO_PHOTOGRAPH_SUBJECT", "ragnhild"),
        model_manifest: nil
      )
        @client = client
        @directory = directory
        @subject = subject.to_s
        raise ArgumentError, "subject must be a simple directory name" unless @subject.match?(/\A[a-zA-Z0-9_-]+\z/)

        @subject_directory = File.join(SUBJECTS, @subject)
        @model_manifest = model_manifest || default_model_manifest
      end

      def write(words, film: true, duration: 5)
        FileUtils.mkdir_p(@directory)
        stamp = Time.now.utc.strftime("%Y%m%dT%H%M%S%6N")
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
        parts = [
          env["TRIGGER"], env["DESCRIPTOR"], words,
          "face readable, a real lens, no text in the frame"
        ]
        parts.compact.join(", ")
      end

      def subject_env
        path = File.join(@subject_directory, "subject.env")
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

      def default_model_manifest
        configured = subject_env["MODEL"].to_s.strip
        configured = @subject if configured.empty?
        raise ArgumentError, "MODEL in #{@subject}/subject.env must be a simple directory name" unless configured.match?(/\A[a-zA-Z0-9_.-]+\z/)

        File.join(@subject_directory, "weights", configured, "replicate_training.json")
      end

      def still_model
        path = @model_manifest
        unless File.file?(path)
          raise "no trained Replicate version for #{@subject}; expected #{path}. " \
                "Complete an approved training run or pass a subject with a valid training manifest."
        end

        version = JSON.parse(File.read(path))["version"].to_s
        unless version.match?(/\A[^\/\s:]+\/[^:\s]+:[^:\s]+\z/)
          raise "training manifest has no valid owner/model:version: #{path}"
        end

        version
      rescue JSON::ParserError => error
        raise "invalid training manifest #{path}: #{error.message}"
      end

      # postpro writes its grade beside the still it was given.
      def grade(path)
        run_postpro(path)
        graded = Dir[graded_pattern(path)].max_by { |file| File.mtime(file) }
        raise "postpro succeeded but produced no graded still under #{File.dirname(path)}" unless graded

        graded
      end

      def run_postpro(path)
        script = File.join(ROOT, "postpro", "postpro.rb")
        stdout, stderr, status = Studio::Subprocess.capture3(
          {}, RbConfig.ruby, script, "--rough", "--count", "1", path, timeout: 600
        )
        return if status.success?

        raise "postpro failed: #{[stdout, stderr].compact.join("\n").lines.last.to_s.strip}"
      end

      # Where postpro names a one-take grade of `path`: beside it.
      def graded_pattern(path)
        ext = File.extname(path)
        stem = File.basename(path, ext).gsub(/[^0-9A-Za-z_-]+/, "_")
        File.join(File.dirname(path), "postpro_#{stem}_*_v1#{ext}")
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
