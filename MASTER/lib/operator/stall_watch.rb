# frozen_string_literal: true

module Operator

  # Reads /fix's own heartbeat for the stall it already reports. The pulse
  # prints "STALLED pass 1 phase scan + stream fixes for 45m, 0 files attempted"
  # every few seconds and, for a phase that is not skippable, goes on waiting.
  # One run spent 46 minutes that way before anyone read the log. The wrapper
  # that launched the run reads the same line and ends the run past a limit.
  module StallWatch
    LINE = /STALLED .* for (\d+)m, 0 files attempted/
    DEFAULT_ABORT_SECONDS = 600

    module_function

    def stalled_seconds(text)
      minutes = text.scan(LINE).flatten.map(&:to_i).max
      minutes && minutes * 60
    end

    def limit(env = ENV)
      Integer(env.fetch("MASTER_FIX_ABORT_S", DEFAULT_ABORT_SECONDS.to_s), exception: false) || DEFAULT_ABORT_SECONDS
    end

    def abort?(text, env: ENV)
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
