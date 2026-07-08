# frozen_string_literal: true

module Master
  module Now
    module CommandRegistry
      module_function

      # /fold <goal> — run a coding goal through the kernel Fold (the rebuild's
      # runtime) instead of the legacy pipeline. Additive during the cutover.
      def kernel_commands(root:, bus: nil)
        {
          "fold" => command(:dispatch_fold, root, bus),
        }
      end

      def dispatch_fold(root, bus, ctx: nil)
        Master::Now::KernelBridge.run_string(arg_for(ctx), root:, bus:)
      end
    end
  end
end
