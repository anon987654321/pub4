# frozen_string_literal: true

require "open-uri"
require "stringio"

module Shared
  # Remote placeholder images for demo seeds (picsum) with optional postpro grading.
  module DemoMedia
    extend self

    def attach_remote!(record, attachment_name, seed:, width: 800, height: 600, content_type: "image/jpeg")
      return false if skip_attach?

      url = "https://picsum.photos/seed/#{seed}/#{width}/#{height}"
      io = URI.open(url, read_timeout: 8, open_timeout: 8) # rubocop:disable Security/Open
      filename = "#{seed}-#{width}x#{height}.jpg"

      record.public_send(attachment_name).attach(
        io: StringIO.new(io.read),
        filename: filename,
        content_type: content_type
      )
      true
    rescue StandardError => error
      log("DemoMedia attach failed (#{seed}): #{error.class}: #{error.message}")
      false
    end

    def attach_remote_postpro!(record, attachment_name, seed:, preset:, width: 800, height: 600)
      return false unless attach_remote!(record, attachment_name, seed:, width:, height:)

      Shared::PostproProcessor.apply_to_record!(record, attachment_name, preset:, replace: true)
    end

    def skip_attach?
      !ENV.fetch("SKIP_DEMO_MEDIA", "").to_s.empty? || (defined?(Rails) && Rails.env.test?)
    end

    def log(message)
      return unless defined?(Rails)

      Rails.logger.warn(message)
    end
  end
end