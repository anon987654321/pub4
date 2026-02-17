# frozen_string_literal: true

require "json"
require "fileutils"

module MASTER
  # Scheduler -- persistent job scheduling (cron-style)
  # Stolen from OpenClaw: agents schedule their own future work,
  # jobs persist across restarts, exponential backoff on failure
  module Scheduler
    extend self

    JOBS_FILE = File.join(MASTER.root, "data", "scheduled_jobs.json")
    MAX_JOBS = 50

    Job = Struct.new(
      :id, :command, :interval, :next_at, :last_run, :failures, :enabled,
      :priority, :max_retries, :retry_backoff, :confidence, :last_status, :last_error,
      keyword_init: true
    )

    @jobs = []
    @mutex = Mutex.new

    class << self
      def load
        return unless File.exist?(JOBS_FILE)

        raw = JSON.parse(File.read(JOBS_FILE), symbolize_names: true)
        @jobs = (raw || []).map do |j|
          Job.new(
            id: j[:id],
            command: j[:command],
            interval: j[:interval],
            next_at: Time.at(j[:next_at] || 0),
            last_run: j[:last_run] ? Time.at(j[:last_run]) : nil,
            failures: j[:failures] || 0,
            enabled: j.fetch(:enabled, true),
            priority: j[:priority] || 50,
            max_retries: j[:max_retries] || 5,
            retry_backoff: j[:retry_backoff] || "exponential",
            confidence: j[:confidence] || 1.0,
            last_status: j[:last_status],
            last_error: j[:last_error]
          )
        end
        Logging.dmesg_log("scheduler", message: "loaded #{@jobs.size} jobs")
      rescue StandardError => e
        Logging.dmesg_log("scheduler", message: "load error: #{e.message}")
        @jobs = []
      end

      def save
        @mutex.synchronize do
          data = @jobs.map do |j|
            { id: j.id, command: j.command, interval: j.interval,
              next_at: j.next_at.to_i, last_run: j.last_run&.to_i,
              failures: j.failures, enabled: j.enabled,
              priority: j.priority, max_retries: j.max_retries,
              retry_backoff: j.retry_backoff, confidence: j.confidence,
              last_status: j.last_status, last_error: j.last_error }
          end
          FileUtils.mkdir_p(File.dirname(JOBS_FILE))
          File.write(JOBS_FILE, JSON.pretty_generate(data))
        end
      end

      # Add a scheduled job
      # interval: seconds between runs, or :once for one-shot
      def add(command, interval:, id: nil, priority: 50, max_retries: 5, retry_backoff: "exponential", confidence: 1.0)
        return Result.err("Too many jobs (max #{MAX_JOBS}).") if @jobs.size >= MAX_JOBS

        job = Job.new(
          id: id || "job_#{Time.now.to_i}_#{rand(1000)}",
          command: command,
          interval: interval == :once ? nil : interval,
          next_at: Time.now,
          last_run: nil,
          failures: 0,
          enabled: true,
          priority: priority,
          max_retries: max_retries,
          retry_backoff: retry_backoff,
          confidence: confidence,
          last_status: nil,
          last_error: nil
        )

        @mutex.synchronize { @jobs << job }
        save
        Logging.dmesg_log("scheduler", message: "added #{job.id}: #{command}")
        Result.ok(job_id: job.id)
      end

      def remove(job_id)
        @mutex.synchronize { @jobs.reject! { |j| j.id == job_id } }
        save
        Result.ok(removed: job_id)
      end

      def list
        @jobs.map do |j|
          { id: j.id, command: j.command, interval: j.interval,
            next_at: j.next_at, enabled: j.enabled, failures: j.failures,
            priority: j.priority, max_retries: j.max_retries, confidence: j.confidence,
            last_status: j.last_status, last_error: j.last_error }
        end
      end

      # Check and run due jobs -- called by Heartbeat
      def tick
        now = Time.now
        due = @jobs.select { |j| j.enabled && j.next_at <= now }
        due = rank_due_jobs(due)
        return if due.empty?

        due.each do |job|
          ok = run_job(job)
          if ok
            if job.interval
              job.next_at = Time.now + job.interval
            else
              job.enabled = false # one-shot
            end
          elsif job.failures >= job.max_retries.to_i
            job.enabled = false
            Logging.dmesg_log("scheduler", message: "disabled #{job.id}: max retries reached")
          end
          job.last_run = Time.now
        end
        save
      end

      def enable(job_id)
        job = @jobs.find { |j| j.id == job_id }
        return Result.err("Job not found: #{job_id}.") unless job

        job.enabled = true
        job.next_at = Time.now
        save
        Result.ok(enabled: job_id)
      end

      def disable(job_id)
        job = @jobs.find { |j| j.id == job_id }
        return Result.err("Job not found: #{job_id}.") unless job

        job.enabled = false
        save
        Result.ok(disabled: job_id)
      end

      private

      def run_job(job)
        Logging.dmesg_log("scheduler", message: "ENTER run #{job.id}: #{job.command}")
        result = execute_like_user(job.command)
        raise "scheduler command failed" if result.respond_to?(:err?) && result.err?

        job.failures = 0
        job.last_status = "ok"
        job.last_error = nil
        Logging.dmesg_log("scheduler", message: "EXIT run #{job.id} ok")
        true
      rescue StandardError => e
        job.failures += 1
        job.last_status = "failed"
        job.last_error = e.message
        backoff = backoff_seconds(job)
        Logging.dmesg_log("scheduler", message: "run #{job.id} failed (#{job.failures}x): #{e.message}; backoff=#{backoff}s")
        job.next_at = Time.now + backoff
        false
      end

      # Ensure scheduler gets exact same treatment as user/self-test input:
      # command dispatch first, then pipeline fallback.
      def execute_like_user(input)
        pipeline = Pipeline.new
        cmd_result = Commands.dispatch(input, pipeline: pipeline)
        return Result.ok(handled: true) if cmd_result == :exit
        return cmd_result if cmd_result.respond_to?(:ok?)
        return pipeline.call({ text: input }) if cmd_result.nil?

        Result.ok(handled: true)
      end

      def backoff_seconds(job)
        case job.retry_backoff.to_s
        when "linear"
          [60 * (job.failures + 1), 3600].min
        when "none"
          60
        else
          [60 * (2**job.failures), 3600].min
        end
      end

      def rank_due_jobs(jobs)
        return jobs unless defined?(DecisionEngine)

        scored = jobs.map do |j|
          fail_penalty = [j.failures.to_i, 5].min
          next_in = [j.next_at.to_i - Time.now.to_i, 0].max
          impact = (j.priority || 50).to_f / 100.0
          confidence = [[j.confidence.to_f - (fail_penalty * 0.08), 0.1].max, 1.0].min
          cost = 1.0 + (next_in / 60.0)
          {
            job: j,
            impact: impact,
            confidence: confidence,
            cost: cost
          }
        end

        DecisionEngine.rank(scored.map { |s| s.merge(score: DecisionEngine.score(impact: s[:impact], confidence: s[:confidence], cost: s[:cost])) })
          .map { |row| row[:job] }
      end
    end
  end
end
