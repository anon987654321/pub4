# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Single instantiation path for scan law classes (avoids ArgumentError drift).
      module LawFactory
        module_function

        def build(klass, root: Master::ROOT, agent: nil, ecology: nil)
          return klass.new if klass.auto_build?

          case klass.name
          when /CoChangeCouplingLaw/ then klass.new(root:, ecology:)
          when /SemanticLaw|AdversarialLaw|CommentDriftLaw/ then klass.new(agent:)
          when /LawCoverageLaw|RubocopLaw|ReekLaw|InterconnectLaw|VetoPatternLaw|AstOmissionLaw|FileSprawlLaw|PathPurposeLaw|LibRootDisciplineLaw/
            klass.new(root:)
          else
            klass.new
          end
        end

        def registry_id(klass, root: Master::ROOT, agent: nil, ecology: nil)
          id = build(klass, root:, agent:, ecology:).id.to_s.strip.downcase
          raise ArgumentError, "#{klass} has no Law identity" if id.empty? || id == "unknown"

          id
        end

        # Prepended to every Laws::NeedsModel law, so it runs in front of the law's own
        # rescue. A missing agent is how the scanner was built, not a model fault: raised
        # inside that rescue it wrote a load_bearing swallow row per file (3,627 a run),
        # and returned as [] it read as an answer of clean.
        module AgentGuard
          def agent? = !@agent.nil?

          def check(code, path:)
            return super if agent?

            raise "semantic assessment INCONCLUSIVE: no model agent configured for #{path}"
          end
        end
      end
    end
  end
end
