# frozen_string_literal: true

module Deploy
  # Shared body for source checks that assert a table of required files each
  # contain a pattern: fail if the file is missing, fail if it exists but the
  # pattern does not match. affiliate_honesty and payment_honesty carried this
  # loop identically; their FORBIDDEN tables, Tradedoubler assertions and the
  # live cart probe are check-specific and stay in each check file.
  module SourceContract
    module_function

    def require_patterns(result, root:, required:, check:)
      required.each do |rel, pat|
        path = File.join(root, rel)
        unless File.file?(path)
          result.fail("#{check}: missing #{rel}")
          next
        end

        body = File.read(path)
        result.fail("#{check}: #{rel} missing #{pat.inspect}") unless body.match?(pat)
      end
    end
  end
end
