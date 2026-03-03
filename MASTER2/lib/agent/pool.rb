# frozen_string_literal: true

require "etc"
require "timeout"

module Agent
  class Pool
    DEFAULT_POOL_SIZE = 5
    DEFAULT_TIMEOUT_SECONDS = 30
    JOIN_TIMEOUT_SECONDS = 0.1

    def initialize(size: DEFAULT_POOL_SIZE, logger: nil)
      @size = Integer(size)
      @logger = logger
    end

    def run_all(jobs, timeout: DEFAULT_TIMEOUT_SECONDS)
      return [] if jobs.nil? || jobs.empty?

      queue = build_queue(jobs)
      workers = start_workers(queue)
      results = collect_results(workers, timeout: timeout)

      stop_workers(workers, queue)
      results
    end

    private

    def build_queue(jobs)
      Queue.new.tap { |q| jobs.each { |job| q << job } }
    end

    def start_workers(queue)
      Array.new([@size, queue.size].min) do
        Thread.new { worker_loop(queue) }
      end
    end

    def worker_loop(queue)
      loop do
        job = queue.pop
        break if job.equal?(:__stop__)

        job.call
      rescue StandardError => e
        log_error(e)
      end
    end

    def collect_results(workers, timeout:)
      Timeout.timeout(timeout) { workers.each { |t| t.join } }
      []
    rescue Timeout::Error => e
      log_error(e)
      []
    end

    def stop_workers(workers, queue)
      workers.size.times { queue << :__stop__ }
      workers.each { |t| t.join(JOIN_TIMEOUT_SECONDS) rescue nil }
    end

    def log_error(error)
      return unless @logger

      @logger.error(error.message)
    rescue StandardError
      nil
    end
  end
end