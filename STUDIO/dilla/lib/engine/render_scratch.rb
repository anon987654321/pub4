# frozen_string_literal: true
#
# Render scratch directory and the stream lock.
#
# Part of the dilla engine, split out of dilla.rb. Defines methods and
# constants at top level exactly as it did there; dilla.rb requires the
# parts in the file's original order, because several constants are
# computed at load time from ones declared above them.

def dilla_render_tmp(tag)
  File.join(SCRATCH_DIR, "dilla_#{tag}.#{Process.pid}.wav")
end

# PID-scoped temp files (drums/harmonic/wonky_*/pads.wav.L0/.smf.mid/etc.)
# are reused across every track iteration within one long-running stream
# process, not just within a single render. If a write is ever interrupted
# (disk full, a signal mid-write) a stale/corrupt derived file can silently
# survive and poison a later, otherwise-unrelated track's render — a
# multi-minute stream then starts failing its final ffmpeg mixdown on every
# track. Wiping this process's own scratch files at the top of every render
# makes each track start from a guaranteed-clean slate instead of trusting
# leftovers from whatever the last track did.
def cleanup_render_scratch!
  Dir.glob(File.join(SCRATCH_DIR, "dilla_*.#{Process.pid}.*")).each { |f| FileUtils.rm_f(f) } # scan: intentional — this process's own scratch files, pid-scoped
end

STREAM_LOCK_PATH = scratch_path("dilla_stream.lock").freeze

def acquire_stream_lock!
  if File.exist?(STREAM_LOCK_PATH)
    holder = File.read(STREAM_LOCK_PATH).strip.to_i
    if holder.positive?
      begin
        Process.kill(0, holder)
        dmesg_warn("stream lock held by pid #{holder} — exit")
        exit 0
      rescue Errno::ESRCH
        FileUtils.rm_f(STREAM_LOCK_PATH)
      end
    end
  end
  File.write(STREAM_LOCK_PATH, Process.pid.to_s)
  at_exit do
    FileUtils.rm_f(STREAM_LOCK_PATH) if File.exist?(STREAM_LOCK_PATH) &&
                                        File.read(STREAM_LOCK_PATH).strip.to_i == Process.pid
  rescue StandardError
    nil
  end
end
