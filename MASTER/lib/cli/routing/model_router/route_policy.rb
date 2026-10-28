# frozen_string_literal: true

require "set"

module Master
  module CLI
    module Routing
      # Deterministic core for route candidate selection. ModelRouter gathers
      # live facts; this policy decides from that snapshot without doing I/O.
      module RoutePolicy
        Decision = Data.define(
          :candidates, :reachable, :parked, :usable, :recently_failed, :selected, :reason
        )

        module_function

        def normalize(models)
          Array(models).filter_map do |model|
            id = model.to_s.strip
            id unless id.empty?
          end.uniq
        end

        def call(candidates:, reachable:, parked:, usable:, recently_failed:, meets_floor:, local:)
          ids = normalize(candidates)
          live = intersection(ids, reachable)
          parked_ids = intersection(live, parked)
          unparked = live.reject { |id| parked_ids.include?(id) }
          usable_ids = intersection(unparked, usable)
          # If any lane is usable, never let an unusable-but-not-yet-failed lane
          # outrank it. When none are usable, preserve the candidates so the
          # downstream dispatcher can produce its typed offline diagnosis.
          eligible = usable_ids.empty? ? unparked : usable_ids
          failed = intersection(eligible, recently_failed)
          answering = eligible.reject { |id| failed.include?(id) }

          if answering.any?
            selected = answering
            reason = :answering_candidates
          else
            floor = intersection(unparked, meets_floor)
            local_floor = intersection(floor, local)
            selected = local_floor.empty? ? floor : local_floor
            reason = if unparked.empty?
                       live.empty? ? :no_reachable_candidates : :all_candidates_parked
                     elsif selected.empty?
                       :recent_failures_without_floor
                     else
                       :all_answering_candidates_recently_failed
                     end
          end

          selected_is_usable = selected.any? { |id| usable_ids.include?(id) }
          reason = :no_usable_candidates if selected.any? && !selected_is_usable

          Decision.new(
            candidates: ids.freeze,
            reachable: live.freeze,
            parked: parked_ids.freeze,
            usable: usable_ids.freeze,
            recently_failed: failed.freeze,
            selected: selected.freeze,
            reason:,
          )
        end

        def intersection(ordered, members)
          accepted = normalize(members).to_set
          ordered.select { |id| accepted.include?(id) }
        end
        private_class_method :intersection
      end
    end
  end
end
