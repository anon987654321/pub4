# frozen_string_literal: true

module Pub4
  # The ratchet contract every *_lint in this directory implements.
  #
  # A lint scans, groups its findings by kind, and compares each count against a
  # BASELINES entry that is allowed to fall and never to rise. Those two steps —
  # counts and over_baseline — were written out in full eight and four times
  # respectively, byte-identical apart from a space inside one bracket pair. The
  # duplication was invisible in review precisely because each copy was correct.
  #
  # Extended, not included: these lints are module_function modules whose methods
  # are called on the module itself (Pub4::BreakpointLint.counts), so the shared
  # pair has to arrive as singleton methods. BASELINES and scan resolve on the
  # extending module, which is what lets one definition serve baselines that have
  # nothing in common.
  #
  # A lint whose counts genuinely differs keeps its own: layout_stability groups
  # every kind it finds rather than only the declared ones, and scale_lint counts
  # per surface. Neither is this contract, and forcing them into it would be a
  # worse lie than the copies were.
  module BaselineRatchet
    def counts(findings = scan)
      self::BASELINES.keys.to_h { |kind| [ kind, findings.count { |f| f.kind == kind } ] }
    end

    def over_baseline(findings = scan)
      counts(findings).filter_map do |kind, count|
        baseline = self::BASELINES.fetch(kind)
        "#{kind}: #{count} (baseline #{baseline}, +#{count - baseline})" if count > baseline
      end
    end
  end
end
