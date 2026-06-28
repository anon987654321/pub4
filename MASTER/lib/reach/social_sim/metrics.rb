# frozen_string_literal: true

require "json"
require "fileutils"

module Master
  module Reach
    module SocialSim
      module Metrics
        COMPOSE_MINUTES = 2.5

        module_function

        def compute(state)
          threads = state.fetch(:threads, {})
          npc_messages = threads.values.sum { |thread| thread[:messages].count { |m| from_npc?(m) } }
          subject_replies = threads.values.sum { |thread| thread[:messages].count { |m| from_subject?(m) } }
          given_up = state.fetch(:npcs, {}).values.count { |npc| npc[:status] == "given_up" }
          violations = boundary_violations(state)

          {
            simulated_hour: state.fetch(:sim_hour, 0),
            npc_messages: npc_messages,
            subject_replies: subject_replies,
            active_threads: threads.count { |_, thread| thread[:messages].any? },
            npcs_given_up: given_up,
            boundary_violations: violations.size,
            estimated_waste_minutes: (npc_messages * COMPOSE_MINUTES).round(1),
            violation_npc_ids: violations.map { |row| row[:npc_id] }.uniq,
          }
        end

        def write!(run_dir, state)
          Guard.assert_sandbox!(run_dir: run_dir)
          payload = compute(state)
          File.write(File.join(run_dir, "metrics.json"), JSON.pretty_generate(payload))
          payload
        end

        def dashboard_text(metrics)
          [
            "sim hour: #{metrics[:simulated_hour]}",
            "npc messages: #{metrics[:npc_messages]}",
            "subject replies: #{metrics[:subject_replies]}",
            "active threads: #{metrics[:active_threads]}",
            "npcs given up: #{metrics[:npcs_given_up]}",
            "boundary violations: #{metrics[:boundary_violations]}",
            "est. npc time wasted (min): #{metrics[:estimated_waste_minutes]}",
          ].join("\n")
        end

        def from_npc?(message)
          message[:from].to_s == "npc"
        end

        def from_subject?(message)
          message[:from].to_s == "subject"
        end

        def boundary_violations(state)
          state.fetch(:threads, {}).flat_map do |npc_id, thread|
            declined_at = thread[:declined_at]
            next [] unless declined_at

            thread[:messages].filter_map do |message|
              next unless from_npc?(message)
              next unless message[:sim_hour].to_i > declined_at

              { npc_id: npc_id, sim_hour: message[:sim_hour], body: message[:body] }
            end
          end
        end
      end
    end
  end
end
