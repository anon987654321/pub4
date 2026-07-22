# frozen_string_literal: true

require "fileutils"

module Master
  module CLI
    # Live operator surface for /scan: flushed lines, multiphase brief, durable snapshot.
    # Survives pipe buffering and partial kills — last useful report lands on disk.
    module ScanLive
      module_function

      SNAPSHOT_REL = File.join(".master", "scan_last.txt").freeze
      TMP_SNAPSHOT = "/tmp/master_scan_last.txt".freeze

      def ensure_sync!
        $stdout.sync = true
        $stderr.sync = true if $stderr.respond_to?(:sync=)
      end

      def emit(msg, unit: "scan")
        ensure_sync!
        text = msg.to_s.gsub(/\s+/, " ").strip
        Master::Trace::Dmesg.status(unit, text)
        text
      end

      def banner(target:, profile:, dry_run:, autofix:)
        emit(
          "begin target=#{target.inspect} profile=#{profile || "full"} " \
          "dry_run=#{dry_run ? "yes" : "no"} autofix=#{autofix ? "yes" : "no"}",
        )
      end

      def snapshot!(text, root:, note: nil, announce: true)
        ensure_sync!
        body = +"# master scan snapshot #{Time.now.utc.iso8601}\n"
        body << "# #{note}\n" if note
        body << text.to_s
        body << "\n" unless body.end_with?("\n")

        path = File.join(root.to_s, SNAPSHOT_REL)
        FileUtils.mkdir_p(File.dirname(path))
        atomic_write(path, body)
        atomic_write(TMP_SNAPSHOT, body)
        emit("snapshot path=#{path} also=#{TMP_SNAPSHOT}") if announce
        path
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "ScanLive.snapshot!")
        nil
      end

      def atomic_write(path, body)
        tmp = "#{path}.#{Process.pid}.tmp"
        File.write(tmp, body)
        File.rename(tmp, path)
      end

      def with_interrupt_dump(root:)
        ensure_sync!
        holder = { text: nil, root: }
        prev_int = trap_soft("INT", holder)
        prev_term = trap_soft("TERM", holder)
        yield holder
      ensure
        restore_trap("INT", prev_int) if prev_int
        restore_trap("TERM", prev_term) if prev_term
      end

      def trap_soft(sig, holder)
        previous = Signal.trap(sig) do
          dump = holder[:text].to_s
          if dump.empty?
            emit("interrupted — no partial report yet", unit: "scan")
          else
            emit("interrupted — writing partial snapshot", unit: "scan")
            snapshot!(dump, root: holder[:root], note: "partial after #{sig}")
            $stdout.puts dump
            $stdout.flush
          end
          exit!(130) if sig == "INT"
          exit!(143)
        end
        previous
      rescue ArgumentError
        # Signal not supported on this platform
        nil
      end

      def restore_trap(sig, previous)
        return unless previous

        Signal.trap(sig, previous)
      rescue ArgumentError, StandardError
        nil
      end
    end
  end
end
