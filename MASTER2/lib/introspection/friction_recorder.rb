# frozen_string_literal: true

require "json"
require "time"

module Introspection
  class FrictionRecorder
    DEFAULT_SOURCE = "friction".freeze
    DEFAULT_VERSION = 1

    def initialize(client:, logger:, enabled: true, source: DEFAULT_SOURCE)
      @client = client
      @logger = logger
      @enabled = enabled
      @source = source
    end

    def record(event_name, payload = {})
      return unless @enabled
      return if event_name.nil? || event_name.to_s.empty?

      event = build_event(event_name, payload)

      begin
        @client.write(event)
      rescue StandardError => e
        log_error(e, event: event)
      end
    end

    def record_from_json(event_name, json_payload)
      return unless @enabled
      return if event_name.nil? || event_name.to_s.empty?

      payload = parse_json(json_payload)
      return unless payload

      record(event_name, payload)
    end

    private

    def build_event(event_name, payload)
      {
        version: DEFAULT_VERSION,
        source: @source,
        name: event_name.to_s,
        timestamp: current_timestamp,
        payload: payload
      }
    end

    def current_timestamp(time = Time.now)
      time.utc.iso8601
    end

    def parse_json(json_payload)
      return {} if json_payload.nil? || json_payload == ""

      JSON.parse(json_payload)
    rescue JSON::ParserError => e
      log_error(e, json_payload: json_payload)
      nil
    end

    def log_error(error, context)
      message = "FrictionRecorder error: #{error.class}: #{error.message}"

      if @logger.respond_to?(:error)
        @logger.error(message, context: context)
      else
        warn(message)
      end
    end
  end
end