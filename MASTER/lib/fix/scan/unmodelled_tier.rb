# frozen_string_literal: true

require_relative "../../review/scan/law_factory"

module Master
  module Fix
    module Scan
      # FileProcessor's handling of model laws that hold no agent. It reads the processor's
      # semantic-gap state, so it is a mixin rather than a collaborator.
      module UnmodelledTier
        def self.unmodelled?(law) = law.is_a?(Review::Scan::LawFactory::AgentGuard) && !law.agent?

        private

        # A model law built without an agent could only answer "no model agent configured", once per
        # file, and run through its rescue each time; scan-only callers (self_findings, self_check,
        # the lint) build every scanner that way. The file keeps its gap, so it is not called clean,
        # and the tier is named inconclusive once a run instead of once a file.
        def modelled(reading)
          unmodelled = reading.laws.select { |law| UnmodelledTier.unmodelled?(law) }
          return reading if unmodelled.empty?

          note_unmodelled(reading.path, unmodelled)
          reading.with(laws: reading.laws - unmodelled)
        end

        def note_unmodelled(path, laws)
          ids = laws.map { |law| law.id.to_s }
          detail = "INCONCLUSIVE: no model agent configured for #{ids.join(", ")}"

          announce = @semantic_gap_mutex.synchronize do
            @semantic_gaps[relative_progress_path(path)] ||= detail
            first = !@unmodelled_notice_emitted
            @unmodelled_notice_emitted = true
            first
          end
          return unless announce

          @bus&.publish("scan:semantic_inconclusive", path: nil, law: ids.join(","), message: detail)
          note = "semantic tier inconclusive, no model agent configured; #{ids.size} law(s) not asked"
          Master::Trace::Dmesg.status("law0", note)
        end
      end
    end
  end
end
