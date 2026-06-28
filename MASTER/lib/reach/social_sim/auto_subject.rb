# frozen_string_literal: true

module Master
  module Reach
    module SocialSim
      # Scripted subject replies for automated sim runs (not real people).
      module AutoSubject
        NOT_INTERESTED = [
          "not interested",
          "please stop",
          "i said no",
          "leave me alone",
        ].freeze

        BUSY = ["busy", "lol", "maybe later", "idk", "k"].freeze

        module_function

        def apply!(state, mode:)
          mode = mode.to_s
          return state if mode == "manual"

          state[:npcs].each_key do |npc_id|
            reply = reply_for(state, npc_id: npc_id, mode: mode)
            next unless reply

            Inbox.append_message!(state, npc_id: npc_id, from: :subject, body: reply, sim_hour: state[:sim_hour])
            npc = state[:npcs][npc_id]
            npc[:last_inbound_hour] = state[:sim_hour]
            mark_declined_if_needed!(state, npc_id: npc_id, body: reply)
          end
          state
        end

        def reply_for(state, npc_id:, mode:)
          thread = state[:threads][npc_id]
          return nil unless thread && thread[:messages].any?
          return nil if thread[:messages].last[:from].to_s == "subject"

          npc = state[:npcs][npc_id]
          outbound = thread[:messages].count { |m| m[:from].to_s == "npc" }
          case mode
          when "ghost"
            ghost_reply(state, outbound: outbound)
          when "busy"
            BUSY.sample(random: random(state))
          when "not_interested"
            NOT_INTERESTED.sample(random: random(state))
          end
        end

        def ghost_reply(state, outbound:)
          limit = state[:subject].fetch(:ghost_after_messages, 3).to_i
          return nil if limit.zero?
          return nil if outbound > limit

          BUSY.sample(random: random(state))
        end

        def mark_declined_if_needed!(state, npc_id:, body:)
          return unless NOT_INTERESTED.any? { |phrase| body.downcase.include?(phrase) }

          Inbox.mark_declined!(state, npc_id: npc_id, sim_hour: state[:sim_hour])
        end

        def random(state)
          seed = state[:seed].to_i + state[:sim_hour].to_i
          Random.new(seed)
        end
      end
    end
  end
end
