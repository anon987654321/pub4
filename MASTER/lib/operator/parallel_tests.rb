# frozen_string_literal: true

require "fileutils"

module Operator
  # The MASTER suite across several processes. Workers are polled rather than
  # waited on synchronously, so a hung worker cannot hide its identity forever.
  module ParallelTests
    LOG_DIR = File.expand_path("../../.master/check", __dir__)
    RESULT_LINE = /\A\S+#\S+ = [\d.]+ s = [.FES]\s*\z/
    REPORT_START = /\AFinished in /
    SUMMARY_LINE = /\A\d+ runs?, \d+ assertions?, \d+ failures?, \d+ errors?, \d+ skips?\s*\z/i
    DEFAULT_WORKER_TIMEOUT = 1800
    POLL_INTERVAL = 0.1

    module_function

    def jobs = [Integer(ENV.fetch("MASTER_TEST_JOBS", "3"), exception: false) || 3, 1].max

    def worker_timeout
      value = Float(ENV.fetch("MASTER_TEST_WORKER_TIMEOUT", DEFAULT_WORKER_TIMEOUT), exception: false)
      value && value.positive? ? value : DEFAULT_WORKER_TIMEOUT
    end

    def deal(files, count)
      buckets = Array.new(count) { [] }
      loads = Array.new(count, 0)
      weight = ->(path) { File.size?(path).to_i + 1 }
      files.sort_by { |path| -weight.call(path) }.each do |path|
        lightest = loads.index(loads.min)
        buckets[lightest] << path
        loads[lightest] += weight.call(path)
      end
      buckets.reject(&:empty?)
    end

    def run(files, command:, out: $stdout)
      FileUtils.mkdir_p(LOG_DIR)
      workers = deal(files, jobs).each_with_index.map do |bucket, index|
        start(bucket, log: File.join(LOG_DIR, "test-worker-#{index + 1}.log"), command:)
      end

      relay_errors = Queue.new
      relay = Thread.new do
        begin
          relay_results(workers, out) { workers.all? { |worker| worker[:status] } }
        rescue StandardError => error
          relay_errors << "#{error.class}: #{error.message}"
        end
      end

      until workers.all? { |worker| worker[:status] }
        workers.each { |worker| poll(worker, out) unless worker[:status] }
        begin
          out.puts "test-relay0: #{relay_errors.pop(true)}"
        rescue ThreadError
          # No relay error was queued.
        end
        sleep POLL_INTERVAL unless workers.all? { |worker| worker[:status] }
      end

      relay.join
      begin
        out.puts "test-relay0: #{relay_errors.pop(true)}"
      rescue ThreadError
        # No relay error was queued.
      end
      workers.each { |worker| worker[:summary_present] = summary_present?(worker) }
      report(workers, out)
      workers.all? { |worker| worker[:status]&.success? && !worker[:timed_out] && worker[:summary_present] }
    ensure
      workers&.each { |worker| terminate(worker) unless worker[:status] }
    end

    def start(bucket, log:, command:)
      marker_setting = ENV.fetch("MASTER_TEST_START_MARKERS", "1")
      env = { "MASTER_TEST_START_MARKERS" => marker_setting }
      pid = Process.spawn(env, *command.call(bucket), out: log, err: %i[child out], in: File::NULL, pgroup: true)
      {
        pid:, log:, offset: 0, started_at: Process.clock_gettime(Process::CLOCK_MONOTONIC),
        status: nil, timed_out: false, start_markers: marker_setting == "1"
      }
    end

    def poll(worker, out)
      result = Process.waitpid2(worker.fetch(:pid), Process::WNOHANG)
      if result
        worker[:status] = result.last
        return
      end

      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - worker.fetch(:started_at)
      return if elapsed <= worker_timeout

      worker[:timed_out] = true
      File.open(worker.fetch(:log), "a") do |file|
        file.puts "test-worker-timeout0: exceeded #{worker_timeout}s; terminating process group"
      end
      last_test = last_started_test(worker)
      out.puts "test-worker-timeout0: pid=#{worker.fetch(:pid)} elapsed=#{elapsed.round(1)}s last_test=#{last_test || "unknown"} log=#{worker.fetch(:log)}"
      terminate(worker)
    end

    def terminate(worker)
      pid = worker.fetch(:pid)
      begin
        Process.kill("TERM", -pid)
      rescue Errno::ESRCH
        # The worker exited between the poll and signal.
      end

      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
      loop do
        result = Process.waitpid2(pid, Process::WNOHANG)
        if result
          worker[:status] = result.last
          return
        end
        break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        sleep 0.05
      end

      begin
        Process.kill("KILL", -pid)
      rescue Errno::ESRCH
        # Already gone.
      end
      _pid, status = Process.waitpid2(pid)
      worker[:status] = status
    rescue Errno::ECHILD
      worker[:status] ||= nil
    end

    def relay_results(workers, out)
      until yield
        relay_once(workers, out)
        sleep 1
      end
      relay_once(workers, out)
    end

    def relay_once(workers, out)
      workers.each { |worker| fresh_lines(worker).grep(RESULT_LINE).each { |line| out.puts line } }
      out.flush
    end

    def fresh_lines(worker)
      text = File.open(worker.fetch(:log), "rb") { |file| file.seek(worker.fetch(:offset)) && file.read.to_s }
      complete = String.new(text[/\A.*\n/m].to_s)
      worker[:offset] += complete.bytesize
      complete.force_encoding(Encoding::UTF_8).scrub.lines(chomp: true)
    end

    def last_started_test(worker)
      last = nil
      File.foreach(worker.fetch(:log), encoding: "UTF-8", invalid: :replace, undef: :replace) do |line|
        last = line.delete_prefix("test-start0: ").strip if line.start_with?("test-start0: ")
      end
      last
    rescue Errno::ENOENT
      nil
    end

    def summary_present?(worker)
      result_count = 0
      start_count = 0
      summary_runs = nil

      File.foreach(worker.fetch(:log), encoding: "UTF-8", invalid: :replace, undef: :replace) do |raw_line|
        line = raw_line.chomp
        result_count += 1 if RESULT_LINE.match?(line)
        start_count += 1 if line.start_with?("test-start0: ")
        summary_runs = line[/\A(\d+) runs?/, 1].to_i if SUMMARY_LINE.match?(line)
      end

      return false unless summary_runs == result_count
      return false if worker[:start_markers] && start_count != result_count

      true
    rescue Errno::ENOENT
      false
    end

    def report(workers, out)
      workers.each_with_index do |worker, index|
        lines = File.read(worker.fetch(:log), encoding: "UTF-8", invalid: :replace, undef: :replace).lines
        start = lines.index { |line| line.match?(REPORT_START) } || [lines.size - 40, 0].max
        suffix = []
        suffix << "TIMEOUT" if worker[:timed_out]
        suffix << "INCOMPLETE" unless worker[:summary_present]
        label = suffix.empty? ? "" : ", #{suffix.join(", ")}"
        out.puts "", "worker #{index + 1} of #{workers.size} (pid #{worker.fetch(:pid)}#{label}):", *lines.drop(start).map(&:chomp)
        out.puts "test-worker-incomplete0: missing final Minitest summary" unless worker[:summary_present]
      end
    end
  end
end
