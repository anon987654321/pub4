# frozen_string_literal: true

module Deploy
  # Shared body for source gates that assert a table of required files each
  # contain a pattern: fail if the file is missing, fail if it exists but the
  # pattern does not match. affiliate_honesty and payment_honesty carried this
  # loop identically; their FORBIDDEN tables, Tradedoubler assertions and the
  # live cart probe are gate-specific and stay in each gate file.
  module SourceContract
    module_function

    def require_patterns(result, root:, required:, gate:)
      required.each do |rel, pat|
        path = File.join(root, rel)
        unless File.file?(path)
          result.fail("#{gate}: missing #{rel}")
          next
        end
        body = File.read(path)
        result.fail("#{gate}: #{rel} missing #{pat.inspect}") unless body.match?(pat)
      end
    end
  end
end
