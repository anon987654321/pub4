# frozen_string_literal: true

require "tty-prompt"

module Master
  module Reach
    module SocialSim
      module Tui
        class Error < StandardError; end

        module_function

        def run(run_dir:)
          prompt = TTY::Prompt.new(interrupt: :exit)
          loop do
            state = Inbox.load(run_dir)
            choice = prompt.select(
              Guard.banner,
              thread_choices(state) + ["Tick +1 hour", "Stats", "Quit"]
            )
            break if choice == "Quit"
            handle_choice(run_dir, state, choice, prompt)
          end
          "tui: closed #{run_dir}"
        end

        def handle_choice(run_dir, state, choice, prompt)
          case choice
          when "Tick +1 hour"
            Director.tick(run_dir: run_dir, hours: 1, auto_mode: "manual")
          when "Stats"
            metrics = Metrics.compute(state)
            prompt.say(Metrics.dashboard_text(metrics))
          else
            reply_in_thread(run_dir, state, choice, prompt)
          end
        end

        def thread_choices(state)
          state[:npcs].map do |npc_id, npc|
            thread = state[:threads][npc_id]
            count = thread ? thread[:messages].size : 0
            "#{npc[:handle]} (#{count} msgs)"
          end
        end

        def reply_in_thread(run_dir, state, label, prompt)
          npc_id = npc_id_from_label(state, label)
          thread = state[:threads][npc_id] || { messages: [] }
          transcript = thread[:messages].map { |m| format_line(state, npc_id, m) }.join("\n")
          prompt.say(transcript.empty? ? "(no messages yet)" : transcript)
          body = prompt.ask("Reply as #{state[:subject][:display_name]} (blank to skip)")
          return if body.to_s.strip.empty?

          Director.subject_reply!(run_dir: run_dir, npc_id: npc_id, body: body)
        end

        def format_line(state, npc_id, message)
          who = message[:from].to_s == "npc" ? state[:npcs][npc_id][:handle] : state[:subject][:display_name]
          "[h#{message[:sim_hour]}] #{who}: #{message[:body]}"
        end

        def npc_id_from_label(state, label)
          handle = label.split(" (", 2).first
          state[:npcs].find { |_, npc| npc[:handle] == handle }&.first || raise(Error, "bad thread")
        end
      end
    end
  end
end