# frozen_string_literal: true

module Master
  module Fix
    # Raised when a scan skipped so many files that "zero violations" no longer
    # describes the tree. A LockSweep that was never required once made 2,400
    # files "scan skipped" and the run reported itself clean.
    class MassSkipError < StandardError
      attr_reader :signature, :count, :total

      def initialize(signature:, count:, total:, reason:)
        @signature = signature
        @count = count
        @total = total
        super("#{reason}: #{count} of #{total} file(s) skipped, #{signature}")
      end
    end

    # Tallies the files a scan could not measure, by failure signature, and
    # refuses to let a systemic failure pass as a clean scan. A refusal of one
    # file (too long, binary, a symlink) is a fact about that file and is not
    # counted; only measurement failures are.
    class ScanSkipGuard
      RATE = 0.02
      MIN_SKIPS = 3
      SAME_CLASS_LIMIT = 20
      CLASS_PATTERN = /\b((?:[A-Z]\w*::)*[A-Z]\w*(?:Error|Exception))\b/

      def initialize
        @skipped = {}
      end

      def reset!
        @skipped.clear
        self
      end

      def size = @skipped.size

      def record(file, result)
        return if result.category == :validation

        @skipped[file] = self.class.signature(result.message)
      end

      def check!(total:)
        by_signature = @skipped.values.tally
        signature, count = by_signature.max_by { |_sig, n| n }
        if count.to_i > SAME_CLASS_LIMIT
          raise error(signature, count, total, "one failure repeats across more than #{SAME_CLASS_LIMIT} files")
        end
        return unless total.to_i.positive? && @skipped.size >= MIN_SKIPS && @skipped.size > total * RATE

        raise error(signature, @skipped.size, total, "more than #{(RATE * 100).round}% of files skipped")
      end

      # The exception class when the message names one; otherwise the message
      # with its path and line stripped, so one failure on many files groups.
      def self.signature(message)
        text = message.to_s
        named = text[CLASS_PATTERN, 1]
        return named if named
        return "NameError" if text.include?("uninitialized constant")

        text.sub(/\A(?:fix )?scan failed(?: for \S+)?: /, "").sub(/ at \S+\z/, "").gsub(%r{/\S+}, "<path>")[0, 60]
      end

      private

      def error(signature, count, total, reason)
        Master::Trace::Dmesg.status("fix0", "scan aborted, #{count} of #{total} file(s) skipped by #{signature}"[0, 200])
        MassSkipError.new(signature:, count:, total:, reason:)
      end
    end
  end
end
