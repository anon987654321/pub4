# frozen_string_literal: true

require_relative "routing/availability_policy"
require_relative "routing/provider_health"

module Master
  module CLI
    # The final line of an LLM turn is a capability receipt. Unknown health is
    # reported as unknown; stale evidence is reported as stale; neither is
    # silently presented as healthy.
    module CapabilityStamp
      module_function

      def render(model:, root: Master::ROOT, provider_health: nil, policy: nil)
        id = model.to_s.strip
        return if id.empty?

        health = provider_health || Routing::ProviderHealth.new(
          path: File.join(root, "runtime", "telemetry", "provider_health.ndjson")
        )
        availability = policy || Routing::AvailabilityPolicy.new(root:)
        age = health.age_seconds(id)
        freshness = health.freshness(id, max_age_s: availability.health_freshness_s)
        health_text =
          case freshness
          when :fresh then "fresh #{age.to_i}s"
          when :stale then "stale #{age.to_i}s"
          else "unknown"
          end
        degraded = case freshness
                    when :fresh then "no"
                    when :stale then "yes"
                    else "unknown"
                    end

        "[served: #{id} @#{availability.level_for(id)} | health: #{health_text} | degraded: #{degraded}]"
      rescue StandardError => e
        Master::Ground::Swallow.log(e, context: "capability_stamp.render", model:)
        "[served: #{id} | health: unknown | degraded: unknown]"
      end
    end
  end
end
