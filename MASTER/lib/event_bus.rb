# frozen_string_literal: true

require "set"

class EventBus
  def initialize
    @subscribers = Hash.new { |h, k| h[k] = Set.new }
    @mutex = Mutex.new
  end

  def subscribe(event, listener = nil, &block)
    callable = listener || block
    raise ArgumentError, "listener or block required" unless callable

    @mutex.synchronize do
      @subscribers[event.to_sym].add(callable)
    end

    callable
  end

  def unsubscribe(event, listener)
    return unless listener

    @mutex.synchronize do
      @subscribers[event.to_sym].delete(listener)
      @subscribers.delete(event.to_sym) if @subscribers[event.to_sym].empty?
    end

    listener
  end

  def publish(event, payload = nil)
    listeners = listeners_for(event)
    return if listeners.empty?

    listeners.each do |listener|
      begin
        listener.call(payload)
      rescue StandardError => e
        handle_error(e, event, listener, payload)
      end
    end

    nil
  end

  private

  def listeners_for(event)
    @mutex.synchronize do
      @subscribers[event.to_sym].to_a
    end
  end

  def handle_error(error, event, listener, payload)
    raise error
  end
end