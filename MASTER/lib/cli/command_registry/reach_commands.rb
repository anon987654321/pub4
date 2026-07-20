# frozen_string_literal: true

require_relative "../../io/brgen_bridge"
require_relative "../../review/council/critique"
require_relative "../../voice/mix_metrics"

module Master
  module CLI
    module CommandRegistry
      module_function

      def reach_commands(root:, agent: nil, bus: nil)
        {
          "postpro" => command(:dispatch_postpro, root),
          "repligen" => command(:dispatch_repligen, root),
          "photograph" => command(:dispatch_repligen, root),
          "dilla" => command(:dispatch_dilla, root, agent, bus),
          "brgen" => command(:dispatch_brgen_status),
        }
      end

      def dispatch_brgen_status(ctx: nil)
        Master::Io::BrgenBridge.summary
      end

      def dispatch_postpro(root, ctx: nil)
        run_tool(root, "postpro", arg_for(ctx))
      end

      def dispatch_repligen(root, ctx: nil)
        run_tool(root, "repligen", arg_for(ctx))
      end

      def dispatch_dilla(root, agent = nil, bus = nil, ctx: nil)
        args = arg_for(ctx).to_s.strip
        head, *rest = args.split(/\s+/, 2)
        case head.to_s.downcase
        when "crit", "critique", "review"
          dispatch_dilla_crit(root, agent, bus, rest.join(" ").strip)
        when "metrics", "ears"
          path = rest.join(" ").strip
          path = Master::Voice::MixMetrics.first_existing_demo(root) if path.empty?
          return "dilla metrics: no audio path (render first or pass a .wav)" unless path
          Master::Voice::MixMetrics.brief(path)
        when "generate", ""
          gen_args = head.to_s.downcase == "generate" ? rest.join(" ") : args
          gen_args = "generate --style dilla" if gen_args.empty?
          gen_args = "generate #{gen_args}" unless gen_args.start_with?("generate")
          run_tool(root, "dilla", gen_args)
        else
          # Bare flags / path → generate; unknown subcommands fall through to tool.
          run_tool(root, "dilla", args.start_with?("generate") ? args : "generate #{args}")
        end
      end

      # Persona panel → multi-solution ideation → cherry-pick (Council::Critique).
      # Engine only supplies audio + mix metrics; it does not host its own council.
      def dispatch_dilla_crit(root, agent, bus, path_arg)
        path = path_arg.to_s.strip
        path = Master::Voice::MixMetrics.first_existing_demo(root) if path.empty?
        metrics_line = path ? Master::Voice::MixMetrics.brief(path) : "mix metrics: no demo yet"
        return "#{metrics_line}\ndilla crit: agent unavailable — metrics only. Start full CLI and /dilla crit." unless agent

        critic = Master::Review::Council::Critique.new(
          mode: :dilla, agent: agent, event_bus: bus, audio_path: path
        )
        result = critic.run
        return "dilla crit: #{result.message}" unless result.ok?

        dilla_crit_report(result.value!, metrics_line)
      end

      def dilla_crit_report(data, metrics_line)
        lines = [
          "dilla crit: #{Array(data[:cherry_picks]).size} cherry-pick(s) (MASTER council)",
          metrics_line,
        ]
        Array(data[:feedback]).each do |f|
          first = f[:feedback].to_s.lines.first.to_s.strip
          lines << "  [#{f[:persona]}] #{first}"
        end
        Array(data[:cherry_picks]).each { |p| lines << "  cherry: #{p}" }
        lines << "hint: apply picks via engine ENV / DILLA_STYLE_DEFAULTS, then /dilla generate"
        lines.join("\n")
      end

      def run_tool(root, tool, args)
        Master::Io::ScriptDispatch.run_string(root: root, tool: tool, arg: args.to_s)
      end
    end
  end
end
