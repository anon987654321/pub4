# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      module_function

      def reach_commands(root:)
        {
          "postpro" => command(:dispatch_postpro, root),
          "repligen" => command(:dispatch_repligen, root),
          "photograph" => command(:dispatch_repligen, root),
          "dilla" => command(:dispatch_dilla, root),
          "video" => command(:dispatch_video),
          "motion-dataset" => command(:dispatch_motion_dataset),
          "lora-train" => command(:dispatch_lora, "train"),
          "lora-check" => command(:dispatch_lora, "check"),
          "lora-generate" => command(:dispatch_lora, "generate"),
          "lora-postpro" => command(:dispatch_lora, "postpro"),
          "lora" => command(:dispatch_lora_summary),
        }
      end

      def dispatch_postpro(root, ctx: nil)
        run_tool(root, "postpro", arg_for(ctx))
      end

      def dispatch_repligen(root, ctx: nil)
        run_tool(root, "repligen", arg_for(ctx))
      end

      def dispatch_dilla(root, ctx: nil)
        args = arg_for(ctx).to_s.strip
        args = "generate --style dilla" if args.empty?
        run_tool(root, "dilla", args)
      end

      def dispatch_video(ctx: nil)
        arg = arg_for(ctx).to_s.strip
        return Master::Reach::VideoChain.help if arg.empty?

        "warn: /video #{arg} not wired — cloud via /repligen, local identity LoRA via /lora-train"
      end

      def dispatch_motion_dataset(ctx: nil)
        arg = arg_for(ctx).to_s.strip
        arg.empty? ? "warn: motion-dataset not wired — prepare clips under lora/training/" : "warn: motion-dataset #{arg} not wired yet"
      end

      def dispatch_lora(default_mode, ctx: nil)
        mode = resolve_lora_mode(arg_for(ctx), default_mode)
        result = Master::Reach::LoraPipeline.run(mode: mode)
        result.ok? ? result.value! : result.message
      end

      def dispatch_lora_summary(ctx: nil)
        arg = arg_for(ctx).to_s.strip.downcase
        return Master::Reach::LoraPipeline.summary if arg.empty? || arg == "help"

        dispatch_lora("check", ctx: ctx)
      end

      def resolve_lora_mode(args, default_mode)
        token = args.to_s.strip.downcase.split(/\s+/, 2).first
        case token
        when "", "ragnhild", "ragnhild_v2" then default_mode
        when "check", "--check" then "check"
        when "train", "--train" then "train"
        when "generate", "--generate" then "generate"
        when "postpro", "--postpro" then "postpro"
        else default_mode
        end
      end

      def run_tool(root, tool, args)
        Master::Reach::ScriptDispatch.run_string(root: root, tool: tool, arg: args.to_s)
      end
    end
  end
end
