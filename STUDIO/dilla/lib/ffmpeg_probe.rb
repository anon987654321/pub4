# frozen_string_literal: true

require "open3"

# One way to ask ffmpeg for a measurement, for the scoring modules.
#
# They each interpolated the path into backticks, discarded the exit status and
# read the number with `.to_f`. A crate path holding a quote became a command, a
# hung decode blocked the caller forever, and a failed run printed no match, so
# `nil.to_f` reported 0.0 dB: silence, or a loudness 19 dB under target, from a
# file ffmpeg never opened. A measurement that cannot fail cannot be trusted.
module FfmpegProbe
  class Error < StandardError; end

  TIMEOUT = Integer(ENV.fetch("DILLA_PROBE_TIMEOUT", "300"))

  module_function

  # ffmpeg's log for `-af filter` run over path into the null muxer. Argument
  # vector, not a shell string; raises on a non-zero exit or the timeout.
  def run(path, filter, timeout: TIMEOUT)
    argv = ["ffmpeg", "-nostdin", "-v", "info", "-i", path.to_s, "-af", filter, "-f", "null", "-"]
    Open3.popen2e(*argv) do |stdin, out, wait|
      stdin.close
      reader = Thread.new { out.read }
      unless wait.join(timeout)
        Process.kill("KILL", wait.pid)
        wait.join
        raise Error, "ffmpeg timed out after #{timeout}s on #{path}"
      end
      log = reader.value.to_s
      raise Error, "ffmpeg exited #{wait.value.exitstatus} on #{path}: #{log.lines.last(2).join.strip}" unless wait.value.success?

      log
    end
  rescue Errno::ENOENT
    raise Error, "ffmpeg is not installed or not on PATH"
  end

  # The float the pattern's first group captures, or Error when it is absent.
  def number(log, pattern, what:)
    raw = log[pattern, 1]
    raise Error, "no #{what} in ffmpeg output" if raw.nil?

    raw.to_f
  end
end
