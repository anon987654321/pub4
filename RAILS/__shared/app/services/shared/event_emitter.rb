# frozen_string_literal: true

module Shared
  class EventEmitter
    def self.call(name, **payload)
      new(name, **payload).call
    end

    def initialize(name, **payload)
      @name = name.to_s
      @payload = payload
    end

    def call
      if defined?(Rails.event) && Rails.event.respond_to?(:notify)
        Rails.event.tagged("pub4") do
          Rails.event.notify(name, **payload)
        end
      else
        Rails.logger.info({ event: name, payload: }.to_json)
      end
      true
    rescue StandardError => e
      Rails.logger.debug("event skipped #{name}: #{e.class}: #{e.message}")
      false
    end

    private

    attr_reader :name, :payload
  end
end
