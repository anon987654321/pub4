# frozen_string_literal: true

module Master
  module Ground
    class PrincipleMap
      # Read-only lookups over `principles` by status/tag -- grouped apart
      # from loading/integrity to keep PrincipleMap itself under the
      # NO_GOD_CLASS public-method ceiling (a mixin's methods aren't counted
      # against the including class since they live in their own ModuleNode).
      module Queries
        def [](id)
          principles[id.to_s]
        end

        def covered
          principles.select { |_, e| e.status == "covered" }
        end

        def gaps
          principles.select { |_, e| e.status == "gap" }
        end

        def by_tag(tag)
          principles.select { |_, e| e.tags.map(&:to_s).include?(tag.to_s) }
        end

        def aesthetic
          by_tag("aesthetic").merge(by_tag("ui"))
        end

        def operation_for(rule_id)
          rid = rule_id.to_s
          principles.each_value do |entry|
            return entry.operation if entry.rule_ids.map(&:to_s).include?(rid) && entry.operation
          end
          nil
        end

        def rules_for(principle_id)
          entry = self[principle_id]
          entry ? entry.rule_ids : []
        end
      end
    end
  end
end
