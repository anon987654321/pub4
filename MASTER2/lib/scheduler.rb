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

    Job = Struct.new(:id, :command, :interval, :next_at, :last_run, :failures, :enabled, keyword_init: true)

    @jobs = []
    @mutex = Mutex.new

    class << self
      def load
        return unless File.exist?(JOBS_FILE)

        raw = JSON.parse(File.read(JOBS_FILE), symbolize_names: true)
        @jobs = (raw || []).map { |j| Job.new(**j.merge(next_at: Time.at(j[:next_at] || 0))) }
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
              failures: j.failures, enabled: j.enabled }
          end
          FileUtils.mkdir_p(File.dirname(JOBS_FILE))
          File.write(JOBS_FILE, JSON.pretty_generate(data))
        end
      end

      # Add a scheduled job
      # interval: seconds between runs, or :once for one-shot
      def add(command, interval:, id: nil)
        return Result.err("Too many jobs (max #{MAX_JOBS}).") if @jobs.size >= MAX_JOBS

        job = Job.new(
          id: id || "job_#{Time.now.to_i}_#{rand(1000)}",
          command: command,
          interval: interval == :once ? nil : interval,
          next_at: Time.now,
          last_run: nil,
          failures: 0,
          enabled: true
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
            next_at: j.next_at, enabled: j.enabled, failures: j.failures }
        end
      end

      # Check and run due jobs -- called by Heartbeat
      def tick
        now = Time.now
        due = @jobs.select { |j| j.enabled && j.next_at <= now }
        return if due.empty?

        due.each do |job|
          run_job(job)
          if job.interval
            job.next_at = Time.now + job.interval
          else
            job.enabled = false # one-shot
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
        # Dispatch through the pipeline so it gets full MASTER treatment
        Pipeline.dispatch(job.command)
        job.failures = 0
        Logging.dmesg_log("scheduler", message: "EXIT run #{job.id} ok")
      rescue StandardError => e
        job.failures += 1
        Logging.dmesg_log("scheduler", message: "run #{job.id} failed (#{job.failures}x): #{e.message}")
        # Exponential backoff: push next_at further out
        backoff = [60 * (2**job.failures), 3600].min
        job.next_at = Time.now + backoff
      end
    end
  end
end
