# frozen_string_literal: true

require "open-uri"
require "stringio"

module Brgen
  module DemoMedia
    module_function

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
      Rails.logger.warn("DemoMedia attach failed (#{seed}): #{error.class}: #{error.message}") if defined?(Rails)
      false
    end

    def skip_attach?
      ENV["SKIP_DEMO_MEDIA"].present? || (defined?(Rails) && Rails.env.test?)
    end
  end
end