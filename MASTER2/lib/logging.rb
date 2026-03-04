# frozen_string_literal: true

require "json"
require "active_support/core_ext/module/delegation"

module Logging
  LEVELS = %i[debug info warn error fatal unknown].freeze
  DEFAULT_LEVEL = :info
  MAX_CONTEXT_BYTES = 10_000

  PARENT_FRAGMENT = '", parent: "'
  MESSAGE_FRAGMENT = '", message: "'
  LEVEL_ALL_EVENTS_FRAGMENT = '", level: ALL_EVENTS)'.freeze

  Event = Struct.new(:name, :message, :parent, :level, :context, keyword_init: true)

  class Formatter
    def format(event)
      %(event: "#{event.name}"#{parent_fragment(event.parent)}#{message_fragment(event.message)}#{level_fragment(event.level)}#{context_fragment(event.context)})
    end

    private

    def parent_fragment(parent)
      return "" unless parent

      %(#{PARENT_FRAGMENT}#{parent}")
    end

    def message_fragment(message)
      return "" unless message

      %(#{MESSAGE_FRAGMENT}#{message}")
    end

    def level_fragment(level)
      return "" unless level

      %(", level: #{level})
    end

    def context_fragment(context)
      return "" if context.nil? || context.empty?

      %(", context: #{safe_json(context)})
    end

    def safe_json(obj)
      json = JSON.generate(obj)
      return json if json.bytesize <= MAX_CONTEXT_BYTES

      JSON.generate(truncate_large_context(obj))
    rescue JSON::GeneratorError
      JSON.generate(context: "unserializable")
    end

    def truncate_large_context(obj)
      case obj
      when Hash
        obj.transform_values { |v| truncate_large_context(v) }
      when Array
        obj.take(50).map { |v| truncate_large_context(v) }
      when String
        obj.bytesize > 2_000 ? "#{obj.byteslice(0, 2_000)}..." : obj
      else
        obj
      end
    end
  end

  class EventLogger
    delegate :debug, :info, :warn, :error, :fatal, :unknown, to: :backend

    def initialize(backend:, formatter: Formatter.new)
      @backend = backend
      @formatter = formatter
    end

    def log(event)
      return false unless event && event.name

      level = normalize_level(event.level)
      message = @formatter.format(event)

      backend.public_send(level, message)
      true
    rescue NoMethodError
      backend.public_send(DEFAULT_LEVEL, message)
      true
    end

    def log_event(name:, message: nil, parent: nil, level: nil, context: nil)
      log(
        Event.new(
          name: name,
          message: message,
          parent: parent,
          level: level,
          context: context || {}
        )
      )
    end

    private

    attr_reader :backend

    def normalize_level(level)
      resolved = (level || DEFAULT_LEVEL).to_sym
      return resolved if LEVELS.include?(resolved)

      DEFAULT_LEVEL
    end
  end

  def self.build(backend:, formatter: nil)
    EventLogger.new(backend: backend, formatter: formatter || Formatter.new)
  end

  def self.enabled?(config)
    return false unless config.is_a?(Hash)

    config.fetch(:enabled, true)
  end
end