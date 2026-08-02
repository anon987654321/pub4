# frozen_string_literal: true

require "open3"
require "tempfile"

module Master
  module Fix
  # Architecture #5: apply a unified diff patch to source text.
  # Calls system `patch`(1) — available on OpenBSD base and most Linux distros.
  # Rejects malformed or no-op patches; never applies blindly.
    class PatchApplier
      # Files smaller than this are cheaper to rewrite in full — skip diff mode.
      DIFF_THRESHOLD = 8_192

      Success = Struct.new(:source, keyword_init: true)
      Failure = Struct.new(:reason, keyword_init: true)

      def self.apply(original, diff_text)
        return Failure.new(reason: "empty diff") if diff_text.strip.empty?
        new(original, diff_text).apply
      end

      def initialize(original, diff_text)
        @original = original
        @diff = diff_text
      end

      def apply
        Tempfile.open(["master_patch", ".src"]) do |f|
          f.write(@original)
          f.flush
          out, err, status = Master::Io::Exec.capture3("patch", "--no-backup-if-mismatch", "-s", f.path, stdin_data: @diff)
          # patch(1) reports a failed hunk on stdout, so err alone gave reason: "".
          return Failure.new(reason: failure_reason(out, err)) unless status.success?

          result = File.read(f.path)
          return Failure.new(reason: "no change") if result.strip == @original.strip
          Success.new(source: result)
        end
      rescue StandardError => e
        Failure.new(reason: e.message[0, 200])
      end

      private

      def failure_reason(out, err)
        text = err.to_s.strip
        text = out.to_s.strip if text.empty?
        text.empty? ? "patch(1) rejected the diff" : text[0, 200]
      end
    end
  end
end
