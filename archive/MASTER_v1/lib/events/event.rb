# frozen_string_literal: true

require 'securerandom'

module MASTER
  module Events
    # Base Event class - immutable event object
    class Event
      attr_reader :type, :data, :timestamp, :id

      def initialize(type:, data: {}, timestamp: Time.now, id: nil)
        @type = type.to_sym
        @data = data.freeze
        @timestamp = timestamp
        @id = id || SecureRandom.hex(8)
        freeze
      end

      def to_h
        {
          type: @type,
          data: @data,
          timestamp: @timestamp,
          id: @id
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
