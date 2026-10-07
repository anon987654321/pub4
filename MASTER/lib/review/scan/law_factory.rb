# frozen_string_literal: true

module Master
  module Review
    module Scan
      # Single instantiation path for scan rule classes (avoids ArgumentError drift).
      module RuleFactory
        BRIDGE_CLASSES = %w[YamlDeclarativeRule VetoPatternRule LawBridgeRule].freeze

        module_function

        def bridge_class?(klass)
          name = klass.name.to_s
          BRIDGE_CLASSES.any? { |token| name.include?(token) }
        end

        def build(klass, root: Master::ROOT, agent: nil, ecology: nil)
          return klass.new if klass.auto_build?

          case klass.name
          when /CoChangeCouplingRule/ then klass.new(root:, ecology:)
          when /SemanticRule|AdversarialRule|CommentDriftRule/ then klass.new(agent:)
          when /RuleCoverageRule|RubocopRule|ReekRule|InterconnectRule|YamlDeclarativeRule|VetoPatternRule|LawBridgeRule|AstOmissionRule/
            klass.new(root:)
          else klass.new(root:)
          end
        rescue ArgumentError => e
          # This rescue exists for one shape: a rule whose initialize does not
          # take the keywords offered. Law's prove! also raises ArgumentError,
          # and retrying bare here turned "a fixture stopped flagging" into
          # half the law silently missing — LawBridgeRule.new re-ran with
          # Law.rules already half-populated and constructed quietly. A
          # failure that is not a signature mismatch stays a failure.
          raise unless e.message.match?(/unknown keyword|wrong number of arguments/)

          klass.new
        end

        def registry_id(klass, root: Master::ROOT, agent: nil, ecology: nil)
          build(klass, root:, agent:, ecology:).id.to_s.downcase
        rescue StandardError # scan: intentional — non-auto-buildable rules have no registry id; nil IS the census answer
          nil
        end
      end
    end
  end
end
