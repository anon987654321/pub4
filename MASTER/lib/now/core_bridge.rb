# frozen_string_literal: true

require_relative "../../core/master"

module Master
  module Now
    # CoreBridge — run one coding goal through the kernel Fold from inside the
    # interactive CLI. The Fold (kernel/) is the runtime this rebuild is folding
    # toward; the bridge routes a single goal to it while the legacy pipeline still
    # handles everything else, so the cutover stays incremental and always green.
    #
    # Turns stream to the event bus as they happen, so the terminal and the web
    # dashboard see the same live trace they get from the legacy path.
    module CoreBridge
      module_function

      def run(goal, root:, bus: nil, model: nil, max_turns: 40)
        transcript = []
        observer = lambda do |turn:, effect:, observation:|
          transcript << "#{turn}: #{effect} -> #{observation}"
          bus&.publish("core:turn", turn:, effect: effect.to_s, ok: observation.ok?, detail: observation.message)
        end

        done = Master::Core::Fold.new(
          model:       model || Master::Core::Model.new,
          constitution: Master::Core::Constitution.load(data_dir: Master.data_path),
          world:       Master::Core::World.new(root:),
          memory:      Master::Core::Memory.new,
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
