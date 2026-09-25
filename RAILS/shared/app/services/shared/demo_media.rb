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
      # A catalogue frame marked graded left STUDIO already through postpro, and
      # a second pass stacks a second grain field and curve on the first.
      return true if Catalog.resolve(seed, catalog:)&.dig("graded")

      Shared::PostproProcessor.apply_to_record!(record, attachment_name, preset:, replace: true)
    end

    # The catalogue alone, with no picsum fallback: for bulk seeds that would
    # otherwise fetch hundreds of stock photographs, and for records that are
    # better with no picture than with an unrelated one.
    def attach_catalog!(record, attachment_name, seed:, catalog: nil)
      return false if skip_attach?

      attach_from_catalog!(record, attachment_name, seed:, catalog:)
    rescue StandardError => error
      log("DemoMedia catalog attach failed (#{seed}): #{error.class}: #{error.message}")
      false
    end

    def attach_from_catalog!(record, attachment_name, seed:, content_type: "image/jpeg", catalog: nil)
      entry = Catalog.resolve(seed, catalog:)
      return false unless entry

      if entry["url"].present?
        attach_from_url!(record, attachment_name, url: entry["url"], seed:, content_type:)
      elsif entry["file"].present?
        path = Catalog.file_path(entry["file"], catalog:)
        # A missing frame is a skip, never a raise: a seed failure blocks every
        # deploy, and a catalogue row can outlive its file on a partial checkout.
        unless path
          message = "DemoMedia: #{seed} names #{entry['file']}, which is not on disk — skipped"
          warn(message)
          log(message)
          return false
        end

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
      # Read into memory, not handed over as an open File: on an unsaved record
      # Active Storage uploads at save, after a File.open block has closed it.
      record.public_send(attachment_name).attach(
        io: StringIO.new(File.binread(path)),
        filename: "#{seed}#{File.extname(path)}",
        content_type:,
      )
      true
    end
  end
end
