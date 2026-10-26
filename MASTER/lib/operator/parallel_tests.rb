# frozen_string_literal: true

require "fileutils"
require "json"

module Operator
  # The MASTER suite across several processes. Workers are polled rather than
  # waited on synchronously, so a hung worker cannot hide its identity forever.
  module ParallelTests
    # The suite under test runs its own runner; it keeps its logs and lock apart (test_helper).
    LOG_DIR = ENV.fetch("MASTER_CHECK_LOG_DIR") { File.expand_path("../../.master/check", __dir__) }
    RESULT_LINE = /\A\S+#\S+ = [\d.]+ s = [.FES]\s*\z/
    REPORT_START = /\AFinished in /
    SUMMARY_LINE = /\A(\d+) runs?, (\d+) assertions?, (\d+) failures?, (\d+) errors?, (\d+) skips?\s*\z/i
    DEFAULT_WORKER_TIMEOUT = 1800
    POLL_INTERVAL = 0.1

    module_function

    def jobs = [Integer(ENV.fetch("MASTER_TEST_JOBS", "3"), exception: false) || 3, 1].max

    # Read at run time so a test or caller can change the cadence after require.
    # Zero disables progress output; completed results remain available in JSON.
    def progress_every
      value = Integer(ENV.fetch("MASTER_TEST_PROGRESS_EVERY", "50"), exception: false)
      value && value >= 0 ? value : 50
    end

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

    # One suite at a time per checkout: the worker logs and suite-report.json have fixed
    # names, so a second suite overwrote the first one's evidence, and two suites on this
    # 8 GB machine starve each other. A held lock refuses rather than waits.
    def run(files, command:, out: $stdout)
      FileUtils.mkdir_p(LOG_DIR)
      File.open(File.join(LOG_DIR, "suite.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          out.puts "test-suite0: another suite holds #{LOG_DIR}/suite.lock (pid #{lock.read.strip}); not starting"
          return false
        end
        lock.truncate(0)
        lock.write(Process.pid.to_s)
        lock.flush
        run_locked(files, command:, out:)
      end
    end

    def run_locked(files, command:, out:)
      workers = deal(files, jobs).each_with_index.map do |bucket, index|
        start(bucket, log: File.join(LOG_DIR, "test-worker-#{index + 1}.log"), command:)
      end

      relay_errors = Queue.new
      progress = { completed: 0, last_emitted: 0, every: progress_every }
      relay = Thread.new do
        begin
          relay_results(workers, out, progress) { workers.all? { |worker| worker[:status] } }
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
      workers.each do |worker|
        worker[:summary] = summary_data(worker)
        worker[:summary_present] = !worker[:summary].nil?
        worker[:failure_result_lines] = worker_failures(worker)
      end
      write_suite_report(workers, progress[:completed], out)
      report(workers, out)
      workers.all? do |worker|
        summary = worker[:summary]
        worker[:status]&.success? && !worker[:timed_out] && worker[:summary_present] &&
          worker[:failure_result_lines].empty? && summary["failures"].zero? && summary["errors"].zero?
      end
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

    def relay_results(workers, out, progress)
      until yield
        relay_once(workers, out, progress)
        sleep 1
      end
      relay_once(workers, out, progress)
    end

    def relay_once(workers, out, progress)
      workers.each do |worker|
        fresh_lines(worker).grep(RESULT_LINE).each do |line|
          out.puts line
          progress[:completed] += 1
          if progress[:every].positive? && progress[:completed] - progress[:last_emitted] >= progress[:every]
            progress[:last_emitted] = progress[:completed]
            out.puts "test-progress0: completed_results=#{progress[:completed]}"
          end
        end
      end
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

    def summary_data(worker)
      result_count = 0
      start_count = 0
      summary = nil

      File.foreach(worker.fetch(:log), encoding: "UTF-8", invalid: :replace, undef: :replace) do |raw_line|
        line = raw_line.chomp
        result_count += 1 if RESULT_LINE.match?(line)
        start_count += 1 if line.start_with?("test-start0: ")
        if (match = SUMMARY_LINE.match(line))
          summary = {
            "runs" => match[1].to_i,
            "assertions" => match[2].to_i,
            "failures" => match[3].to_i,
            "errors" => match[4].to_i,
            "skips" => match[5].to_i
          }
        end
      end

      return nil unless summary && summary["runs"] == result_count
      return nil if worker[:start_markers] && start_count != result_count

      summary.merge("result_lines" => result_count, "start_markers" => start_count)
    rescue Errno::ENOENT
      nil
    end

    def summary_present?(worker) = !summary_data(worker).nil?

    def worker_failures(worker)
      failures = []
      File.foreach(worker.fetch(:log), encoding: "UTF-8", invalid: :replace, undef: :replace) do |raw_line|
        line = raw_line.chomp
        failures << line if RESULT_LINE.match?(line) && line.match?(/ = [FE]\s*\z/)
      end
      failures
    rescue Errno::ENOENT
      []
    end

    def worker_outcome(worker)
      summary = worker[:summary]
      return "timeout" if worker[:timed_out]
      return "incomplete" unless worker[:summary_present]
      return "failed" unless worker[:status]&.success?
      return "failed" unless worker[:failure_result_lines].empty?
      return "failed" if summary["failures"].positive? || summary["errors"].positive?

      "passed"
    end

    def write_suite_report(workers, completed_results, out)
      payload = {
        "schema" => 1,
        "status" => (workers.all? { |worker| worker_outcome(worker) == "passed" } ? "passed" : "failed_or_incomplete"),
        "completed_results_relayed" => completed_results,
        "jobs" => workers.size,
        "workers" => workers.each_with_index.map do |worker, index|
          {
            "index" => index + 1,
            "pid" => worker[:pid],
            "log" => worker[:log],
            "exit_status" => worker[:status]&.exitstatus,
            "success" => worker[:status]&.success? || false,
            "timed_out" => !!worker[:timed_out],
            "outcome" => worker_outcome(worker),
            "summary_present" => !!worker[:summary_present],
            "summary" => worker[:summary],
            "last_started_test" => last_started_test(worker),
            "failure_result_lines" => worker[:failure_result_lines],
            "known_red" => !!(worker[:summary] && (worker[:summary]["failures"].positive? || worker[:summary]["errors"].positive?)) || !worker[:failure_result_lines].empty? || (worker[:status] && !worker[:status].success?)
          }
        end
      }
      path = File.join(LOG_DIR, "suite-report.json")
      File.write(path, JSON.pretty_generate(payload) + "\n")
      out.puts "test-suite-report0: #{path} completed_results=#{completed_results} status=#{payload["status"]}"

      incomplete = payload["workers"].reject { |worker| worker["outcome"] == "passed" }
      return if incomplete.empty?

      out.puts "test-suite-incomplete-workers0: #{incomplete.size}"
      incomplete.each do |worker|
        out.puts "test-worker-last0: #{worker["last_started_test"] || "unknown"}" if worker["last_started_test"]
        out.puts "  worker=#{worker["index"]} outcome=#{worker["outcome"]} timed_out=#{worker["timed_out"]} " \
                 "summary=#{worker["summary_present"]} exit=#{worker["exit_status"].inspect}"
      end
    rescue StandardError => error
      out.puts "test-suite-report0: failed #{error.class}: #{error.message}"
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
        if worker[:timed_out] || worker[:failure_result_lines]&.any? || worker[:summary].to_h.values_at("failures", "errors").compact.any?(&:positive?)
          out.puts "test-worker-last0: #{last_started_test(worker) || "unknown"}"
        end
      end
    end
  end
end
