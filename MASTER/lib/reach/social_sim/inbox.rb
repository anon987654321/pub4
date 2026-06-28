# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Master
  module Reach
    module SocialSim
      module Inbox
        class Error < StandardError; end

        module_function

        def init_run(subject_name:, persona_count: 12, seed: nil, root: Master::ROOT)
          subject = Subject.load(subject_name)
          npcs = Personas.sample(count: persona_count, seed: seed)
          raise Error, "no personas loaded" if npcs.empty?

          run_id = format("%s_%s", subject_name, Time.now.utc.strftime("%Y%m%dT%H%M%SZ"))
          run_dir = File.join(root, "output", "social_sim", run_id)
          Guard.assert_sandbox!(run_dir: run_dir)

          state = {
            run_id: run_id,
            subject: subject,
            sim_hour: 0,
            seed: seed,
            npcs: npcs.to_h { |npc| [npc[:id], npc_state(npc)] },
            threads: {},
            flags: { synthetic_only: true },
          }

          save!(run_dir, state)
          write_manifest!(run_dir, state)
          Logger.append(run_dir, type: "init", at: Time.now.utc.iso8601, banner: Guard.banner)
          { run_dir: run_dir, run_id: run_id, state: state }
        end

        def load(run_dir)
          path = File.join(run_dir, "state.json")
          raise Error, "missing state at #{run_dir}" unless File.file?(path)

          JSON.parse(File.read(path), symbolize_names: true)
        end

        def save!(run_dir, state)
          Guard.assert_sandbox!(run_dir: run_dir)
          FileUtils.mkdir_p(run_dir)
          File.write(File.join(run_dir, "state.json"), JSON.pretty_generate(state))
          Metrics.write!(run_dir, state)
        end

        def append_message!(state, npc_id:, from:, body:, sim_hour:)
          thread = state[:threads][npc_id] ||= { messages: [], declined_at: nil }
          thread[:messages] << { from: from.to_s, body: body.to_s, sim_hour: sim_hour }
          state
        end

        def mark_declined!(state, npc_id:, sim_hour:)
          thread = state[:threads][npc_id] ||= { messages: [], declined_at: nil }
          thread[:declined_at] = sim_hour
          state
        end

        def npc_state(npc)
          {
            id: npc[:id],
            handle: npc[:handle],
            archetype: npc[:archetype],
            respect_boundaries: npc[:respect_boundaries],
            patience_hours: npc[:patience_hours],
            message_rate: npc[:message_rate],
            status: "active",
            last_outbound_hour: nil,
            last_inbound_hour: nil,
            outbound_count: 0,
          }
        end

        def write_manifest!(run_dir, state)
          manifest = {
            banner: Guard.banner,
            run_id: state[:run_id],
            subject: state[:subject][:id],
            persona_count: state[:npcs].size,
            seed: state[:seed],
          }
          File.write(File.join(run_dir, "manifest.json"), JSON.pretty_generate(manifest))
        end
      end
    end
  end
end