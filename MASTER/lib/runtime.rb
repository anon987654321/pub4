# frozen_string_literal: true

require "digest"
require "etc"
require "json"
require "timeout"

module Master
  module Runtime
    module Benchmark
      module_function

      def measure(label:, repeats: 1)
        count = Integer(repeats)
        raise ArgumentError, "repeats must be positive" unless count.positive?
        samples = []
        digest = nil
        count.times do
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          value = yield
          samples << Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          digest = output_digest(value)
        end
        {
          label: label.to_s,
          repeats: count,
          wall_ms: (samples.sum / count * 1000).round(3),
          min_ms: (samples.min * 1000).round(3),
          max_ms: (samples.max * 1000).round(3),
          output_digest: digest,
        }.freeze
      end

      def compare(before, after)
        before_digest = before.fetch(:output_digest)
        after_digest = after.fetch(:output_digest)
        before_ms = before.fetch(:wall_ms).to_f
        after_ms = after.fetch(:wall_ms).to_f
        {
          output_equal: before_digest == after_digest,
          before_ms:,
          after_ms:,
          ratio: before_ms.positive? ? (after_ms / before_ms).round(4) : nil,
          regression: before_ms.positive? && after_ms > before_ms,
        }.freeze
      end

      def output_digest(value)
        Digest::SHA256.hexdigest(JSON.generate(canonicalize(value)))
      end

      def canonicalize(value)
        case value
        when Hash
          value.keys.sort_by(&:to_s).to_h { |key| [key.to_s, canonicalize(value[key])] }
        when Array
          value.map { |entry| canonicalize(entry) }
        when Symbol
          value.to_s
        else
          value
        end
      end
      private_class_method :canonicalize
    end

    module Compute
      DEFAULT_WORKER_LIMIT = 8
      DEFAULT_TIMEOUT_SECONDS = 30

      class Error < StandardError; end
      class ExecutionError < Error
        attr_reader :index, :operation
        def initialize(index:, operation:, message:)
          @index = index
          @operation = operation
          super("#{operation} job #{index}: #{message}")
        end
      end
      class TimeoutError < Error
        attr_reader :timeout
        def initialize(timeout)
          @timeout = timeout
          super("compute timed out after #{timeout}s")
        end
      end

      module_function

      def map(items, backend: :auto, operation: nil, workers: nil, timeout: DEFAULT_TIMEOUT_SECONDS, &block)
        values = Array(items)
        return [] if values.empty?
        selected = resolve_backend(values, backend, operation)
        if %i[serial thread].include?(selected)
          raise ArgumentError, "compute requires a block for #{selected}" unless block
        end
        case selected
        when :serial then values.map.with_index { |item, index| block.call(item, index) }
        when :thread then thread_map(values, workers:, timeout:, &block)
        when :ractor
          raise ArgumentError, "ractor backend requires an operation" if operation.nil?
          ractor_map(values, operation:, workers:, timeout:)
        else
          raise ArgumentError, "unknown compute backend #{selected.inspect}"
        end
      end

      def resolve_backend(items, backend, operation)
        selected = backend.to_sym
        return selected unless selected == :auto
        return :ractor if ractor_available? && operation == :invoke && items.all? { |item| valid_invoke_job?(item) }
        :thread
      end

      def ractor_available?
        defined?(Ractor) && Ractor.respond_to?(:new) && Ractor.respond_to?(:select)
      end

      def valid_invoke_job?(item)
        item.is_a?(Array) && item.size == 3 &&
          item[0].is_a?(String) && item[1].is_a?(String) &&
          item[0].start_with?("Master::") && item[1] == "ractor_call"
      end

      def thread_map(items, workers:, timeout:, &block)
        worker_count = worker_limit(items.size, workers)
        cursor = -1
        mutex = Mutex.new
        results = Array.new(items.size)
        failures = []
        threads = Array.new(worker_count) do
          Thread.new do
            loop do
              index = mutex.synchronize { cursor += 1; cursor }
              break if index >= items.size
              results[index] = block.call(items[index], index)
            rescue StandardError => e
              mutex.synchronize { failures << [index, e] }
            end
          end
        end
        timed_out = false
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        threads.each do |thread|
          remaining = [deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max
          next if thread.join(remaining)
          timed_out = true
          thread.kill if thread.alive?
        end
        threads.each { |thread| thread.join(0.1) if thread.alive? }
        raise TimeoutError, timeout if timed_out
        return results if failures.empty?
        index, error = failures.min_by(&:first)
        raise ExecutionError.new(index:, operation: "thread", message: "#{error.class}: #{error.message}")
      end

      def ractor_map(items, operation:, workers:, timeout:)
        jobs = prepare_ractor_jobs(items)
        ractors = spawn_ractors(operation, worker_limit(jobs.size, workers))
        seed_ractors(ractors, jobs)
        collect_ractor_results(ractors, jobs, timeout)
      ensure
        stop_ractors(ractors)
      end

      def prepare_ractor_jobs(items)
        invalid = items.index { |item| !valid_invoke_job?(item) }
        raise ArgumentError, "invalid ractor invoke job at #{invalid}" if invalid
        items.map { |item| Ractor.make_shareable(item, copy: true) }
      end

      def spawn_ractors(operation, worker_count)
        Array.new(worker_count) do |worker_id|
          Ractor.new(operation.to_sym, worker_id) { |op, id| Master::Runtime::Compute.ractor_loop(op, id) }
        end
      end

      def ractor_loop(operation, worker_id)
        loop do
          message = Ractor.receive
          break if message == :stop
          job_index, payload = message
          ractor_process(worker_id, job_index, operation, payload)
        end
      end

      def ractor_process(worker_id, job_index, operation, payload)
        result = invoke(operation, payload)
        Ractor.yield([worker_id, job_index, true, Ractor.make_shareable(result, copy: true)])
      rescue StandardError, SecurityError => e
        error = { "class" => e.class.name.to_s, "message" => e.message.to_s }.freeze
        Ractor.yield([worker_id, job_index, false, error])
      end

      def seed_ractors(ractors, jobs)
        jobs.each_with_index.take(ractors.size).each { |(job, index)| ractors[index].send([index, job]) }
      end

      def collect_ractor_results(ractors, jobs, timeout)
        results = Array.new(jobs.size)
        active = (0...[ractors.size, jobs.size].min).to_h { |index| [index, ractors[index]] }
        next_index = active.size
        Timeout.timeout(timeout) do
          until active.empty?
            ractor, message = Ractor.select(*ractors)
            _worker_id, index, ok, value = message
            active.delete(index)
            results[index] = ractor_result!(ok, index, value)
            next_index = refill_ractor(ractor, next_index, jobs, active)
          end
        end
        results
      rescue Timeout::Error
        kill_ractors(ractors)
        raise TimeoutError, timeout
      end

      def kill_ractors(ractors)
        ractors.each { |ractor| ractor.kill rescue nil }
      end

      def ractor_result!(ok, index, value)
        return value if ok
        raise ExecutionError.new(index:, operation: "invoke", message: "#{value.fetch("class")}: #{value.fetch("message")}")
      end

      def refill_ractor(ractor, next_index, jobs, active)
        return next_index if next_index >= jobs.size
        ractor.send([next_index, jobs[next_index]])
        active[next_index] = ractor
        next_index + 1
      end

      def stop_ractors(ractors)
        return unless ractors
        ractors.each { |ractor| stop_ractor(ractor) }
      end

      def stop_ractor(ractor)
        ractor.send(:stop)
      rescue StandardError
        nil
      ensure
        ractor.take rescue nil
      end

      def invoke(operation, payload)
        raise Error, "unsupported ractor operation #{operation.inspect}" unless operation.to_sym == :invoke
        raise SecurityError, "ractor target outside Master namespace" unless payload.is_a?(Array)
        qualified_name, method_name, argument = payload
        unless qualified_name.is_a?(String) && qualified_name.start_with?("Master::") && method_name == "ractor_call"
          raise SecurityError, "invalid ractor target"
        end
        constant = qualified_name.split("::").reject(&:empty?).reduce(Object) { |scope, name| scope.const_get(name, false) }
        constant.public_send(method_name, argument)
      end

      def worker_limit(item_count, workers)
        requested = Integer(workers || Etc.nprocessors)
        [[requested, 1].max, DEFAULT_WORKER_LIMIT, item_count].min
      end
    end

    module Jit
      MODES = %w[auto off yjit].freeze
      module_function

      def mode
        configured = ENV.fetch("MASTER_JIT", "auto").to_s.strip.downcase
        return configured if MODES.include?(configured)
        warn("jit0: unknown MASTER_JIT=#{configured.inspect} — using auto")
        "auto"
      end

      def available?
        defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enable) && RubyVM::YJIT.respond_to?(:runtime_stats)
      end

      def enabled?
        available? && RubyVM::YJIT.respond_to?(:enabled?) && RubyVM::YJIT.enabled?
      end

      def constrained?
        Master::Ground::HostBudget.constrained?
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.constrained?")
        false
      end

      def auto_allowed?
        available? && !constrained? && !RUBY_PLATFORM.include?("android")
      end

      def apply!
        case mode
        when "off" then false
        when "yjit" then enable!(reason: "forced")
        else return false unless auto_allowed?; enable!(reason: "auto")
        end
      end

      def enable!(reason: "manual")
        return true if enabled?
        return false unless available?
        RubyVM::YJIT.enable
        warn("jit0: yjit enabled (#{reason})")
        true
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.enable!")
        warn("jit0: yjit unavailable — #{e.class}: #{e.message}")
        false
      end

      def stats
        return {} unless available?
        RubyVM::YJIT.runtime_stats || {}
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::Jit.stats")
        {}
      end

      def snapshot
        { mode:, available: available?, enabled: enabled?, constrained: constrained?, stats: stats }.freeze
      end
    end

    module NativeInventory
      module_function

      def specs
        Gem::Specification.to_a
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "Runtime::NativeInventory.specs")
        []
      end

      def native?(spec)
        Array(spec.extensions).any?
      end

      def rows
        specs.filter_map do |spec|
          next unless native?(spec)
          {
            name: spec.name.to_s,
            version: spec.version.to_s,
            extensions: Array(spec.extensions).map(&:to_s).freeze,
            ractor_safety: ractor_safety(spec),
          }.freeze
        end
      end

      def ractor_safety(spec)
        metadata = spec.respond_to?(:metadata) ? spec.metadata : {}
        return "safe" if metadata["ractor_safe"].to_s == "true"
        return "unsafe" if metadata["ractor_safe"].to_s == "false"
        "unknown"
      end

      def snapshot
        native = rows
        {
          native_gems: native.size,
          unknown_ractor_safety: native.count { |row| row[:ractor_safety] == "unknown" },
          gems: native,
        }.freeze
      end
    end
  end
end
