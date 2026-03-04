# frozen_string_literal: true

require "logger"

module Logging
  def self.logger
    @logger ||= Logger.new($stdout)
  end

  def self.warn(message)
    logger.warn(message)
  end

  def self.info(message)
    logger.info(message)
  end
end

module Heartbeat
  DEFAULT_CYCLE_SECONDS = 10
  DEFAULT_MAX_CYCLES = 1_000
  DEFAULT_BATCH_SIZE = 50

  LOG_MESSAGE_SEGMENT = '", message: "'
  LOG_ITEMS_TYPE_SEGMENT = '", items: { type: "'

  class Runner
    def initialize(store:, clock: -> { Time.now }, cycle_seconds: DEFAULT_CYCLE_SECONDS, max_cycles: DEFAULT_MAX_CYCLES)
      @store = store
      @clock = clock
      @cycle_seconds = cycle_seconds
      @max_cycles = max_cycles
      @cycle = nil
    end

    def install_default_cycle(options = {})
      seconds = options.fetch(:seconds, @cycle_seconds)
      batch_size = options.fetch(:batch_size, DEFAULT_BATCH_SIZE)

      return build_cycle(seconds:, batch_size:) unless @cycle

      @cycle = build_cycle(seconds:, batch_size:)
    rescue StandardError => e
      Logging.warn(%(Heartbeat.install_default_cycle failed: #{e.class}: #{e.message}))
      nil
    end

    def run_loop(options = {})
      cycles = options.fetch(:cycles, @max_cycles)
      return nil unless cycles.to_i.positive?

      install_default_cycle(options)
      return nil unless @cycle

      cycles.to_i.times do
        tick!
        sleep(@cycle[:seconds])
      end
    rescue StandardError => e
      Logging.warn(%(Heartbeat.run_loop failed: #{e.class}: #{e.message}))
      nil
    end

    def tick!
      return nil unless @cycle

      items = load_items(@cycle.fetch(:batch_size, DEFAULT_BATCH_SIZE))
      selection = adversarial_reason_and_select(items)
      learn(selection) if selection
      selection
    rescue StandardError => e
      Logging.warn(%(Heartbeat.tick! failed: #{e.class}: #{e.message}))
      nil
    end

    def adversarial_reason_and_select(items)
      return nil if items.nil? || items.empty?

      review = heuristic_adversarial_review(items)
      candidate = review.fetch(:candidate, nil)
      reason = review.fetch(:reason, "no_reason")

      return nil unless candidate

      log_selection(candidate, reason)
      { item: candidate, reason: }
    end

    def heuristic_adversarial_review(items)
      candidate = items.compact.first
      return { candidate: nil, reason: "empty" } unless candidate

      risky = candidate.respond_to?(:risk_score) ? candidate.risk_score.to_f : 0.0
      reason = risky.positive? ? "risk_score" : "first_item"
      { candidate:, reason: }
    rescue StandardError => e
      Logging.warn(%(Heartbeat.heuristic_adversarial_review failed: #{e.class}: #{e.message}))
      { candidate: nil, reason: "error" }
    end

    def learn(selection)
      return nil unless selection

      item = selection.fetch(:item, nil)
      return nil unless item

      @store.record_learning(item, selection.fetch(:reason, "unknown"), at: @clock.call)
    rescue StandardError => e
      Logging.warn(%(Heartbeat.learn failed: #{e.class}: #{e.message}))
      nil
    end

    private

    def build_cycle(seconds:, batch_size:)
      {
        seconds: seconds.to_i,
        batch_size: batch_size.to_i
      }
    end

    def load_items(batch_size)
      scope = @store.items_scope
      scope = scope.includes(:association) if scope.respond_to?(:includes)
      scope.limit(batch_size)
    rescue StandardError => e
      Logging.warn(%(Heartbeat.load_items failed: #{e.class}: #{e.message}))
      []
    end

    def log_selection(item, reason)
      id = item.respond_to?(:id) ? item.id : item.to_s
      type = item.respond_to?(:class) ? item.class.name : "Unknown"
      Logging.info(%(Heartbeat selected id: "#{id}#{LOG_MESSAGE_SEGMENT}#{reason}#{LOG_ITEMS_TYPE_SEGMENT}#{type}" }))
    end
  end
end