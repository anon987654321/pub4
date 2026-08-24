# frozen_string_literal: true

require "pub4/deploy_paths"
require "rbconfig"
require "fileutils"

module Shared
  # Runs studio/postpro/postpro.rb on Active Storage blobs (seeds, jobs, newsletters).
  module PostproProcessor
    VALID_PRESETS = %w[portrait landscape street blockbuster cinematic magic_hour indie polaroid].freeze

    module_function

    def script
      Pub4::DeployPaths.postpro_script
    end

    def available?
      path = script
      !path.to_s.empty? && File.file?(path)
    end

    def skip?
      !ENV.fetch("SKIP_DEMO_POSTPRO", "").to_s.empty? || !available?
    end

    def apply_to_record!(record, attachment_name, preset:, replace: true)
      attached = record.public_send(attachment_name)
      return false unless attached.attached?

      if attached.is_a?(ActiveStorage::Attached::Many)
        blob = attached.blobs.first
        return false unless blob

        apply_blob!(record, attached, blob, preset:, replace:)
      else
        apply_blob!(record, attached, attached.blob, preset:, replace:)
      end
    end

    def apply_blob!(record, attached, blob, preset:, replace:)
      preset = preset.to_s
      return false unless VALID_PRESETS.include?(preset)
      return false if skip?

      Dir.mktmpdir("postpro") do |dir|
        ext = File.extname(blob.filename.to_s).downcase.presence || ".jpg"
        input = File.join(dir, "input#{ext}")
        output = File.join(dir, "output.jpg")

        File.open(input, "wb") { |file| blob.download { |chunk| file.write(chunk) } }
        return false unless run_script(input, output, preset)
        return false unless File.exist?(output) && File.size?(output).positive?

        base = File.basename(blob.filename.to_s, ".*")
        filename = "#{base}_#{preset}.jpg"

        File.open(output, "rb") do |io|
          if attached.is_a?(ActiveStorage::Attached::Many) && replace
            attached.purge
          end
          attached.attach(io:, filename:, content_type: "image/jpeg")
        end
        true
      end
    rescue StandardError => error
      log("postpro failed for #{record.class.name}##{record.id}: #{error.class}: #{error.message}")
      false
    end

    def run_script(input, output, preset)
      system(
        RbConfig.ruby, script.to_s,
        "--input", input, "--output", output, "--preset", preset.to_s,
        out: File::NULL, err: File::NULL
      )
    end

    def log(message)
      return unless defined?(Rails)

      Rails.logger.warn(message)
    end
  end
end
