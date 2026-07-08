# frozen_string_literal: true

require_relative "../../kernel/master"

module Master
  module Now
    # KernelBridge — run one coding goal through the kernel Fold from inside the
    # interactive CLI. The Fold (kernel/) is the runtime this rebuild is folding
    # toward; the bridge routes a single goal to it while the legacy pipeline still
    # handles everything else, so the cutover stays incremental and always green.
    #
    # Turns stream to the event bus as they happen, so the terminal and the web
    # dashboard see the same live trace they get from the legacy path.
    module KernelBridge
      module_function

      def run(goal, root:, bus: nil, model: nil, max_turns: 40)
        transcript = []
        observer = lambda do |turn:, effect:, observation:|
          transcript << "#{turn}: #{effect} -> #{observation}"
          bus&.publish("kernel:turn", turn:, effect: effect.to_s, ok: observation.ok?, detail: observation.message)
        end

        done = Master::Kernel::Fold.new(
          model:       model || Master::Kernel::Model.new,
          constitution: Master::Kernel::Constitution.load(data_dir: Master.data_path),
          world:       Master::Kernel::World.new(root:),
          memory:      Master::Kernel::Memory.new,
          max_turns:,
          observer:
        ).run(goal)

        { reason: done.reason, turns: done.turns, summary: done.summary, transcript: }
      end

      def run_string(goal, root:, bus: nil, model: nil)
        return "kernel: no goal" if goal.to_s.strip.empty?

        result = run(goal, root:, bus:, model:)
        header = "kernel: #{result[:reason]} turns=#{result[:turns]}"
        [header, *result[:transcript], result[:summary]].compact.join("\n")
      end
    end
  end
end
