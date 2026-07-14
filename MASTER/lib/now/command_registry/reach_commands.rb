# frozen_string_literal: true

require_relative "../../reach/brgen_bridge"

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
          "brgen" => command(:dispatch_brgen_status),
        }
      end

      def dispatch_brgen_status(ctx: nil)
        Master::Reach::BrgenBridge.summary
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

      def run_tool(root, tool, args)
        Master::Reach::ScriptDispatch.run_string(root: root, tool: tool, arg: args.to_s)
      end
    end
  end
end
