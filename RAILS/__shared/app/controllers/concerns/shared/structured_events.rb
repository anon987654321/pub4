# frozen_string_literal: true

module Shared
  module StructuredEvents
    extend ActiveSupport::Concern

    private

    def emit_event(name, **payload)
      if defined?(Rails.event) && Rails.event.respond_to?(:notify)
        Rails.event.notify(name, **payload)
      else
        Rails.logger.info({ event: name, payload: }.to_json)
      end
    rescue StandardError => e
      Rails.logger.debug("structured event skipped: #{name} #{e.class}: #{e.message}")
    end
  end
end
