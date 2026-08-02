# frozen_string_literal: true

# OpenBSD-style kernel dmesg logging for the Dilla engine.
#
# Format (device-attach + fact lines), inspired by OpenBSD dmesg collections
# and MASTER house style (postpro / chat dmesg / OPENBSD/RUNBOOK.md):
#
#   dilla0 at mainbus0: ruby3.4.5 pid=12345 mode=dilla
#   stream0 at dilla0: continuous bars=32 mode=fast
#   track0 at stream0: quartal_west_coast pad=blend/wash lead=0
#   exec0 at dilla0: run ffmpeg exit=0 +1.24s
#   audio0 at dilla0: write demo.wav 15735666B
#   warn0 at dilla0: speech tts segment failed
#
# Control:
#   DILLA_DMESG=0   silence
#   DILLA_DMESG=1   normal (default)
#   DILLA_DMESG=2   verbose (full argv, tool stderr tails)
#   DILLA_VERBOSE=1 same as DILLA_DMESG=2
#   DILLA_DEBUG=1   same as DILLA_DMESG=2
module DillaDmesg
  BOOT_T0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  INTERACTIVE_BINS = %w[afplay ffplay].freeze

  module_function

  def enabled?
    ENV.fetch("DILLA_DMESG", "1") != "0"
  end

  def verbose?
    ENV["DILLA_DMESG"] == "2" || ENV["DILLA_VERBOSE"] == "1" || ENV["DILLA_DEBUG"] == "1"
  end

  def elapsed
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - BOOT_T0
  end

  def elapsed_tag
    "+%.3fs" % elapsed
  end

  # Core emit: "unit at parent: message" or "unit: message"
  def emit(unit, msg, parent: nil, stream: $stderr)
    return unless enabled?
    text = msg.to_s.strip.downcase
    text = text.gsub(/\s+/, " ")
    line = if parent
             "#{unit} at #{parent}: #{text}"
           else
             "#{unit}: #{text}"
           end
    stream.puts line
    stream.flush
    line
  end

  def ok(msg, unit: "dilla0", parent: nil)
    emit(unit, msg, parent:)
  end

  def warn(msg, unit: "warn0", parent: "dilla0")
    emit(unit, "warn #{msg}", parent:)
  end

  def error(msg, unit: "error0", parent: "dilla0")
    emit(unit, "error #{msg}", parent:)
  end

  def attach(unit, parent, msg = nil)
    body = msg.to_s.strip.empty? ? "attached" : msg
    emit(unit, body, parent:)
  end

  def boot!(mode: nil, cmd: nil)
    host = RbConfig::CONFIG["host_os"].to_s.split.first
    bits = [
      "ruby#{RUBY_VERSION}",
      "os=#{host}",
      "pid=#{Process.pid}",
      ("mode=#{mode}" if mode),
      ("cmd=#{cmd}" if cmd),
      elapsed_tag,
    ].compact
    emit("dilla0", bits.join(" "), parent: "mainbus0")
  end

  def stream!(mode:, bars:, order_n: nil)
    bits = ["continuous", "bars=#{bars}", "mode=#{mode}", ("tracks=#{order_n}" if order_n), elapsed_tag]
    emit("stream0", bits.compact.join(" "), parent: "dilla0")
  end

  def track!(name, meta)
    emit("track0", "#{name} #{meta}", parent: "stream0")
  end

  def write!(path, bytes: nil)
    base = File.basename(path.to_s)
    size = bytes || (File.file?(path) ? File.size(path) : nil)
    bits = ["write", base, (size ? "#{size}B" : nil), elapsed_tag].compact
    emit("audio0", bits.join(" "), parent: "dilla0")
  end

  def read!(path, bytes: nil)
    base = File.basename(path.to_s)
    size = bytes || (File.file?(path) ? File.size(path) : nil)
    bits = ["read", base, (size ? "#{size}B" : nil)].compact
    emit("audio0", bits.join(" "), parent: "dilla0")
  end

  def run!(cmd_display, exitstatus:, seconds: nil, unit: "exec0")
    bin = cmd_display.to_s.split.first.to_s
    short = verbose? ? truncate(cmd_display, 200) : bin
    bits = ["run", short, "exit=#{exitstatus}", (seconds ? "+%.2fs" % seconds : nil), elapsed_tag].compact
    emit(unit, bits.join(" "), parent: "dilla0")
  end

  def play!(tool, path)
    emit("play0", "#{tool} #{File.basename(path.to_s)}", parent: "dilla0")
  end

  def style!(keys)
    emit("style0", keys.to_s, parent: "dilla0")
  end

  def metrics!(hash)
    return unless hash.is_a?(Hash)
    parts = hash.map { |k, v| "#{k}=#{v.is_a?(Float) ? format('%.1f', v) : v}" }
    emit("meter0", parts.join(" "), parent: "dilla0")
  end

  def truncate(s, n)
    s = s.to_s
    s.bytesize <= n ? s : "#{s.byteslice(0, n)}…"
  end

  def interactive_bin?(command)
    bin = Array(command).flatten.first.to_s
    INTERACTIVE_BINS.include?(File.basename(bin))
  end
end
