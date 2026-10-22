# frozen_string_literal: true

require "fileutils"
require_relative "../../trace/dmesg"

module Operator
  class CheckRunner
    # Reads a running step's log as it grows: each failing test as minitest names it, the tests run
    # so far each minute, and a stall when the log has not grown for two minutes.
    class StepWatch
      LOG_DIR = File.expand_path("../../../.master/check", __dir__)

      # Seconds between reads of the log, between progress lines, and of silence before a stall.
      Pace = Data.define(:every, :report, :stall)
      PACE = Pace.new(every: 5, report: 60, stall: 120)

      FAILURE_HEAD = /\A\s*\d+\) (?:Failure|Error):\s*\z/
      TEST_NAME = /\A\s*(\S+#\S+?)(?: \[[^\]]*\])?:?\s*\z/
      DOTS = /\A[.FES]+/

      def self.log_path(name)
        FileUtils.mkdir_p(LOG_DIR)
        File.join(LOG_DIR, "#{name.gsub(/[^\w.-]+/, "_")[0, 80]}.log")
      end

      def initialize(path, unit:, pace: PACE)
        @path = path
        @unit = unit
        @pace = pace
        @tally = Hash.new(0)
        @thread = Thread.new { watch }
      end

      def stop = @thread.kill

      private

      def watch
        offset = 0
        clock = { grew: now, reported: now, stalled: false }

        loop do
          sleep @pace.every
          fresh = read_from(offset)
          offset += fresh.bytesize
          fresh.empty? ? quiet(clock) : grew(fresh, clock)
          report(clock)
        end
      end

      def read_from(offset)
        File.open(@path, "rb") { |file| file.seek(offset) && file.read.to_s }
      rescue SystemCallError
        ""
      end

      def grew(fresh, clock)
        clock.merge!(grew: now, stalled: false)
        lines = fresh.force_encoding(Encoding::UTF_8).scrub.lines(chomp: true)
        lines.each_cons(2) { |head, name| name_failure(head, name) }
        lines.each { |line| line[DOTS].to_s.each_char { |mark| @tally[mark] += 1 } }
      end

      def name_failure(head, name)
        return unless head.match?(FAILURE_HEAD)

        name.match(TEST_NAME) { |found| status("failed #{found[1]}") }
      end

      def quiet(clock)
        silent = now - clock[:grew]
        return if silent < @pace.stall || clock[:stalled]

        status("no output for #{silent.round}s, the step may be stuck; log #{@path}")
        clock[:stalled] = true
      end

      def report(clock)
        return if now - clock[:reported] < @pace.report || @tally.empty?

        run = @tally.values.sum
        status("#{run} tests run, #{@tally["F"]} failed, #{@tally["E"]} errored so far")
        clock[:reported] = now
      end

      def status(text) = Master::Trace::Dmesg.status(@unit, text)

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
