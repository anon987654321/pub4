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
      end

    end
  end
end
