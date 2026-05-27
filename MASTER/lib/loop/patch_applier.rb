# frozen_string_literal: true

require "open3"
require "tempfile"

module Master
  module Loop
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
      return Failure.new(reason: "not a diff") unless diff_text.include?("@@")
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
        _out, err, status = Open3.capture3("patch", "--no-backup-if-mismatch", "-s", f.path, stdin_data: @diff)
        return Failure.new(reason: err.strip[0, 200]) unless status.success?
        result = File.read(f.path, encoding: "UTF-8")
        return Failure.new(reason: "no change") if result.strip == @original.strip
        Success.new(source: result)
      end
    rescue StandardError => e
      Failure.new(reason: e.message[0, 200])
    end
  end
  end
end
