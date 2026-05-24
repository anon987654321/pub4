# frozen_string_literal: true

module Converge
  class EventStream
    attr_reader :log

    def initialize
      @subscribers = []
      @log = []
    end

    def emit(event_type, payload = {})
      entry = { type: event_type.to_sym, payload: payload, timestamp: Time.now.utc }
      @log << entry
      @subscribers.each { |subscriber| subscriber.call(entry) }
      entry
    end

    def subscribe(&block)
      @subscribers << block if block
    end

    def <<(entry)
      emit(entry.fetch(:type), entry.fetch(:payload, entry.reject { |key, _| key == :type }))
    end
  end
end
