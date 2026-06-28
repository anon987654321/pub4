# frozen_string_literal: true

module Master
  module Reach
    module SocialSim
      module Director
        class Error < StandardError; end

        module_function

        def tick(run_dir:, hours: 1, auto_mode: nil)
          state = Inbox.load(run_dir)
          mode = auto_mode || state[:subject][:auto_mode]
          hours = [hours.to_i, 1].max

          hours.times do
            state[:sim_hour] += 1
            npc_tick!(run_dir, state)
            AutoSubject.apply!(state, mode: mode) unless mode == "manual"
          end

          Inbox.save!(run_dir, state)
          metrics = Metrics.compute(state)
          Logger.append(run_dir, type: "tick", sim_hour: state[:sim_hour], metrics: metrics)
          { state: state, metrics: metrics }
        end

        def npc_tick!(run_dir, state)
          state[:npcs].each do |npc_id, npc|
            next if npc[:status] == "given_up"

            persona = Personas.find(npc_id)
            next unless persona

            if should_give_up?(state, npc_id: npc_id, npc: npc)
              npc[:status] = "given_up"
              next
            end

            next unless roll_message?(state, npc: npc, persona: persona)

            body = pick_message(persona, npc: npc)
            Inbox.append_message!(state, npc_id: npc_id, from: :npc, body: body, sim_hour: state[:sim_hour])
            npc[:last_outbound_hour] = state[:sim_hour]
            npc[:outbound_count] += 1
            Logger.append(
              run_dir,
              type: "npc_message",
              npc_id: npc_id,
              handle: npc[:handle],
              sim_hour: state[:sim_hour],
              body: body
            )
          end
        end

        def subject_reply!(run_dir:, npc_id:, body:)
          state = Inbox.load(run_dir)
          Inbox.append_message!(state, npc_id: npc_id, from: :subject, body: body, sim_hour: state[:sim_hour])
          npc = state[:npcs][npc_id]
          raise Error, "unknown npc #{npc_id}" unless npc

          npc[:last_inbound_hour] = state[:sim_hour]
          AutoSubject.mark_declined_if_needed!(state, npc_id: npc_id, body: body)
          Inbox.save!(run_dir, state)
          Logger.append(run_dir, type: "subject_reply", npc_id: npc_id, body: body, sim_hour: state[:sim_hour])
          state
        end

        def should_give_up?(state, npc_id:, npc:)
          thread = state[:threads][npc_id]
          return false unless thread

          last_in = npc[:last_inbound_hour]
          last_out = npc[:last_outbound_hour]
          return false unless last_out && !last_in

          (state[:sim_hour] - last_out) >= npc[:patience_hours]
        end

        def roll_message?(state, npc:, persona:)
          rate = persona[:message_rate] * (0.5 + persona[:respect_boundaries])
          thread = state[:threads][npc[:id]]
          rate *= 1.25 if thread.nil? || thread[:messages].empty?
          Random.new(state[:seed].to_i + state[:sim_hour] + npc[:id].hash).rand < rate
        end

        def pick_message(persona, npc:)
          pool = npc[:outbound_count].to_i.zero? ? persona[:opener_pool] : persona[:followup_pool]
          pool.sample(random: Random.new(npc[:id].hash + npc[:outbound_count]))
        end

      end
    end
  end
end