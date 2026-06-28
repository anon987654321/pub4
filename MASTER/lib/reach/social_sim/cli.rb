# frozen_string_literal: true

module Master
  module Reach
    module SocialSim
      module CLI
        class Error < StandardError; end

        module_function

        def parse_args(argv)
          tokens = Array(argv).dup
          command = tokens.shift.to_s
          command = "help" if command.empty?

          options = {
            subject: "ragnhild",
            personas: 12,
            seed: nil,
            hours: 1,
            auto: nil,
            run_dir: nil,
            lora: nil,
            preset: "social",
            stock: "kodak_portra",
          }

          until tokens.empty?
            token = tokens.shift
            case token
            when "--subject" then options[:subject] = tokens.shift
            when "--personas" then options[:personas] = (tokens.shift || "12").to_i
            when "--seed" then options[:seed] = (tokens.shift || "0").to_i
            when "--hours", "--ticks" then options[:hours] = (tokens.shift || "1").to_i
            when "--auto" then options[:auto] = tokens.shift
            when "--run" then options[:run_dir] = tokens.shift
            when "--lora" then options[:lora] = tokens.shift
            when "--preset" then options[:preset] = tokens.shift
            when "--stock" then options[:stock] = tokens.shift
            else
              options[:run_dir] ||= token if command != "init" && token.start_with?("/")
            end
          end

          { command: command, options: options }
        end

        def run(parsed, root: Master::ROOT)
          command = parsed[:command]
          opts = parsed[:options]

          case command
          when "help", "-h", "--help" then usage
          when "init" then cmd_init(opts, root: root)
          when "tick" then cmd_tick(opts)
          when "stats" then cmd_stats(opts)
          when "replay" then cmd_replay(opts)
          when "tui" then cmd_tui(opts)
          when "dashboard" then cmd_dashboard(opts)
          when "visuals" then cmd_visuals(opts, root: root)
          else
            raise Error, "unknown command #{command}\n#{usage}"
          end
        rescue Guard::Violation, Inbox::Error, Director::Error, Subject::Error, Visuals::Error => e
          "social-sim: #{e.message}"
        end

        def cmd_init(opts, root:)
          result = Inbox.init_run(
            subject_name: opts[:subject],
            persona_count: opts[:personas],
            seed: opts[:seed],
            root: root
          )
          [
            Guard.banner,
            "init: run=#{result[:run_id]}",
            "dir: #{result[:run_dir]}",
            "subject: #{opts[:subject]} personas: #{opts[:personas]}",
            "next: bundle exec ruby bin/social_sim tick --run #{result[:run_dir]}",
          ].join("\n")
        end

        def cmd_tick(opts)
          run_dir = resolve_run!(opts)
          mode = opts[:auto]
          result = Director.tick(run_dir: run_dir, hours: opts[:hours], auto_mode: mode)
          [
            "tick: hour=#{result[:state][:sim_hour]} auto=#{mode || 'manual'}",
            Metrics.dashboard_text(result[:metrics]),
          ].join("\n")
        end

        def cmd_stats(opts)
          run_dir = resolve_run!(opts)
          state = Inbox.load(run_dir)
          metrics = Metrics.compute(state)
          ["run: #{state[:run_id]}", Metrics.dashboard_text(metrics)].join("\n")
        end

        def cmd_replay(opts)
          run_dir = resolve_run!(opts)
          state = Inbox.load(run_dir)
          events = Logger.read_all(run_dir)
          lines = events.last(20).map { |event| "#{event['type']}: #{event.except('type').to_json}" }
          ["replay: #{state[:run_id]} (last #{lines.size} events)", *lines].join("\n")
        end

        def cmd_tui(opts)
          run_dir = resolve_run!(opts)
          Tui.run(run_dir: run_dir)
        end

        def cmd_dashboard(opts)
          run_dir = resolve_run!(opts)
          state = Inbox.load(run_dir)
          metrics = Metrics.compute(state)
          rows = state[:npcs].map do |npc_id, npc|
            thread = state[:threads][npc_id]
            msgs = thread ? thread[:messages].size : 0
            "#{npc[:handle]} | #{npc[:status]} | msgs=#{msgs} | respect=#{npc[:respect_boundaries]}"
          end
          [Metrics.dashboard_text(metrics), "threads:", *rows].join("\n")
        end

        def cmd_visuals(opts, root:)
          run_dir = resolve_run!(opts)
          generated = Visuals.generate_feed!(run_dir: run_dir, lora_id: opts[:lora], root: root)
          graded = Visuals.grade_feed!(
            run_dir: run_dir,
            preset: opts[:preset],
            stock: opts[:stock],
            root: root
          )
          [
            "visuals: avatars=#{generated[:files].size} dir=#{generated[:avatar_dir]}",
            "graded: #{graded[:files].size} dir=#{graded[:graded_dir]}",
          ].join("\n")
        rescue Visuals::Error => e
          "visuals: #{e.message} (skip with manual avatars in #{run_dir}/avatars/)"
        end

        def resolve_run!(opts)
          run_dir = opts[:run_dir].to_s.strip
          run_dir = latest_run if run_dir.empty?
          raise Error, "no run dir — pass --run or run init first" if run_dir.to_s.empty?

          File.expand_path(run_dir)
        end

        def latest_run
          base = File.join(Master::ROOT, "output", "social_sim")
          return nil unless File.directory?(base)

          Dir.glob(File.join(base, "*")).select { |path| File.directory?(path) }
            .max_by { |path| File.mtime(path) }
        end

        def usage
          <<~HELP.strip
            usage: social-sim <command> [options]

            commands:
              init     --subject ragnhild [--personas 12] [--seed N]
              tick     --run DIR [--hours N] [--auto busy|ghost|not_interested]
              stats    --run DIR
              dashboard --run DIR
              replay   --run DIR
              tui      --run DIR
              visuals  --run DIR [--lora basicfeatures/ragnhild] [--preset social] [--stock kodak_portra]

            #{Guard.banner}
          HELP
        end
      end
    end
  end
end