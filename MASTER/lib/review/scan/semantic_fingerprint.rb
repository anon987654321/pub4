# frozen_string_literal: true

require "digest"

module Master
  module Review
    module Scan
      # Structural fingerprint of a Ruby file's source, used to detect
      # whether a file changed between when a violation was found and when
      # a fix is about to be applied to it (RuleLoop::FixVerification's
      # stale-scan guard).
      #
      # One implementation, because two drift. FileProcessor computes this when
      # a finding is recorded and RuleLoop::FixVerification recomputed it
      # just before applying a fix; the two definitions disagreed, one carrying an
      # `ast_present` key the other
      # didn't. Marshal.dump serializes every key, so a 6-field hash and a
      # 5-field hash never produce the same digest no matter how identical
      # the underlying code is. Every fingerprint comparison failed,
      # permanently, for every file, since this code was written -- found
      # live via the skip_breakdown aggregate trace (rule_loop.rb) showing
      # 100% of skipped violations attributed to fingerprint, 0% to
      # confidence, across every single rule in a full-repo /fix pass.
      module SemanticFingerprint
        module_function

        def for(code)
          counts = {
            line_count: code.lines.count,
            class_count: code.scan(/^\s*class\s+/).size,
            method_count: code.scan(/^\s*def\s+/).size,
            def_names: code.scan(/^\s*def\s+([a-zA-Z_][\w!?=]*)/).flatten.sort,
            constant_names: code.scan(/\b([A-Z][A-Z0-9_]*(?:::[A-Z][A-Z0-9_]*)*)\b/).flatten.sort,
          }
          Digest::SHA256.hexdigest(Marshal.dump(counts))
        rescue StandardError
          Digest::SHA256.hexdigest(code.to_s)
        end
      end
    end
  end
end
