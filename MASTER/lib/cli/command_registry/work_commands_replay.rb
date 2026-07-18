# frozen_string_literal: true

module Master
  module CLI
    module CommandRegistry
      module_function

      def dispatch_replay(root:, trace: nil, ctx: nil)
        Trace::ReplayReader.new(root: root, recorder: trace).render(arg: arg_for(ctx))
      rescue StandardError => e
        "replay: #{e.message}"
      end
    end
  end
end
