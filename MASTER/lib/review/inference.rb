# frozen_string_literal: true

module Master
  module Review
    module Inference
      # One public entrypoint for advanced inference. The Agent remains the
      # transport façade; this namespace owns deliberation strategy only.
      def self.run(agent:, prompt:, task_type: :exploration, strategy: nil, event_bus: nil, root: Master::ROOT, **options)
        Runner.new(agent:, event_bus:, root:).run(prompt:, task_type:, strategy:, **options)
      end
    end
  end
end
