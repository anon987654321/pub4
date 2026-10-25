# frozen_string_literal: true

module Deploy
  # Treat a deploy-status PID as untrusted input. Process.kill(0, 0) probes the
  # current process group on Unix, so coercing malformed metadata with to_i can
  # make a corrupt PID look live forever.
  module PidProbe
    module_function

    def alive?(pid)
      candidate = pid.to_s
      return false unless candidate.match?(/\A[1-9]\d*\z/)

      Process.kill(0, Integer(candidate, 10))
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true # exists, just owned by another user (e.g. root vs. dev)
    rescue ArgumentError, TypeError, RangeError, SystemCallError
      false
    end
  end
end
