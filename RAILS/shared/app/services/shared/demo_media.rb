# frozen_string_literal: true

require "open-uri"
require "pathname"
require "stringio"
require_relative "demo_media/catalog"

module Shared
  # Remote placeholder images for demo seeds (catalog → picsum) with optional postpro grading.
  module DemoMedia
    extend self

    def attach_remote!(record, attachment_name, seed:, width: 800, height: 600, content_type: "image/jpeg",
catalog: nil)
      return false if skip_attach?

      return true if attach_from_catalog!(record, attachment_name, seed:, content_type:, catalog:)

      url = "https://picsum.photos/seed/#{seed}/#{width}/#{height}"
      attach_from_url!(record, attachment_name, url:, seed:, content_type:)
    rescue StandardError => error
      log("DemoMedia attach failed (#{seed}): #{error.class}: #{error.message}")
      false
    end

    def attach_remote_postpro!(record, attachment_name, seed:, preset:, width: 800, height: 600, catalog: nil)
      return false unless attach_remote!(record, attachment_name, seed:, width:, height:, catalog:)

      Shared::PostproProcessor.apply_to_record!(record, attachment_name, preset:, replace: true)
    end

    def attach_from_catalog!(record, attachment_name, seed:, content_type: "image/jpeg", catalog: nil)
      entry = Catalog.resolve(seed, catalog:)
      return false unless entry

      if entry["url"].present?
        attach_from_url!(record, attachment_name, url: entry["url"], seed:, content_type:)
      elsif entry["file"].present?
        path = Catalog.file_path(entry["file"], catalog:)
        return false unless path

        attach_from_file!(record, attachment_name, path:, seed:, content_type:)
      else
        false
      end
    end

    def skip_attach?
      !ENV.fetch("SKIP_DEMO_MEDIA", "").to_s.empty? || (defined?(Rails) && Rails.env.test?)
    end

    def log(message)
      return unless defined?(Rails)

      Rails.logger.warn(message)
    end

    private

    def attach_from_url!(record, attachment_name, url:, seed:, content_type:)
      io = URI.open(url, read_timeout: 12, open_timeout: 12, "User-Agent" => user_agent) # rubocop:disable Security/Open
      filename = "#{seed}.jpg"

      record.public_send(attachment_name).attach(
        io: StringIO.new(io.read),
        filename:,
        content_type:,
      )
      true
    end

    def user_agent
      ENV.fetch("DEMO_MEDIA_USER_AGENT", "BrgenDemoSeed/1.0 (+https://brgen.no; demo content)")
    end

    def attach_from_file!(record, attachment_name, path:, seed:, content_type:)
      File.open(path, "rb") do |io|
        record.public_send(attachment_name).attach(
          io:,
          filename: "#{seed}#{File.extname(path)}",
          content_type:,
        )
      end
      true
    end
  end
end
