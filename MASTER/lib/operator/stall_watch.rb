# frozen_string_literal: true

module Operator

  # Reads /fix's own heartbeat for the stall it already reports. The pulse
  # prints "STALLED pass 1 phase scan + stream fixes for 10m, 0 files attempted".
  # RunBudget now aborts sustained non-advisory stalls inside the process; this
  # wrapper remains a second line of defense for direct child processes and for
  # logs emitted by older runtimes that only report the stall.
  module StallWatch
    LINE = /STALLED .* for (\d+)m, 0 files attempted/
    NO_YIELD = /STALLED no yield: 0 fixed after \d+m, \d+ attempts/
    DEFAULT_ABORT_SECONDS = 600

    module_function

    def stalled_seconds(text)
      minutes = text.scan(LINE).flatten.map(&:to_i).max
      minutes && minutes * 60
    end

    def limit(env = ENV)
      Integer(env.fetch("MASTER_FIX_ABORT_S", DEFAULT_ABORT_SECONDS.to_s), exception: false) || DEFAULT_ABORT_SECONDS
    end

    # The run itself decides a no-yield stall (RunPulse); the wrapper only ends it.
    def abort?(text, env: ENV)
      return true if NO_YIELD.match?(text)

      seconds = stalled_seconds(text)
      !seconds.nil? && seconds >= limit(env)
    end

    # The last stretch of a log is where the current state is; reading all of a
    # multi-hour log every poll would cost more than the run's own heartbeat.
    def tail(path, bytes: 8192)
      return "" unless File.file?(path)

      File.open(path, "rb") do |file|
        file.seek([file.size - bytes, 0].max)
        file.read.to_s.force_encoding(Encoding::UTF_8).scrub
      end
    end
  end
end
