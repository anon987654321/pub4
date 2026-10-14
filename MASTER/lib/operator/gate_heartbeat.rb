# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../trace/dmesg"

module Operator
  # A gate stage runs minutes with its output captured, so the terminal is
  # silent for as long. The runner writes the gate it is on to a small file
  # (GATE_PROGRESS_FILE); this reads it on the RunBudget cadence and says one
  # dmesg line: the gate, n of N, how long it has run, how long the stage has.
  class GateHeartbeat
    CADENCE = 28
    ENV_KEY = "GATE_PROGRESS_FILE"

    # Runs the block with the progress path in its environment hash and a
    # thread speaking while it runs. The block receives the env additions.
    def self.around(label, unit: "gate0", cadence: CADENCE, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
                    wall: -> { Time.now.to_f }, say: nil, poll: 1)
      Dir.mktmpdir("gate_progress") do |dir|
        path = File.join(dir, "progress.json")
        beat = new(label:, path:, unit:, cadence:, clock:, wall:, say:)
        thread = Thread.new { beat.run(poll) } if poll.positive?
        begin
          yield({ ENV_KEY => path })
        ensure
          thread&.kill
        end
      end
    end

    def initialize(label:, path:, unit: "gate0", cadence: CADENCE, clock:, wall:, say: nil)
      @label = label
      @path = path
      @unit = unit
      @cadence = cadence
      @clock = clock
      @wall = wall
      @say = say || ->(text) { Master::Trace::Dmesg.status(unit, text) }
      @started = clock.call
      @last = @started
    end

    def run(poll)
      loop do
        sleep poll
        beat
      end
    end

    # One line per cadence, whatever else was said. Returns the line, or nil.
    def beat
      now = @clock.call
      row = progress
      cadence = row&.fetch("kind", nil) == "scan" ? [@cadence, 5].min : @cadence
      return if now - @last < cadence

      @last = now
      line = describe(now, row)
      @say.call(line)
      line
    end

    private

    def describe(now, row = progress)
      elapsed = now - @started
      return "#{@label} running, elapsed #{human(elapsed)}" unless row

      ran = [@wall.call - row["at"].to_f, 0].max
      return describe_scan(row, ran:, elapsed:) if row["kind"] == "scan"

      "#{@label} gate #{row["n"]}/#{row["total"]} #{row["name"]} running #{human(ran)}, elapsed #{human(elapsed)}"
    end

    def describe_scan(row, ran:, elapsed:)
      updated = [@wall.call - row.fetch("updated_at", row["at"]).to_f, 0].max
      detail = "pass=#{row["pass"]} law=#{row["law"]} file=#{row["file"]} " \
               "checks=#{row["checks"]} active=#{row["active"]} laws=#{row["n"]}/#{row["total"]}"

      if row["state"] == "running"
        state = updated > 6 ? "scan progress stale" : "scan"
        return "#{@label} #{state} #{detail}, check elapsed #{human(ran)}, last update #{human(updated)} ago, stage elapsed #{human(elapsed)}"
      end

      "#{@label} scanner idle; last #{detail}, no active law check, last update #{human(updated)} ago, stage elapsed #{human(elapsed)}"
    end

    def progress
      JSON.parse(File.read(@path))
    rescue SystemCallError, JSON::ParserError
      nil
    end

    def human(seconds)
      minutes, secs = seconds.to_i.divmod(60)
      minutes.positive? ? "#{minutes}m#{format("%02d", secs)}s" : "#{secs}s"
    end
  end
end
