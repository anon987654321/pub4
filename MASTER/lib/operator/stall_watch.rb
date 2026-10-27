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

  # What a /fix run does before its first repair, and how long that took last time. A RAILS run
  # spent fifty-six minutes on baseline proof, browser sweeps and the layout sweep before pass 1,
  # and nothing said so: the operator saw "no repairs yet" and could not tell waiting from stuck.
  # Read from the tree's previous log before the next run overwrites it.
  module RunPlan
    PULSE = %r{fix0: pass (\d+)/\d+ (\S+) .*elapsed = (\d+)s}

    module_function

    # Each pulse as [pass, stage, minute].
    def pulses(log)
      File.foreach(log, encoding: "UTF-8", invalid: :replace, undef: :replace).filter_map do |line|
        pass, stage, elapsed = line.match(PULSE)&.captures
        [pass.to_i, stage, elapsed.to_i / 60] if pass
      end
    end

    # [[stage, start_minute], ...] for pass 0, and the minute pass 1 began (nil if it never did).
    def read(log)
      return [[], nil] unless File.file?(log)

      seen = pulses(log)
      stages = seen.select { |pass, _stage, _minute| pass.zero? }.uniq { |_pass, stage, _minute| stage }
      repairs = seen.find { |pass, _stage, _minute| pass.positive? }
      [stages.map { |_pass, stage, minute| [stage, minute] }, repairs&.last]
    end

    def line(tree, log)
      stages, repairs_at = read(log)
      return "plan0 at fix-here: no earlier #{tree} run to time; repairs follow the proof and scan" if stages.empty?

      timeline = stages.map { |stage, minute| "#{stage.delete_suffix("0")} #{minute}m" }.join(", ")
      start = repairs_at ? "repairs began at #{repairs_at}m" : "it never reached repairs"
      "plan0 at fix-here: last #{tree} run: #{timeline}; #{start}. An unchanged tree's browser sweeps now replay."
    end
  end
end
