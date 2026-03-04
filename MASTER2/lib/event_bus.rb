# frozen_string_literal: true

require "set"

class EventBus
  Subscriber = Struct.new(:owner, :handler)

  class << self
    def subscribe(event, listener = nil, subscriber: nil, &block)
      instance.subscribe(event, listener, subscriber: subscriber, &block)
    end

    def unsubscribe(subscriber)
      instance.unsubscribe(subscriber)
    end

    def publish(event, payload = nil)
      instance.publish(event, payload)
    end

    def clear!
      instance.clear!
    end

    def registered
      instance.registered
    end

    private

    def instance
      @instance ||= new
    end
  end

  def initialize
    @subscribers = Hash.new { |h, k| h[k] = Set.new }
    @mutex = Mutex.new
  end

  def subscribe(event, listener = nil, subscriber: nil, &block)
    callable = listener || block
    raise ArgumentError, "listener or block required" unless callable

    @mutex.synchronize do
      @subscribers[event.to_sym].add(Subscriber.new(subscriber, callable))
    end

    callable
  end

  def unsubscribe(subscriber)
    return unless subscriber

    @mutex.synchronize do
      @subscribers.each_value { |listeners| listeners.delete_if { |entry| entry.owner == subscriber } }
      @subscribers.delete_if { |_event, listeners| listeners.empty? }
    end

    subscriber
  end

  def publish(event, payload = nil)
    listeners_for(event).each do |entry|
      begin
        entry.handler.call(payload)
      rescue StandardError
        # swallow handler errors to avoid disrupting callers
      end
    end

    nil
  end

  def clear!
    @mutex.synchronize { @subscribers.clear }
  end

  def registered
    @mutex.synchronize { @subscribers.keys }
  end

  private

  def listeners_for(event)
    @mutex.synchronize do
      @subscribers[event.to_sym].to_a
    end
  end
end
