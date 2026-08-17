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
        rescue ArgumentError
          klass.new
        end

        def registry_id(klass, root: Master::ROOT, agent: nil, ecology: nil)
          build(klass, root:, agent:, ecology:).id.to_s.downcase
        rescue StandardError
          nil
        end
      end
    end
  end
end
