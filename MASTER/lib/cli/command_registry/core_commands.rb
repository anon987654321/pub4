# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      # /fold <goal> — run a coding goal through the core Fold (the rebuild's
      # runtime) instead of the legacy pipeline. Additive during the cutover.
      def core_commands(root:, bus: nil, model_id: nil)
        {
          "fold" => command(:dispatch_fold, root, bus, model_id),
        }
      end

      def dispatch_fold(root, bus, model_id, ctx: nil)
        Master::CLI::CoreBridge.run_string(arg_for(ctx), root:, bus:, model_id:)
      end
    end
  end
end
